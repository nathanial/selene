/-
  Selene.FFI.Table
  Low-level FFI declarations for Lua table operations
-/
import Selene.FFI.Types

namespace Selene.FFI

/-- Create a new empty table and push it onto the stack -/
@[extern "selene_new_table"]
opaque newTable : @& LuaState → IO Unit

/-- Create a new table with pre-allocated space -/
@[extern "selene_create_table"]
opaque createTable : @& LuaState → UInt32 → UInt32 → IO Unit

/-- Get table[key] where table is at index, key is on top of stack.
    Pops key and pushes result. Returns type of value. -/
@[extern "selene_get_table"]
opaque getTable : @& LuaState → Int → IO Int

/-- Set table[key] = value where table is at index,
    key is second from top, value is on top. Pops both. -/
@[extern "selene_set_table"]
opaque setTable : @& LuaState → Int → IO Unit

/-- Get table.name where table is at index. Pushes result. Returns type. -/
@[extern "selene_get_field"]
opaque getField : @& LuaState → Int → @& String → IO Int

/-- Set table.name = value where table is at index, value is on top. Pops value. -/
@[extern "selene_set_field"]
opaque setField : @& LuaState → Int → @& String → IO Unit

/-- Get global variable by name. Pushes result. Returns type. -/
@[extern "selene_get_global"]
opaque getGlobal : @& LuaState → @& String → IO Int

/-- Set global variable. Value is on top of stack. Pops value. -/
@[extern "selene_set_global"]
opaque setGlobal : @& LuaState → @& String → IO Unit

/-- Get metatable for value at index. Pushes metatable and returns true if present. -/
@[extern "selene_get_metatable"]
opaque getMetatable : @& LuaState → Int → IO Bool

/-- Set metatable for value at index. Metatable is on top of stack and is popped. -/
@[extern "selene_set_metatable"]
opaque setMetatable : @& LuaState → Int → IO Bool

/-- Get raw length of table/string at index -/
@[extern "selene_raw_len"]
opaque rawLen : @& LuaState → Int → IO UInt64

/-- Get table[i] where table is at index. Pushes result. Returns type.
    Uses raw access (no metamethods). -/
@[extern "selene_raw_geti"]
opaque rawGetI : @& LuaState → Int → Int → IO Int

/-- Set table[i] = value where table is at index, value is on top. Pops value.
    Uses raw access (no metamethods). -/
@[extern "selene_raw_seti"]
opaque rawSetI : @& LuaState → Int → Int → IO Unit

/-- Iterate table: pops key, pushes next key-value pair.
    Returns true if there are more pairs, false when iteration complete. -/
@[extern "selene_next"]
opaque next : @& LuaState → Int → IO Bool

end Selene.FFI
