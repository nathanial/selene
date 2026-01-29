/-
  Selene.FFI.Types
  Opaque FFI handle types for Lua
-/

namespace Selene.FFI

/-- Opaque handle to lua_State -/
opaque LuaStatePointed : NonemptyType
def LuaState := LuaStatePointed.type
instance : Nonempty LuaState := LuaStatePointed.property

/-- Opaque handle to a Lua registry reference -/
opaque LuaRefPointed : NonemptyType
def LuaRef := LuaRefPointed.type
instance : Nonempty LuaRef := LuaRefPointed.property

/-- Lua type codes -/
def LUA_TNONE : Int := -1
def LUA_TNIL : Int := 0
def LUA_TBOOLEAN : Int := 1
def LUA_TLIGHTUSERDATA : Int := 2
def LUA_TNUMBER : Int := 3
def LUA_TSTRING : Int := 4
def LUA_TTABLE : Int := 5
def LUA_TFUNCTION : Int := 6
def LUA_TUSERDATA : Int := 7
def LUA_TTHREAD : Int := 8

/-- Lua status codes -/
def LUA_OK : Int := 0
def LUA_YIELD : Int := 1
def LUA_ERRRUN : Int := 2
def LUA_ERRSYNTAX : Int := 3
def LUA_ERRMEM : Int := 4
def LUA_ERRERR : Int := 5

/-- Special registry index for references -/
def LUA_REGISTRYINDEX : Int := -1001000

end Selene.FFI
