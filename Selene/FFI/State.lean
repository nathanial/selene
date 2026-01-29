/-
  Selene.FFI.State
  Low-level FFI declarations for Lua state lifecycle
-/
import Selene.FFI.Types

namespace Selene.FFI

/-- Create a new Lua state without standard libraries -/
@[extern "selene_state_new"]
opaque stateNew : IO LuaState

/-- Create a new Lua state with all standard libraries loaded -/
@[extern "selene_state_new_with_libs"]
opaque stateNewWithLibs : IO LuaState

/-- Close/destroy a Lua state -/
@[extern "selene_state_close"]
opaque stateClose : @& LuaState → IO Unit

/-- Execute a Lua string, returns error message on failure -/
@[extern "selene_do_string"]
opaque doString : @& LuaState → @& String → IO (Option String)

/-- Load and execute a Lua file, returns error message on failure -/
@[extern "selene_do_file"]
opaque doFile : @& LuaState → @& String → IO (Option String)

/-- Protected call of function on stack with nargs arguments and nresults results.
    Returns status code (LUA_OK on success). -/
@[extern "selene_pcall"]
opaque pcall : @& LuaState → UInt32 → UInt32 → IO Int

/-- Get Lua version number -/
@[extern "selene_version"]
opaque luaVersion : @& LuaState → IO Float

end Selene.FFI
