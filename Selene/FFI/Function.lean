/-
  Selene.FFI.Function
  Low-level FFI declarations for Lua function operations
-/
import Selene.FFI.Types
import Selene.Core.Value
import Selene.Core.Callback

namespace Selene.FFI

/-- Call function on stack with nargs arguments, expecting nresults results.
    Function and args are popped, results are pushed. -/
@[extern "selene_call"]
opaque call : @& LuaState → UInt32 → UInt32 → IO Unit

/-- Register a Lean function as a Lua global.
    The callback receives arguments as an array and returns an array of results. -/
@[extern "selene_register_function"]
opaque registerFunction : @& LuaState → @& String → (Array Selene.Value → IO (Array Selene.Value)) → IO Unit

/-- Register a Lean function as a Lua global that can yield.
    The callback receives arguments as an array and returns a CallbackResult. -/
@[extern "selene_register_yielding_function"]
opaque registerYieldingFunction :
  @& LuaState → @& String → (Array Selene.Value → IO Selene.CallbackResult) → IO Unit

/-- Create a reference to the value on top of stack in the registry.
    Pops the value and returns a LuaRef. -/
@[extern "selene_ref"]
opaque ref : @& LuaState → IO LuaRef

/-- Release a registry reference -/
@[extern "selene_unref"]
opaque unref : @& LuaState → @& LuaRef → IO Unit

/-- Push the value associated with a registry reference onto the stack -/
@[extern "selene_push_ref"]
opaque pushRef : @& LuaState → @& LuaRef → IO Unit

/-- Convert stack value at index to a Lean Value -/
@[extern "selene_to_value"]
opaque toValue : @& LuaState → Int → IO Selene.Value

/-- Push a Lean Value onto the Lua stack -/
@[extern "selene_push_from_value"]
opaque pushFromValue : @& LuaState → @& Selene.Value → IO Unit

end Selene.FFI
