import Lake
open Lake DSL

package selene where
  version := v!"0.1.0"

require crucible from git "https://github.com/nathanial/crucible" @ "v0.0.9"

@[default_target]
lean_lib Uselene where
  roots := #[`Uselene]

lean_lib Tests where
  roots := #[`Tests]

@[test_driver]
lean_exe selene_tests where
  root := `Tests.Main
