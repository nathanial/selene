import Crucible
open Crucible

suite "selene" do
  test "placeholder" do
    check (1 + 1 = 2)

def main : IO UInt32 := runAllSuites
