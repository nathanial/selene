/-
  Selene.FFI.Stack
  Low-level FFI declarations for Lua stack manipulation
-/
import Selene.FFI.Types

namespace Selene.FFI

/-- Push nil onto stack -/
@[extern "selene_push_nil"]
opaque pushNil : @& LuaState → IO Unit

/-- Push boolean onto stack -/
@[extern "selene_push_boolean"]
opaque pushBoolean : @& LuaState → Bool → IO Unit

/-- Push number (Float) onto stack -/
@[extern "selene_push_number"]
opaque pushNumber : @& LuaState → Float → IO Unit

/-- Push integer onto stack -/
@[extern "selene_push_integer"]
opaque pushInteger : @& LuaState → Int → IO Unit

/-- Push string onto stack -/
@[extern "selene_push_string"]
opaque pushString : @& LuaState → @& String → IO Unit

/-- Get boolean from stack at index -/
@[extern "selene_to_boolean"]
opaque toBoolean : @& LuaState → Int → IO Bool

/-- Get number from stack at index -/
@[extern "selene_to_number"]
opaque toNumber : @& LuaState → Int → IO Float

/-- Get integer from stack at index -/
@[extern "selene_to_integer"]
opaque toInteger : @& LuaState → Int → IO Int

/-- Get string from stack at index -/
@[extern "selene_to_string"]
opaque toString : @& LuaState → Int → IO String

/-- Get type of value at stack index -/
@[extern "selene_type"]
opaque luaType : @& LuaState → Int → IO Int

/-- Get type name for type code -/
@[extern "selene_typename"]
opaque typeName : @& LuaState → Int → IO String

/-- Pop n elements from stack -/
@[extern "selene_pop"]
opaque pop : @& LuaState → UInt32 → IO Unit

/-- Get current stack top (number of elements) -/
@[extern "selene_get_top"]
opaque getTop : @& LuaState → IO Int

/-- Set stack top (can grow or shrink) -/
@[extern "selene_set_top"]
opaque setTop : @& LuaState → Int → IO Unit

/-- Push copy of element at given index -/
@[extern "selene_push_value"]
opaque pushValue : @& LuaState → Int → IO Unit

/-- Check stack space -/
@[extern "selene_check_stack"]
opaque checkStack : @& LuaState → UInt32 → IO Bool

/-- Is the value at index nil? -/
@[extern "selene_is_nil"]
opaque isNil : @& LuaState → Int → IO Bool

/-- Is the value at index a boolean? -/
@[extern "selene_is_boolean"]
opaque isBoolean : @& LuaState → Int → IO Bool

/-- Is the value at index a number? -/
@[extern "selene_is_number"]
opaque isNumber : @& LuaState → Int → IO Bool

/-- Is the value at index an integer? -/
@[extern "selene_is_integer"]
opaque isInteger : @& LuaState → Int → IO Bool

/-- Is the value at index a string? -/
@[extern "selene_is_string"]
opaque isString : @& LuaState → Int → IO Bool

/-- Is the value at index a table? -/
@[extern "selene_is_table"]
opaque isTable : @& LuaState → Int → IO Bool

/-- Is the value at index a function? -/
@[extern "selene_is_function"]
opaque isFunction : @& LuaState → Int → IO Bool

end Selene.FFI
