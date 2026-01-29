/-
  Selene.Core.Convert
  Type conversion between Lean and Lua values
-/
import Selene.Core.Value
import Selene.Core.Error

namespace Selene

/-- Typeclass for converting Lean values to Lua values -/
class ToLua (α : Type) where
  toLua : α → Value

/-- Typeclass for converting Lua values to Lean values -/
class FromLua (α : Type) where
  fromLua : Value → LuaResult α

-- ToLua instances
instance : ToLua Unit where
  toLua _ := .nil

instance : ToLua Bool where
  toLua b := .bool b

instance : ToLua Int where
  toLua n := .integer n

instance : ToLua UInt8 where
  toLua n := .integer n.toNat

instance : ToLua UInt16 where
  toLua n := .integer n.toNat

instance : ToLua UInt32 where
  toLua n := .integer n.toNat

instance : ToLua UInt64 where
  toLua n := .integer n.toNat

instance : ToLua Nat where
  toLua n := .integer n

instance : ToLua Float where
  toLua f := .number f

instance : ToLua String where
  toLua s := .string s

instance : ToLua Value where
  toLua v := v

instance [ToLua α] : ToLua (Option α) where
  toLua
    | none => .nil
    | some a => ToLua.toLua a

instance [ToLua α] : ToLua (Array α) where
  toLua _ := .nil  -- Tables need state, handled at higher level

-- FromLua instances
instance : FromLua Unit where
  fromLua _ := .ok ()

instance : FromLua Bool where
  fromLua v := match v with
    | .bool b => .ok b
    | .nil => .ok false
    | _ => .ok true  -- Lua truthiness

instance : FromLua Int where
  fromLua v := match v with
    | .integer n => .ok n
    | .number f => .ok (Int.ofNat f.toUInt64.toNat)
    | _ => .error (.type "number" v.getTypeName)

instance : FromLua Nat where
  fromLua v := match v with
    | .integer n => if n >= 0 then .ok n.toNat else .error (.conversion "negative integer" "Nat")
    | .number f => if f >= 0 then .ok f.toUInt64.toNat else .error (.conversion "negative number" "Nat")
    | _ => .error (.type "number" v.getTypeName)

instance : FromLua UInt8 where
  fromLua v := match v with
    | .integer n => .ok (n.toNat.toUInt8)
    | .number f => .ok (f.toUInt8)
    | _ => .error (.type "number" v.getTypeName)

instance : FromLua UInt16 where
  fromLua v := match v with
    | .integer n => .ok (n.toNat.toUInt16)
    | .number f => .ok (f.toUInt16)
    | _ => .error (.type "number" v.getTypeName)

instance : FromLua UInt32 where
  fromLua v := match v with
    | .integer n => .ok (n.toNat.toUInt32)
    | .number f => .ok (f.toUInt32)
    | _ => .error (.type "number" v.getTypeName)

instance : FromLua UInt64 where
  fromLua v := match v with
    | .integer n => .ok (n.toNat.toUInt64)
    | .number f => .ok (f.toUInt64)
    | _ => .error (.type "number" v.getTypeName)

instance : FromLua Float where
  fromLua v := match v with
    | .number f => .ok f
    | .integer n => .ok (Float.ofInt n)
    | _ => .error (.type "number" v.getTypeName)

instance : FromLua String where
  fromLua v := match v with
    | .string s => .ok s
    | .integer n => .ok (toString n)
    | .number f => .ok (toString f)
    | _ => .error (.type "string" v.getTypeName)

instance : FromLua Value where
  fromLua v := .ok v

instance [FromLua α] : FromLua (Option α) where
  fromLua v := match v with
    | .nil => .ok none
    | _ => match FromLua.fromLua v with
      | .ok a => .ok (some a)
      | .error e => .error e

end Selene
