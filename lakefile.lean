import Lake
open Lake DSL System

package selene where
  version := v!"0.1.0"
  precompileModules := true

require crucible from git "https://github.com/nathanial/crucible" @ "v0.0.9"

@[default_target]
lean_lib Selene where
  roots := #[`Selene]

lean_lib Tests where
  roots := #[`Tests]

@[test_driver]
lean_exe selene_tests where
  root := `Tests.Main

-- Compile all Lua source files
-- Uses a script target that compiles everything and returns a single .o via ld -r
target lua_o pkg : FilePath := do
  let oFile := pkg.buildDir / "native" / "lua.o"
  let luaDir := pkg.dir / "native" / "lua"
  let srcFiles := #[
    "lapi.c", "lcode.c", "lctype.c", "ldebug.c", "ldo.c", "ldump.c",
    "lfunc.c", "lgc.c", "llex.c", "lmem.c", "lobject.c", "lopcodes.c",
    "lparser.c", "lstate.c", "lstring.c", "ltable.c", "ltm.c",
    "lundump.c", "lvm.c", "lzio.c", "lauxlib.c", "lbaselib.c",
    "lcorolib.c", "ldblib.c", "liolib.c", "lmathlib.c", "loadlib.c",
    "loslib.c", "lstrlib.c", "ltablib.c", "lutf8lib.c", "linit.c"
  ]
  -- Track first source file for initial check (all should be present if one is)
  let firstSrc := luaDir / "lapi.c"
  buildFileAfterDep oFile (← inputTextFile firstSrc) fun _ => do
    IO.FS.createDirAll (pkg.buildDir / "native" / "lua_objs")
    -- Compile each file
    for src in srcFiles do
      let srcFile := luaDir / src
      let objFile := pkg.buildDir / "native" / "lua_objs" / (src.dropRight 2 ++ ".o")
      proc {
        cmd := "cc"
        args := #["-c", "-DLUA_USE_MACOSX", "-fPIC", "-O2",
                  "-I", luaDir.toString,
                  "-o", objFile.toString, srcFile.toString]
        cwd := some pkg.dir
      }
    -- Combine all .o files into one using ld -r
    let objFiles := srcFiles.map fun src =>
      (pkg.buildDir / "native" / "lua_objs" / (src.dropRight 2 ++ ".o")).toString
    proc {
      cmd := "ld"
      args := #["-r", "-o", oFile.toString] ++ objFiles
      cwd := some pkg.dir
    }

-- FFI bridge
target selene_ffi_o pkg : FilePath := do
  let oFile := pkg.buildDir / "native" / "selene_ffi.o"
  let srcFile := pkg.dir / "native" / "src" / "selene_ffi.c"
  let luaInclude := pkg.dir / "native" / "lua"
  let leanIncludeDir ← getLeanIncludeDir
  buildO oFile (← inputTextFile srcFile) #[
    "-I", leanIncludeDir.toString,
    "-I", luaInclude.toString,
    "-fPIC",
    "-O2"
  ] #[] "cc" getLeanTrace

extern_lib selene_native pkg := do
  let name := nameToStaticLib "selene_native"
  let luaO ← lua_o.fetch
  let ffiO ← selene_ffi_o.fetch
  buildStaticLib (pkg.buildDir / "lib" / name) #[luaO, ffiO]
