/-
  Selene.Core.Error
  Error handling for Lua operations
-/

namespace Selene

/-- Errors that can occur during Lua operations -/
inductive LuaError where
  | runtime (msg : String) (trace : Option String)
  | syntax (msg : String) (trace : Option String)
  | memory
  | handler (msg : String) (trace : Option String)
  | type (expected : String) (got : String)
  | conversion (fromType : String) (toType : String)
  deriving Repr, Inhabited

namespace LuaError

def traceSuffix : Option String → String
  | some t => s!"\n{t}"
  | none => ""

instance : ToString LuaError where
  toString e := match e with
    | .runtime msg trace => s!"Lua runtime error: {msg}" ++ traceSuffix trace
    | .syntax msg trace => s!"Lua syntax error: {msg}" ++ traceSuffix trace
    | .memory => "Lua memory allocation error"
    | .handler msg trace => s!"Lua error handler error: {msg}" ++ traceSuffix trace
    | .type expected got => s!"Type error: expected {expected}, got {got}"
    | .conversion fromType toType => s!"Conversion error: cannot convert {fromType} to {toType}"

def ofStatus (status : Int) (msg : String := "") (trace : Option String := none) : LuaError :=
  if status == 2 then .runtime msg trace
  else if status == 3 then .syntax msg trace
  else if status == 4 then .memory
  else if status == 5 then .handler msg trace
  else .runtime msg trace

end LuaError

/-- Result type for Lua operations -/
abbrev LuaResult (α : Type) := Except LuaError α

end Selene
