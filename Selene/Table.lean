/-
  Selene.Table
  High-level Lua table operations
-/
import Selene.State

namespace Selene

namespace State

/-- Create a new empty table and return it as a Value -/
def newTable (s : State) : IO Value := do
  FFI.newTable s.raw
  let ref ← FFI.ref s.raw
  return .table ref

/-- Create a new table with pre-allocated space -/
def newTableSized (s : State) (arraySize : Nat) (hashSize : Nat) : IO Value := do
  FFI.createTable s.raw arraySize.toUInt32 hashSize.toUInt32
  let ref ← FFI.ref s.raw
  return .table ref

/-- Get a field from a table by string key -/
def tableGet (s : State) (table : Value) (key : String) : IO Value := do
  match table with
  | .table ref =>
    FFI.pushRef s.raw ref
    let _ ← FFI.getField s.raw (-1) key
    let v ← FFI.toValue s.raw (-1)
    FFI.pop s.raw 2
    return v
  | _ => return .nil

/-- Set a field in a table by string key -/
def tableSet (s : State) (table : Value) (key : String) (value : Value) : IO Unit := do
  match table with
  | .table ref =>
    FFI.pushRef s.raw ref
    FFI.pushFromValue s.raw value
    FFI.setField s.raw (-2) key
    FFI.pop s.raw 1
  | _ => pure ()

/-- Get an array element from a table by integer index (1-based) -/
def tableGetI (s : State) (table : Value) (idx : Nat) : IO Value := do
  match table with
  | .table ref =>
    FFI.pushRef s.raw ref
    let _ ← FFI.rawGetI s.raw (-1) (Int.ofNat idx)
    let v ← FFI.toValue s.raw (-1)
    FFI.pop s.raw 2
    return v
  | _ => return .nil

/-- Set an array element in a table by integer index (1-based) -/
def tableSetI (s : State) (table : Value) (idx : Nat) (value : Value) : IO Unit := do
  match table with
  | .table ref =>
    FFI.pushRef s.raw ref
    FFI.pushFromValue s.raw value
    FFI.rawSetI s.raw (-2) (Int.ofNat idx)
    FFI.pop s.raw 1
  | _ => pure ()

/-- Get the length of a table (array part) -/
def tableLen (s : State) (table : Value) : IO Nat := do
  match table with
  | .table ref =>
    FFI.pushRef s.raw ref
    let len ← FFI.rawLen s.raw (-1)
    FFI.pop s.raw 1
    return len.toNat
  | _ => return 0

/-- Iterate over all key-value pairs in a table -/
def tableForEach (s : State) (table : Value) (f : Value → Value → IO Unit) : IO Unit := do
  match table with
  | .table ref =>
    FFI.pushRef s.raw ref
    FFI.pushNil s.raw  -- First key
    while ← FFI.next s.raw (-2) do
      let value ← FFI.toValue s.raw (-1)
      let key ← FFI.toValue s.raw (-2)
      FFI.pop s.raw 1  -- Pop value, keep key for next iteration
      f key value
    FFI.pop s.raw 1  -- Pop table
  | _ => pure ()

/-- Collect all key-value pairs from a table -/
def tableToArray (s : State) (table : Value) : IO (Array (Value × Value)) := do
  let pairsRef ← IO.mkRef #[]
  s.tableForEach table fun k v => do
    pairsRef.modify (·.push (k, v))
  pairsRef.get

/-- Create a table from an array (1-indexed) -/
def arrayToTable (s : State) (arr : Array Value) : IO Value := do
  let table ← s.newTableSized arr.size 0
  for h : i in [0:arr.size] do
    s.tableSetI table (i + 1) arr[i]
  return table

/-- Create a table from key-value pairs -/
def pairsToTable (s : State) (pairs : Array (String × Value)) : IO Value := do
  let table ← s.newTableSized 0 pairs.size
  for (k, v) in pairs do
    s.tableSet table k v
  return table

/-- Check if a table has a given key -/
def tableHas (s : State) (table : Value) (key : String) : IO Bool := do
  let v ← s.tableGet table key
  return !v.isNil

end State
end Selene
