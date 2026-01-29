/-
  Selene.Coroutine
  High-level Lua coroutine wrapper
-/
import Selene.FFI.Types
import Selene.FFI.Coroutine
import Selene.FFI.Stack
import Selene.FFI.Table
import Selene.FFI.Function
import Selene.Core.Value
import Selene.Core.Error

namespace Selene

/-- Status of a coroutine -/
inductive CoroutineStatus where
  | suspended  -- Can be resumed
  | running    -- Currently running
  | normal     -- Active but not running (resumed another coroutine)
  | dead       -- Finished or errored
  deriving Repr, Inhabited, BEq

instance : ToString CoroutineStatus where
  toString
    | .suspended => "suspended"
    | .running => "running"
    | .normal => "normal"
    | .dead => "dead"

namespace CoroutineStatus

def fromStatusCode (status : Int) : CoroutineStatus :=
  if status == 0 then
    .running
  else if status == 1 then
    .dead
  else if status == 2 then
    .suspended
  else if status == 3 then
    .normal
  else
    .dead

def fromLuaStatus (status : Int) (isYieldable : Bool) : CoroutineStatus :=
  let _ := isYieldable
  fromStatusCode status

end CoroutineStatus

/-- Result of resuming a coroutine -/
inductive ResumeResult where
  | yielded (values : Array Value)    -- Coroutine yielded with values
  | finished (values : Array Value)   -- Coroutine finished with return values
  | error (err : LuaError)            -- Coroutine errored
  deriving Repr, Inhabited

/-- Hooks for coroutine lifecycle events -/
structure CoroutineHooks where
  onResume : Array Value → IO Unit := fun _ => pure ()
  onYield : Array Value → IO Unit := fun _ => pure ()
  onFinish : Array Value → IO Unit := fun _ => pure ()
  onError : LuaError → IO Unit := fun _ => pure ()
  onClose : LuaResult Unit → IO Unit := fun _ => pure ()

/-- High-level coroutine handle -/
structure Coroutine where
  /-- Parent Lua state that owns this coroutine -/
  parent : FFI.LuaState
  /-- Registry reference to the thread (keeps it alive) -/
  thread : FFI.LuaThread

namespace Coroutine

/-- Get the current status of the coroutine -/
def getStatus (co : Coroutine) : IO CoroutineStatus := do
  let status ← FFI.coroutineStatus co.parent co.thread
  return CoroutineStatus.fromStatusCode status

/-- Alias for getStatus -/
def status (co : Coroutine) : IO CoroutineStatus :=
  co.getStatus

/-- Check if the coroutine can be resumed -/
def canResume (co : Coroutine) : IO Bool := do
  let status ← co.getStatus
  return status == .suspended

/-- Check if the coroutine is yieldable -/
def isYieldable (co : Coroutine) : IO Bool :=
  FFI.isYieldable co.thread

/-- Resume the coroutine with arguments, returning results or error -/
def resume (co : Coroutine) (args : Array Value := #[]) : IO ResumeResult := do
  -- Push arguments onto coroutine stack
  for arg in args do
    FFI.coPushFromValue co.thread arg

  -- Resume with number of arguments
  let (status, nresults) ← FFI.resume co.thread args.size.toUInt32

  if status == FFI.LUA_OK then
    -- Coroutine finished, collect return values
    let mut results := #[]
    for i in [1:nresults.toNat + 1] do
      let v ← FFI.coToValue co.thread (Int.ofNat i)
      results := results.push v
    FFI.coPop co.thread nresults.toNat.toUInt32
    return .finished results
  else if status == FFI.LUA_YIELD then
    -- Coroutine yielded, collect yielded values
    let mut results := #[]
    for i in [1:nresults.toNat + 1] do
      let v ← FFI.coToValue co.thread (Int.ofNat i)
      results := results.push v
    FFI.coPop co.thread nresults.toNat.toUInt32
    return .yielded results
  else
    -- Error occurred
    let errMsg ← FFI.coToValue co.thread (-1)
    FFI.coPop co.thread 1
    let msg := match errMsg with
      | .string s => s
      | _ => "Unknown coroutine error"
    return .error (LuaError.ofStatus status msg)

/-- Resume the coroutine with lifecycle hooks. -/
def resumeWithHooks (co : Coroutine) (hooks : CoroutineHooks) (args : Array Value := #[]) : IO ResumeResult := do
  hooks.onResume args
  let result ← co.resume args
  match result with
  | .yielded values => hooks.onYield values
  | .finished values => hooks.onFinish values
  | .error err => hooks.onError err
  return result

/-- Close the coroutine thread -/
def close (co : Coroutine) : IO (LuaResult Unit) := do
  let status ← co.getStatus
  match status with
  | .running | .normal =>
    return .error (.runtime s!"cannot close a {status} coroutine")
  | .suspended | .dead =>
    let closeStatus ← FFI.closeThread co.parent co.thread
    if closeStatus == FFI.LUA_OK then
      return .ok ()
    else
      let errMsg ← FFI.coToValue co.thread (-1)
      FFI.coPop co.thread 1
      let msg := match errMsg with
        | .string s => s
        | _ => "Unknown coroutine error"
      return .error (LuaError.ofStatus closeStatus msg)

/-- Close the coroutine thread with lifecycle hooks. -/
def closeWithHooks (co : Coroutine) (hooks : CoroutineHooks) : IO (LuaResult Unit) := do
  let result ← co.close
  hooks.onClose result
  return result

/-- Wrap the coroutine in a function that resumes it and throws on error. -/
def wrap (co : Coroutine) : Array Value → IO (Array Value) :=
  fun args => do
    let result ← co.resume args
    match result with
    | .yielded values => pure values
    | .finished values => pure values
    | .error err => throw (IO.userError (toString err))

end Coroutine

end Selene
