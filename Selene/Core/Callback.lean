/-
  Selene.Core.Callback
  Results for Lean callbacks that can yield to Lua coroutines
-/
import Selene.Core.Value

namespace Selene

/-- Result of a yielding Lua callback. -/
inductive CallbackResult where
  | returned (values : Array Value)
  | yielded (values : Array Value)
  deriving Repr, Inhabited

namespace CallbackResult

def returnValues (values : Array Value := #[]) : CallbackResult :=
  .returned values

def yieldValues (values : Array Value := #[]) : CallbackResult :=
  .yielded values

end CallbackResult

end Selene
