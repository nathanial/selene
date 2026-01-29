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

namespace CoroutineStatus

def fromLuaStatus (status : Int) (isYieldable : Bool) : CoroutineStatus :=
  if status == FFI.LUA_OK then
    -- LUA_OK means coroutine finished (dead) or is the main thread
    .dead
  else if status == FFI.LUA_YIELD then
    .suspended
  else
    -- Error status means dead
    .dead

end CoroutineStatus

/-- Result of resuming a coroutine -/
inductive ResumeResult where
  | yielded (values : Array Value)    -- Coroutine yielded with values
  | finished (values : Array Value)   -- Coroutine finished with return values
  | error (err : LuaError)            -- Coroutine errored
  deriving Repr, Inhabited

/-- High-level coroutine handle -/
structure Coroutine where
  /-- Parent Lua state that owns this coroutine -/
  parent : FFI.LuaState
  /-- Registry reference to the thread (keeps it alive) -/
  thread : FFI.LuaThread

namespace Coroutine

/-- Get the current status of the coroutine -/
def getStatus (co : Coroutine) : IO CoroutineStatus := do
  let status ← FFI.status co.thread
  if status == FFI.LUA_OK then
    -- Need to check if it's actually finished or just started
    let top ← FFI.coGetTop co.thread
    if top == 0 then
      return .dead
    else
      return .suspended
  else if status == FFI.LUA_YIELD then
    return .suspended
  else
    return .dead

/-- Check if the coroutine can be resumed -/
def canResume (co : Coroutine) : IO Bool := do
  let status ← co.getStatus
  return status == .suspended

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

end Coroutine

end Selene
