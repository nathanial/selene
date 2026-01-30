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

test "Table metatable get/set" := do
  let lua ← State.new
  let t ← lua.newTable
  let mt ← lua.newTable
  lua.tableSet mt "tag" (Value.integer 123)
  let ok ← lua.setMetatable t (some mt)
  ensure ok "Expected setMetatable success"

  let mtVal ← lua.getMetatable t
  match mtVal with
  | some mtTable =>
    let tag ← lua.tableGet mtTable "tag"
    match tag with
    | .integer n => n ≡ 123
    | _ => throw (IO.userError "Expected metatable tag")
  | none => throw (IO.userError "Expected metatable")

  let cleared ← lua.setMetatable t none
  ensure cleared "Expected clear metatable success"

  let mtVal2 ← lua.getMetatable t
  match mtVal2 with
  | none => pure ()
  | some _ => throw (IO.userError "Expected no metatable after clear")

  lua.close

test "Userdata metatable get/set" := do
  let lua ← State.new
  let ioVal ← lua.getGlobal "io"
  let stdoutVal ← lua.tableGet ioVal "stdout"
  match stdoutVal with
  | .userdata _ =>
    let mt ← lua.newTable
    lua.tableSet mt "tag" (Value.integer 7)
    let ok ← lua.setMetatable stdoutVal (some mt)
    ensure ok "Expected setMetatable on userdata"
    let mtVal ← lua.getMetatable stdoutVal
    match mtVal with
    | some mtTable =>
      let tag ← lua.tableGet mtTable "tag"
      match tag with
      | .integer n => n ≡ 7
      | _ => throw (IO.userError "Expected userdata metatable tag")
    | none => throw (IO.userError "Expected userdata metatable")
  | _ => throw (IO.userError "Expected userdata value")
  lua.close

test "Userdata finalizer" := do
  let lua ← State.new
  let finalized ← IO.mkRef false
  let ud ← lua.newUserdataWithFinalizer (finalized.set true)
  lua.setGlobal "ud" ud
  lua.release ud
  lua.exec! "ud = nil; collectgarbage('collect'); collectgarbage('collect')"
  let wasFinalized ← finalized.get
  ensure wasFinalized "Expected userdata finalizer to run"
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

test "Coroutine basic creation" := do
  let lua ← State.new
  lua.exec! "function simple() return 42 end"
  let co ← lua.newCoroutine "simple"
  let canRes ← co.canResume
  ensure canRes "Should be able to resume new coroutine"
  lua.close

test "Coroutine yield and resume" := do
  let lua ← State.new
  lua.exec! "function gen() coroutine.yield(1); coroutine.yield(2); return 3 end"
  let co ← lua.newCoroutine "gen"

  -- First resume: yields 1
  let r1 ← co.resume
  match r1 with
  | .yielded vals =>
    vals.size ≡ 1
    match vals[0]? with
    | some (Value.integer 1) => pure ()
    | _ => throw (IO.userError s!"Expected integer 1, got {vals[0]?}")
  | _ => throw (IO.userError s!"Expected yielded, got {repr r1}")

  -- Second resume: yields 2
  let r2 ← co.resume
  match r2 with
  | .yielded vals =>
    vals.size ≡ 1
    match vals[0]? with
    | some (Value.integer 2) => pure ()
    | _ => throw (IO.userError s!"Expected integer 2, got {vals[0]?}")
  | _ => throw (IO.userError s!"Expected yielded, got {repr r2}")

  -- Third resume: finishes with 3
  let r3 ← co.resume
  match r3 with
  | .finished vals =>
    vals.size ≡ 1
    match vals[0]? with
    | some (Value.integer 3) => pure ()
    | _ => throw (IO.userError s!"Expected integer 3, got {vals[0]?}")
  | _ => throw (IO.userError s!"Expected finished, got {repr r3}")

  lua.close

