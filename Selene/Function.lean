/-
  Selene.Function
  Type-safe function registration
-/
import Selene.State

namespace Selene
namespace State

private def nilValue : Value := Value.nil

/-- Register a 0-argument function -/
def register0 (s : State) (name : String) (f : IO α) [ToLua α] : IO Unit :=
  s.registerGlobal name fun (_ : Array Value) => do
    let result ← f
    return #[ToLua.toLua result]

/-- Register a 1-argument function -/
def register1 (s : State) (name : String) (f : α → β) [FromLua α] [ToLua β] : IO Unit :=
  s.registerGlobal name fun (args : Array Value) => do
    let a := args.getD 0 nilValue
    match FromLua.fromLua a with
    | .ok aVal =>
      let result := f aVal
      return #[ToLua.toLua result]
    | .error e =>
      throw (IO.userError (toString e))

/-- Register a 2-argument function -/
def register2 (s : State) (name : String) (f : α → β → γ) [FromLua α] [FromLua β] [ToLua γ] : IO Unit :=
  s.registerGlobal name fun (args : Array Value) => do
    let a := args.getD 0 nilValue
    let b := args.getD 1 nilValue
    match FromLua.fromLua a, FromLua.fromLua b with
    | .ok aVal, .ok bVal =>
      let result := f aVal bVal
      return #[ToLua.toLua result]
    | .error e, _ => throw (IO.userError (toString e))
    | _, .error e => throw (IO.userError (toString e))

/-- Register a 3-argument function -/
def register3 (s : State) (name : String) (f : α → β → γ → δ)
    [FromLua α] [FromLua β] [FromLua γ] [ToLua δ] : IO Unit :=
  s.registerGlobal name fun (args : Array Value) => do
    let a := args.getD 0 nilValue
    let b := args.getD 1 nilValue
    let c := args.getD 2 nilValue
    match FromLua.fromLua a, FromLua.fromLua b, FromLua.fromLua c with
    | .ok aVal, .ok bVal, .ok cVal =>
      let result := f aVal bVal cVal
      return #[ToLua.toLua result]
    | .error e, _, _ => throw (IO.userError (toString e))
    | _, .error e, _ => throw (IO.userError (toString e))
    | _, _, .error e => throw (IO.userError (toString e))

/-- Register a 4-argument function -/
def register4 (s : State) (name : String) (f : α → β → γ → δ → ε)
    [FromLua α] [FromLua β] [FromLua γ] [FromLua δ] [ToLua ε] : IO Unit :=
  s.registerGlobal name fun (args : Array Value) => do
    let a := args.getD 0 nilValue
    let b := args.getD 1 nilValue
    let c := args.getD 2 nilValue
    let d := args.getD 3 nilValue
    match FromLua.fromLua a, FromLua.fromLua b, FromLua.fromLua c, FromLua.fromLua d with
    | .ok aVal, .ok bVal, .ok cVal, .ok dVal =>
      let result := f aVal bVal cVal dVal
      return #[ToLua.toLua result]
    | .error e, _, _, _ => throw (IO.userError (toString e))
    | _, .error e, _, _ => throw (IO.userError (toString e))
    | _, _, .error e, _ => throw (IO.userError (toString e))
    | _, _, _, .error e => throw (IO.userError (toString e))

/-- Register a 1-argument IO function -/
def registerIO1 (s : State) (name : String) (f : α → IO β) [FromLua α] [ToLua β] : IO Unit :=
  s.registerGlobal name fun (args : Array Value) => do
    let a := args.getD 0 nilValue
    match FromLua.fromLua a with
    | .ok aVal =>
      let result ← f aVal
      return #[ToLua.toLua result]
    | .error e =>
      throw (IO.userError (toString e))

/-- Register a 2-argument IO function -/
def registerIO2 (s : State) (name : String) (f : α → β → IO γ) [FromLua α] [FromLua β] [ToLua γ] : IO Unit :=
  s.registerGlobal name fun (args : Array Value) => do
    let a := args.getD 0 nilValue
    let b := args.getD 1 nilValue
    match FromLua.fromLua a, FromLua.fromLua b with
    | .ok aVal, .ok bVal =>
      let result ← f aVal bVal
      return #[ToLua.toLua result]
    | .error e, _ => throw (IO.userError (toString e))
    | _, .error e => throw (IO.userError (toString e))

/-- Register a 3-argument IO function -/
def registerIO3 (s : State) (name : String) (f : α → β → γ → IO δ)
    [FromLua α] [FromLua β] [FromLua γ] [ToLua δ] : IO Unit :=
  s.registerGlobal name fun (args : Array Value) => do
    let a := args.getD 0 nilValue
    let b := args.getD 1 nilValue
    let c := args.getD 2 nilValue
    match FromLua.fromLua a, FromLua.fromLua b, FromLua.fromLua c with
    | .ok aVal, .ok bVal, .ok cVal =>
      let result ← f aVal bVal cVal
      return #[ToLua.toLua result]
    | .error e, _, _ => throw (IO.userError (toString e))
    | _, .error e, _ => throw (IO.userError (toString e))
    | _, _, .error e => throw (IO.userError (toString e))

/-- Register a variadic function (receives all args as array) -/
def registerVariadic (s : State) (name : String) (f : Array Value → IO (Array Value)) : IO Unit :=
  s.registerGlobal name f

end State
end Selene
