/-
  Selene.FFI.Coroutine
  Low-level FFI declarations for Lua coroutine operations
-/
import Selene.FFI.Types
import Selene.Core.Value

namespace Selene.FFI

/-- Handle to a coroutine thread (stored as a registry reference). -/
abbrev LuaThread := LuaRef
instance : Nonempty LuaThread := inferInstance

/-- Create a new coroutine thread and return its registry reference. -/
@[extern "selene_new_thread"]
opaque newThread : @& LuaState → IO LuaThread

/-- Get the currently running thread and whether it is the main thread. -/
@[extern "selene_running_thread"]
opaque runningThread : @& LuaState → IO (LuaThread × Bool)

/-- Validate a thread reference and return it. -/
@[extern "selene_thread_state"]
opaque threadState : @& LuaState → @& LuaRef → IO LuaThread

/-- Resume a coroutine with nargs arguments on its stack.
    Returns (status, nresults) where status is LUA_OK or LUA_YIELD on success. -/
@[extern "selene_resume"]
opaque resume : @& LuaThread → UInt32 → IO (Int × Int)

/-- Get coroutine status following Lua coroutine.status semantics. -/
@[extern "selene_coroutine_status"]
opaque coroutineStatus : @& LuaState → @& LuaThread → IO Int

/-- Get the status of a coroutine -/
@[extern "selene_status"]
opaque status : @& LuaThread → IO Int

/-- Close a coroutine thread (Lua 5.4) -/
@[extern "selene_close_thread"]
opaque closeThread : @& LuaState → @& LuaThread → IO Int

/-- Check if a coroutine can yield -/
@[extern "selene_is_yieldable"]
opaque isYieldable : @& LuaThread → IO Bool

/-- Check if value at stack index is a thread -/
@[extern "selene_is_thread"]
opaque isThread : @& LuaState → Int → IO Bool

/-- Get thread at stack index -/
@[extern "selene_to_thread"]
opaque toThread : @& LuaState → Int → IO LuaThread

/-- Move n values from one thread to another -/
@[extern "selene_xmove"]
opaque xmove : @& LuaThread → @& LuaThread → UInt32 → IO Unit

/-- Move n values from LuaState to LuaThread -/
@[extern "selene_xmove_to_thread"]
opaque xmoveToThread : @& LuaState → @& LuaThread → UInt32 → IO Unit

/-- Move n values from LuaThread to LuaState -/
@[extern "selene_xmove_from_thread"]
opaque xmoveFromThread : @& LuaThread → @& LuaState → UInt32 → IO Unit

/-- Get top of coroutine stack -/
@[extern "selene_co_get_top"]
opaque coGetTop : @& LuaThread → IO Int

/-- Get value from coroutine stack -/
@[extern "selene_co_to_value"]
opaque coToValue : @& LuaThread → Int → IO Selene.Value

/-- Pop values from coroutine stack -/
@[extern "selene_co_pop"]
opaque coPop : @& LuaThread → UInt32 → IO Unit

/-- Push value onto coroutine stack -/
@[extern "selene_co_push_from_value"]
opaque coPushFromValue : @& LuaThread → @& Selene.Value → IO Unit

end Selene.FFI