test "Coroutine with arguments" := do
  let lua ← State.new
  lua.exec! "function add(a, b) coroutine.yield(a + b); return a * b end"
  let co ← lua.newCoroutine "add"

  -- Resume with arguments
  let r1 ← co.resume #[Value.integer 3, Value.integer 4]
  match r1 with
  | .yielded vals =>
    vals.size ≡ 1
    match vals[0]? with
    | some (Value.integer 7) => pure ()  -- 3 + 4 = 7
    | _ => throw (IO.userError s!"Expected integer 7, got {vals[0]?}")
  | _ => throw (IO.userError s!"Expected yielded, got {repr r1}")

  -- Resume to finish
  let r2 ← co.resume
  match r2 with
  | .finished vals =>
    vals.size ≡ 1
    match vals[0]? with
    | some (Value.integer 12) => pure ()  -- 3 * 4 = 12
    | _ => throw (IO.userError s!"Expected integer 12, got {vals[0]?}")
  | _ => throw (IO.userError s!"Expected finished, got {repr r2}")

  lua.close

test "Coroutine error handling" := do
  let lua ← State.new
  lua.exec! "function err() error('test error') end"
  let co ← lua.newCoroutine "err"

  let result ← co.resume
  match result with
  | .error _ => pure ()
  | _ => throw (IO.userError s!"Expected error, got {repr result}")

  lua.close

test "Coroutine status check" := do
  let lua ← State.new
  lua.exec! "function simple() coroutine.yield(); return 1 end"
  let co ← lua.newCoroutine "simple"

  -- Should be suspended initially (has function to run)
  let canResume1 ← co.canResume
  ensure canResume1 "Should be resumable initially"

  -- Resume once (yields)
  let _ ← co.resume
  let canResume2 ← co.canResume
  ensure canResume2 "Should be resumable after yield"

  -- Resume again (finishes)
  let _ ← co.resume
  let canResume3 ← co.canResume
  ensure (!canResume3) "Should not be resumable after finish"

  lua.close

test "Wrap existing thread" := do
  let lua ← State.new
  lua.exec! "co = coroutine.create(function() coroutine.yield(42); return 100 end)"

  let coVal ← lua.getGlobal "co"
  match coVal with
  | .thread _ =>
    let co ← lua.wrapThread coVal

    let r1 ← co.resume
    match r1 with
    | .yielded vals =>
      match vals[0]? with
      | some (Value.integer 42) => pure ()
      | _ => throw (IO.userError s!"Expected 42, got {vals[0]?}")
    | _ => throw (IO.userError s!"Expected yielded, got {repr r1}")

    let r2 ← co.resume
    match r2 with
    | .finished vals =>
      match vals[0]? with
      | some (Value.integer 100) => pure ()
      | _ => throw (IO.userError s!"Expected 100, got {vals[0]?}")
    | _ => throw (IO.userError s!"Expected finished, got {repr r2}")
  | _ => throw (IO.userError s!"Expected thread value, got {coVal}")

  lua.close

test "Coroutine multiple values" := do
  let lua ← State.new
  lua.exec! "function multi() coroutine.yield(1, 2, 3); return 4, 5 end"
  let co ← lua.newCoroutine "multi"

  let r1 ← co.resume
  match r1 with
  | .yielded vals =>
    vals.size ≡ 3
    match vals[0]?, vals[1]?, vals[2]? with
    | some (Value.integer 1), some (Value.integer 2), some (Value.integer 3) => pure ()
    | _, _, _ => throw (IO.userError s!"Expected 1,2,3 got {repr vals}")
  | _ => throw (IO.userError s!"Expected yielded, got {repr r1}")

  let r2 ← co.resume
  match r2 with
  | .finished vals =>
    vals.size ≡ 2
    match vals[0]?, vals[1]? with
    | some (Value.integer 4), some (Value.integer 5) => pure ()
    | _, _ => throw (IO.userError s!"Expected 4,5 got {repr vals}")
  | _ => throw (IO.userError s!"Expected finished, got {repr r2}")

  lua.close

