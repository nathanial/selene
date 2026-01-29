/-
  Selene.Core.Error
  Error handling for Lua operations
-/

namespace Selene

/-- Errors that can occur during Lua operations -/
inductive LuaError where
  | runtime (msg : String)
  | syntax (msg : String)
  | memory
  | handler (msg : String)
  | type (expected : String) (got : String)
  | conversion (fromType : String) (toType : String)
  deriving Repr, Inhabited

namespace LuaError

instance : ToString LuaError where
  toString e := match e with
    | .runtime msg => s!"Lua runtime error: {msg}"
    | .syntax msg => s!"Lua syntax error: {msg}"
    | .memory => "Lua memory allocation error"
    | .handler msg => s!"Lua error handler error: {msg}"
    | .type expected got => s!"Type error: expected {expected}, got {got}"
    | .conversion fromType toType => s!"Conversion error: cannot convert {fromType} to {toType}"

def ofStatus (status : Int) (msg : String := "") : LuaError :=
  if status == 2 then .runtime msg
  else if status == 3 then .syntax msg
  else if status == 4 then .memory
  else if status == 5 then .handler msg
  else .runtime msg

end LuaError

/-- Result type for Lua operations -/
abbrev LuaResult (α : Type) := Except LuaError α

end Selene
