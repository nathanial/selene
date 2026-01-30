/-
  Selene.FFI.Userdata
  Low-level FFI declarations for Lua userdata operations
-/
import Selene.FFI.Types

namespace Selene.FFI

/-- Create a new userdata with a Lean finalizer (IO Unit) and return its registry reference. -/
@[extern "selene_new_userdata"]
opaque newUserdata : @& LuaState → (IO Unit) → IO LuaRef

end Selene.FFI