test "Coroutine running and yieldable" := do
  let lua ← State.new
  let (running, isMain) ← lua.runningCoroutine
  ensure isMain "Expected running coroutine to be main thread"
  let runStatus ← running.getStatus
  runStatus ≡ .running
  let mainYieldable ← running.isYieldable
  ensure (!mainYieldable) "Main thread should not be yieldable"
  let mainYieldable2 ← lua.isYieldable
  ensure (!mainYieldable2) "Expected main thread not yieldable"

  lua.exec! "function simple() coroutine.yield(); return 1 end"
  let co ← lua.newCoroutine "simple"
  let coYieldable ← co.isYieldable
  ensure coYieldable "Coroutine should be yieldable"
  lua.close

test "Coroutine wrap" := do
  let lua ← State.new
  lua.exec! "function gen() coroutine.yield(10); return 20 end"
  let co ← lua.newCoroutine "gen"
  let wrapped := co.wrap

  let r1 ← wrapped #[]
  r1.size ≡ 1
  match r1[0]? with
  | some (Value.integer 10) => pure ()
  | _ => throw (IO.userError s!"Expected 10, got {r1[0]?}")

  let r2 ← wrapped #[]
  r2.size ≡ 1
  match r2[0]? with
  | some (Value.integer 20) => pure ()
  | _ => throw (IO.userError s!"Expected 20, got {r2[0]?}")

  lua.close

test "Coroutine close" := do
  let lua ← State.new
  lua.exec! "function gen() coroutine.yield(1); return 2 end"
  let co ← lua.newCoroutine "gen"

  let _ ← co.resume
  let closeResult ← co.close
  match closeResult with
  | .ok _ => pure ()
  | .error e => throw (IO.userError (toString e))

  let status ← co.getStatus
  status ≡ .dead
  lua.close

test "Coroutine hooks" := do
  let lua ← State.new
  lua.exec! "function gen() coroutine.yield(1); return 2 end"
  let co ← lua.newCoroutine "gen"
  let events ← IO.mkRef (#[] : Array String)
  let hooks : CoroutineHooks := {
    onResume := fun _ => events.modify (fun evs => evs.push "resume")
    onYield := fun _ => events.modify (fun evs => evs.push "yield")
    onFinish := fun _ => events.modify (fun evs => evs.push "finish")
    onError := fun _ => events.modify (fun evs => evs.push "error")
    onClose := fun _ => events.modify (fun evs => evs.push "close")
  }

  let _ ← co.resumeWithHooks hooks
  let _ ← co.resumeWithHooks hooks
  let _ ← co.closeWithHooks hooks

  let evs ← events.get
  evs.size ≡ 5
  match evs[0]?, evs[1]?, evs[2]?, evs[3]?, evs[4]? with
  | some "resume", some "yield", some "resume", some "finish", some "close" => pure ()
  | _, _, _, _, _ => throw (IO.userError s!"Unexpected events {repr evs}")

  lua.close

test "Coroutine yield from Lean" := do
  let lua ← State.new
  let step ← IO.mkRef (0 : Nat)
  lua.registerYielding "stepper" fun args => do
    let n ← step.get
    if n == 0 then
      step.set 1
      return .yielded #[Value.integer 10]
    else
      let v := args.getD 0 .nil
      return .returned #[v]

  lua.exec! "function run() return stepper() end"
  let co ← lua.newCoroutine "run"

  let r1 ← co.resume
  match r1 with
  | .yielded vals =>
    vals.size ≡ 1
    match vals[0]? with
    | some (Value.integer 10) => pure ()
    | _ => throw (IO.userError s!"Expected 10, got {vals[0]?}")
  | _ => throw (IO.userError s!"Expected yielded, got {repr r1}")

  let r2 ← co.resume #[Value.integer 99]
  match r2 with
  | .finished vals =>
    vals.size ≡ 1
    match vals[0]? with
    | some (Value.integer 99) => pure ()
    | _ => throw (IO.userError s!"Expected 99, got {vals[0]?}")
  | _ => throw (IO.userError s!"Expected finished, got {repr r2}")

  lua.close

end Tests.Selene

def main (args : List String) : IO UInt32 := runAllSuitesFiltered args
