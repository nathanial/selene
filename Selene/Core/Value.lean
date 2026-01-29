/-
  Selene.Core.Value
  Lua value types mapping to Lean types
-/
import Selene.FFI.Types

namespace Selene

/-- Lua value types -/
inductive Value : Type where
  | nil
  | bool (v : Bool)
  | number (v : Float)
  | integer (v : Int)
  | string (v : String)
  | table (ref : FFI.LuaRef)
  | function (ref : FFI.LuaRef)
  | userdata (ref : FFI.LuaRef)
  | thread (ref : FFI.LuaRef)
  deriving Inhabited

instance : Repr Value where
  reprPrec v _ := match v with
    | .nil => "Value.nil"
    | .bool b => s!"Value.bool {repr b}"
    | .number f => s!"Value.number {repr f}"
    | .integer n => s!"Value.integer {repr n}"
    | .string s => s!"Value.string {repr s}"
    | .table _ => "Value.table <ref>"
    | .function _ => "Value.function <ref>"
    | .userdata _ => "Value.userdata <ref>"
    | .thread _ => "Value.thread <ref>"

namespace Value

instance : BEq Value where
  beq a b := match a, b with
    | .nil, .nil => true
    | .bool x, .bool y => x == y
    | .number x, .number y => x == y || (x.isNaN && y.isNaN)
    | .integer x, .integer y => x == y
    | .string x, .string y => x == y
    | _, _ => false

instance : ToString Value where
  toString v := match v with
    | .nil => "nil"
    | .bool b => if b then "true" else "false"
    | .number f => toString f
    | .integer n => toString n
    | .string s => s!"\"{s}\""
    | .table _ => "<table>"
    | .function _ => "<function>"
    | .userdata _ => "<userdata>"
    | .thread _ => "<thread>"

def asBool? : Value → Option Bool
  | .bool b => some b
  | .nil => some false
  | _ => none

def asInt? : Value → Option Int
  | .integer n => some n
  | .number f => some (Int.ofNat f.toUInt64.toNat)
  | _ => none

def asFloat? : Value → Option Float
  | .number f => some f
  | .integer n => some (Float.ofInt n)
  | _ => none

def asString? : Value → Option String
  | .string s => some s
  | _ => none

def isNil : Value → Bool
  | .nil => true
  | _ => false

def isTruthy : Value → Bool
  | .nil => false
  | .bool false => false
  | _ => true

def getTypeCode : Value → Int
  | .nil => FFI.LUA_TNIL
  | .bool _ => FFI.LUA_TBOOLEAN
  | .number _ => FFI.LUA_TNUMBER
  | .integer _ => FFI.LUA_TNUMBER
  | .string _ => FFI.LUA_TSTRING
  | .table _ => FFI.LUA_TTABLE
  | .function _ => FFI.LUA_TFUNCTION
  | .userdata _ => FFI.LUA_TUSERDATA
  | .thread _ => FFI.LUA_TTHREAD

def getTypeName : Value → String
  | .nil => "nil"
  | .bool _ => "boolean"
  | .number _ => "number"
  | .integer _ => "number"
  | .string _ => "string"
  | .table _ => "table"
  | .function _ => "function"
  | .userdata _ => "userdata"
  | .thread _ => "thread"

end Value
end Selene
