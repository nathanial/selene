/-
  Selene.State
  High-level Lua state wrapper
-/
import Selene.FFI.State
import Selene.FFI.Stack
import Selene.FFI.Table
import Selene.FFI.Function
import Selene.FFI.Userdata
import Selene.Core.Value
import Selene.Core.Error
import Selene.Core.Callback
import Selene.Core.Convert

namespace Selene

/-- High-level wrapper around a Lua state -/
structure State where
  raw : FFI.LuaState

namespace State

/-- Create a new Lua state with standard libraries -/
def new : IO State := do
  let raw ← FFI.stateNewWithLibs
  return ⟨raw⟩

/-- Create a new bare Lua state without standard libraries -/
def newBare : IO State := do
  let raw ← FFI.stateNew
  return ⟨raw⟩

/-- Close the Lua state -/
def close (s : State) : IO Unit :=
  FFI.stateClose s.raw

/-- Execute a Lua string, throwing on error -/
def exec! (s : State) (code : String) : IO Unit := do
  match ← FFI.doString s.raw code with
  | none => pure ()
  | some err => throw (IO.userError err)

/-- Execute a Lua string, returning result -/
def exec (s : State) (code : String) : IO (LuaResult Unit) := do
  match ← FFI.doString s.raw code with
  | none => pure (.ok ())
  | some err => pure (.error (.runtime err))

/-- Load and execute a Lua file, throwing on error -/
def execFile! (s : State) (path : String) : IO Unit := do
  match ← FFI.doFile s.raw path with
  | none => pure ()
  | some err => throw (IO.userError err)

/-- Load and execute a Lua file, returning result -/
def execFile (s : State) (path : String) : IO (LuaResult Unit) := do
  match ← FFI.doFile s.raw path with
  | none => pure (.ok ())
  | some err => pure (.error (.runtime err))

/-- Get a global variable as a Value -/
def getGlobal (s : State) (name : String) : IO Value := do
  let _ ← FFI.getGlobal s.raw name
  let v ← FFI.toValue s.raw (-1)
  FFI.pop s.raw 1
  return v

/-- Get a global variable with type conversion -/
def getGlobalAs (s : State) (name : String) [FromLua α] : IO (LuaResult α) := do
  let v ← s.getGlobal name
  return FromLua.fromLua v

/-- Set a global variable from a Value -/
def setGlobal (s : State) (name : String) (v : Value) : IO Unit := do
  FFI.pushFromValue s.raw v
  FFI.setGlobal s.raw name

/-- Set a global variable with type conversion -/
def setGlobalFrom (s : State) (name : String) (v : α) [ToLua α] : IO Unit :=
  s.setGlobal name (ToLua.toLua v)

/-- Call a Lua function by name with arguments and return results -/
def call (s : State) (funcName : String) (args : Array Value) : IO (Array Value) := do
  let _ ← FFI.getGlobal s.raw funcName
  for arg in args do
    FFI.pushFromValue s.raw arg
  FFI.call s.raw args.size.toUInt32 0xFFFFFFFF  -- LUA_MULTRET
  let nResults ← FFI.getTop s.raw
  let mut results := #[]
  -- Results are at stack positions 1 through nResults
  for i in [1:nResults.toNat + 1] do
    let v ← FFI.toValue s.raw (Int.ofNat i)
    results := results.push v
  FFI.pop s.raw nResults.toNat.toUInt32
  return results

/-- Call a Lua function and return single result -/
def call1 (s : State) (funcName : String) (args : Array Value) : IO Value := do
  let results ← s.call funcName args
  return results.getD 0 .nil

/-- Protected call - returns error instead of throwing -/
def pcall (s : State) (funcName : String) (args : Array Value) : IO (LuaResult (Array Value)) := do
  let _ ← FFI.getGlobal s.raw funcName
  for arg in args do
    FFI.pushFromValue s.raw arg
  let status ← FFI.pcall s.raw args.size.toUInt32 0xFFFFFFFF
  if status == FFI.LUA_OK then
    let nResults ← FFI.getTop s.raw
    let mut results := #[]
    -- Results are at stack positions 1 through nResults
    for i in [1:nResults.toNat + 1] do
      let v ← FFI.toValue s.raw (Int.ofNat i)
      results := results.push v
    FFI.pop s.raw nResults.toNat.toUInt32
    return .ok results
  else
    let err ← FFI.toString s.raw (-1)
    FFI.pop s.raw 1
    return .error (LuaError.ofStatus status err)

/-- Register a Lean function as a Lua global -/
def registerGlobal (s : State) (name : String) (f : Array Value → IO (Array Value)) : IO Unit :=
  FFI.registerFunction s.raw name f

/-- Register a Lean function as a Lua global that can yield -/
def registerYielding (s : State) (name : String) (f : Array Value → IO CallbackResult) : IO Unit :=
  FFI.registerYieldingFunction s.raw name f

/-- Get the current Lua version -/
def version (s : State) : IO Float :=
  FFI.luaVersion s.raw

/-- Get number of elements on the stack -/
def stackSize (s : State) : IO Nat := do
  let top ← FFI.getTop s.raw
  return top.toNat

/-- Release a registry reference held by a Value. -/
def release (s : State) (v : Value) : IO Unit := do
  match v with
  | .table ref | .function ref | .userdata ref | .thread ref =>
    FFI.unref s.raw ref
  | _ => pure ()

/-- Create a new userdata with a no-op finalizer. -/
def newUserdata (s : State) : IO Value := do
  let ref ← FFI.newUserdata s.raw (pure ())
  return .userdata ref

/-- Create a new userdata with a custom finalizer. -/
def newUserdataWithFinalizer (s : State) (finalizer : IO Unit) : IO Value := do
  let ref ← FFI.newUserdata s.raw finalizer
  return .userdata ref

/-- Get metatable for a table or userdata value. -/
def getMetatable (s : State) (v : Value) : IO (Option Value) := do
  match v with
  | .table ref | .userdata ref =>
    FFI.pushRef s.raw ref
    let hasMeta ← FFI.getMetatable s.raw (-1)
    if hasMeta then
      let mt ← FFI.toValue s.raw (-1)
      FFI.pop s.raw 2
      return some mt
    else
      FFI.pop s.raw 1
      return none
  | _ => return none

/-- Set metatable for a table or userdata value. Returns true on success. -/
def setMetatable (s : State) (v : Value) (mt : Option Value) : IO Bool := do
  match v with
  | .table ref | .userdata ref =>
    FFI.pushRef s.raw ref
    match mt with
    | none =>
      FFI.pushNil s.raw
      let ok ← FFI.setMetatable s.raw (-2)
      FFI.pop s.raw 1
      return ok
    | some (.table metaRef) =>
      FFI.pushRef s.raw metaRef
      let ok ← FFI.setMetatable s.raw (-2)
      FFI.pop s.raw 1
      return ok
    | some _ =>
      FFI.pop s.raw 1
      return false
  | _ => return false

end State
end Selene
