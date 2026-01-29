/-
  Selene Tests
-/
import Crucible
import Selene

open Crucible
open Selene

namespace Tests.Selene

testSuite "Selene"

test "State creation" := do
  let lua ← State.new
  let ver ← lua.version
  ensure (ver >= 504.0) "Expected Lua 5.4+"
  lua.close

test "Basic script execution" := do
  let lua ← State.new
  lua.exec! "x = 1 + 2"
  let x ← lua.getGlobalAs (α := Int) "x"
  match x with
  | .ok n => n ≡ 3
  | .error e => throw (IO.userError (toString e))
  lua.close

test "Global variable get/set" := do
  let lua ← State.new
  lua.setGlobalFrom "myNum" (42 : Int)
  lua.setGlobalFrom "myStr" "hello"
  lua.setGlobalFrom "myBool" true

  let num ← lua.getGlobalAs (α := Int) "myNum"
  let str ← lua.getGlobalAs (α := String) "myStr"
  let b ← lua.getGlobalAs (α := Bool) "myBool"

  match num, str, b with
  | .ok n, .ok s, .ok bb =>
    n ≡ 42
    s ≡ "hello"
    ensure bb "Expected true"
  | _, _, _ => throw (IO.userError "Type conversion failed")
  lua.close

test "Function registration" := do
  let lua ← State.new
  lua.register2 "add" (fun (a : Int) (b : Int) => a + b)
  lua.exec! "result = add(10, 20)"
  let result ← lua.getGlobalAs (α := Int) "result"
  match result with
  | .ok n => n ≡ 30
  | .error e => throw (IO.userError (toString e))
  lua.close

test "Calling Lua functions" := do
  let lua ← State.new
  lua.exec! "function double(x) return x * 2 end"
  let result ← lua.call1 "double" #[Value.integer 21]
  match result with
  | .integer n => n ≡ 42
  | _ => throw (IO.userError s!"Expected integer, got {result}")
  lua.close

test "Table creation and access" := do
  let lua ← State.new
  let table ← lua.newTable
  lua.tableSet table "name" (Value.string "test")
  lua.tableSet table "value" (Value.integer 123)

  let name ← lua.tableGet table "name"
  let value ← lua.tableGet table "value"

  match name, value with
  | .string s, .integer n =>
    s ≡ "test"
    n ≡ 123
  | _, _ => throw (IO.userError "Unexpected types in table")
  lua.close

test "Table array operations" := do
  let lua ← State.new
  let arr ← lua.arrayToTable #[Value.integer 10, Value.integer 20, Value.integer 30]

  let v1 ← lua.tableGetI arr 1
  let v2 ← lua.tableGetI arr 2
  let v3 ← lua.tableGetI arr 3

  match v1, v2, v3 with
  | .integer a, .integer b, .integer c =>
    a ≡ 10
    b ≡ 20
    c ≡ 30
  | _, _, _ => throw (IO.userError "Unexpected types in array")

  let len ← lua.tableLen arr
  len ≡ 3
  lua.close

test "Value conversion round-trip" := do
  let lua ← State.new

  lua.setGlobal "vNil" Value.nil
  lua.setGlobal "vBool" (Value.bool true)
  lua.setGlobal "vNum" (Value.number 3.14)
  lua.setGlobal "vInt" (Value.integer 42)
  lua.setGlobal "vStr" (Value.string "hello")

  let vNil ← lua.getGlobal "vNil"
  let vBool ← lua.getGlobal "vBool"
  let vNum ← lua.getGlobal "vNum"
  let vInt ← lua.getGlobal "vInt"
  let vStr ← lua.getGlobal "vStr"

  ensure vNil.isNil "Expected nil"
  match vBool with
  | .bool bb => ensure bb "Expected true"
  | _ => throw (IO.userError "Expected bool")
  match vNum with
  | .number f => ensure (f > 3.0 && f < 4.0) "Expected ~3.14"
  | _ => throw (IO.userError "Expected number")
  match vInt with
  | .integer n => n ≡ 42
  | _ => throw (IO.userError "Expected integer")
  match vStr with
  | .string s => s ≡ "hello"
  | _ => throw (IO.userError "Expected string")
  lua.close

test "Error handling" := do
  let lua ← State.new
  let result ← lua.exec "invalid lua syntax @@#$"
  match result with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "Expected syntax error")
  lua.close

test "Multiple return values" := do
  let lua ← State.new
  lua.exec! "function multi() return 1, 2, 3 end"
  let results ← lua.call "multi" #[]
  results.size ≡ 3
  match results[0]?, results[1]?, results[2]? with
  | some (Value.integer 1), some (Value.integer 2), some (Value.integer 3) => pure ()
  | _, _, _ => throw (IO.userError "Unexpected return values")
  lua.close

test "IO function registration" := do
  let lua ← State.new
  let counter ← IO.mkRef (0 : Nat)
  lua.registerIO1 "increment" fun (n : Nat) => do
    counter.modify (· + n)
    counter.get
  lua.exec! "x = increment(5)"
  lua.exec! "y = increment(3)"
  let total ← counter.get
  total ≡ 8
  lua.close

test "Protected call" := do
  let lua ← State.new
  lua.exec! "function failfn() error('intentional error') end"
  let result ← lua.pcall "failfn" #[]
  match result with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "Expected error from pcall")
  lua.close

end Tests.Selene

def main (args : List String) : IO UInt32 := runAllSuitesFiltered args
