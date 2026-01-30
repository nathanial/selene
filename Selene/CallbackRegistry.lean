/-
  Selene.CallbackRegistry
  Lean-side registry for Lua callbacks (avoid holding closures in C)
-/
import Selene.Core.Value
import Selene.Core.Callback
import Std.Data.HashMap

namespace Selene

open Std

private structure Registry where
  nextId : UInt64
  normal : HashMap UInt64 (Array Value → IO (Array Value))
  yielding : HashMap UInt64 (Array Value → IO CallbackResult)
  deriving Inhabited

private def emptyRegistry : Registry :=
  { nextId := 1, normal := {}, yielding := {} }

initialize registryRef : IO.Ref Registry ← IO.mkRef emptyRegistry

private def freshId : IO UInt64 := do
  let r ← registryRef.get
  let id := r.nextId
  registryRef.set { r with nextId := r.nextId + 1 }
  return id

/-- Register a non-yielding callback and return its id. -/
def registerCallback (f : Array Value → IO (Array Value)) : IO UInt64 := do
  let id ← freshId
  registryRef.modify fun r => { r with normal := r.normal.insert id f }
  return id

/-- Register a yielding callback and return its id. -/
def registerYieldingCallback (f : Array Value → IO CallbackResult) : IO UInt64 := do
  let id ← freshId
  registryRef.modify fun r => { r with yielding := r.yielding.insert id f }
  return id

/-- Unregister a non-yielding callback. -/
def unregisterCallback (id : UInt64) : IO Unit :=
  registryRef.modify fun r => { r with normal := r.normal.erase id }

/-- Unregister a yielding callback. -/
def unregisterYieldingCallback (id : UInt64) : IO Unit :=
  registryRef.modify fun r => { r with yielding := r.yielding.erase id }

/-- Invoke a non-yielding callback by id. -/
def invokeCallback (id : UInt64) (args : Array Value) : IO (Array Value) := do
  let r ← registryRef.get
  match r.normal.get? id with
  | some f => f args
  | none => throw (IO.userError s!"Unknown callback id {id}")

/-- Invoke a yielding callback by id. -/
def invokeYieldingCallback (id : UInt64) (args : Array Value) : IO CallbackResult := do
  let r ← registryRef.get
  match r.yielding.get? id with
  | some f => f args
  | none => throw (IO.userError s!"Unknown yielding callback id {id}")

@[export selene_callback_invoke]
def callbackInvoke (id : UInt64) (args : Array Value) : IO (Array Value) :=
  invokeCallback id args

@[export selene_yielding_callback_invoke]
def yieldingCallbackInvoke (id : UInt64) (args : Array Value) : IO CallbackResult :=
  invokeYieldingCallback id args

@[export selene_callback_release]
def callbackRelease (id : UInt64) : IO Unit :=
  unregisterCallback id

@[export selene_yielding_callback_release]
def yieldingCallbackRelease (id : UInt64) : IO Unit :=
  unregisterYieldingCallback id

end Selene
