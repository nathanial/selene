/-
  Selene
  Lua-Lean 4 Integration Library
-/
import Selene.FFI.Types
import Selene.FFI.State
import Selene.FFI.Stack
import Selene.FFI.Table
import Selene.FFI.Function
import Selene.FFI.Coroutine
import Selene.Core.Value
import Selene.Core.Error
import Selene.Core.Callback
import Selene.Core.Convert
import Selene.State
import Selene.Table
import Selene.Function
import Selene.Coroutine

namespace Selene

-- Re-export commonly used types
export FFI (LuaState LuaRef LuaThread)
export Value (nil bool number integer string table function userdata thread)

namespace State

/-- Create a new coroutine from a global function name -/
def newCoroutine (s : State) (funcName : String) : IO Coroutine := do
  -- Create new thread (stored in registry)
  let thread ← FFI.newThread s.raw
  -- Get the function and move it to coroutine stack
  let _ ← FFI.getGlobal s.raw funcName
  FFI.xmoveToThread s.raw thread 1
  return ⟨s.raw, thread⟩

/-- Create a coroutine from a function Value -/
def coroutineFromFunction (s : State) (func : Value) : IO Coroutine := do
  match func with
  | .function ref =>
    -- Create new thread (stored in registry)
    let thread ← FFI.newThread s.raw
    -- Push function onto parent stack, then move to coroutine stack
    FFI.pushRef s.raw ref
    FFI.xmoveToThread s.raw thread 1
    return ⟨s.raw, thread⟩
  | _ => throw (IO.userError "Expected function value")

/-- Create a coroutine from a function Value (alias). -/
def createCoroutine (s : State) (func : Value) : IO Coroutine :=
  s.coroutineFromFunction func

/-- Wrap an existing Lua thread Value as a Coroutine -/
def wrapThread (s : State) (v : Value) : IO Coroutine := do
  match v with
  | .thread ref =>
    let thread ← FFI.threadState s.raw ref
    return ⟨s.raw, thread⟩
  | _ => throw (IO.userError "Expected thread value")

/-- Get the currently running coroutine and whether it is the main thread. -/
def runningCoroutine (s : State) : IO (Coroutine × Bool) := do
  let result ← FFI.runningThread s.raw
  let thread := result.fst
  let isMain := result.snd
  return (⟨s.raw, thread⟩, isMain)

/-- Check if the current thread is yieldable. -/
def isYieldable (s : State) : IO Bool := do
  let result ← s.runningCoroutine
  let co := result.fst
  co.isYieldable

/-- Wrap a function Value into a resume wrapper (like coroutine.wrap). -/
def coroutineWrap (s : State) (func : Value) : IO (Array Value → IO (Array Value)) := do
  let co ← s.coroutineFromFunction func
  return co.wrap

end State

end Selene
