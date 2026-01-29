# Selene Roadmap

This document outlines planned features and improvements for the Selene Lua-Lean 4 integration library.

## Current Status (v0.1.0)

- [x] Core FFI bindings for Lua 5.4.7
- [x] State lifecycle management
- [x] Global variable get/set with type conversion
- [x] Type-safe function registration (1-4 args, pure and IO)
- [x] Lua function calling with multiple return values
- [x] Table creation, field access, and iteration
- [x] Value type mapping (nil, bool, number, integer, string, table, function, userdata, thread)
- [x] ToLua/FromLua typeclasses for automatic conversion
- [x] Error handling with LuaError type
- [x] Protected calls (pcall)

## Short Term

### v0.2.0 - Enhanced Type Safety

- [ ] **Coroutine support**: Create, resume, and yield Lua coroutines from Lean
- [ ] **Metatables**: Get/set metatables on tables and userdata
- [ ] **Userdata**: Create Lean-managed userdata with custom finalizers
- [ ] **Better error messages**: Include Lua stack traces in error types
- [ ] **FromLua for tuples**: `FromLua (α × β)` to destructure multiple returns

### v0.3.0 - Advanced Features

- [ ] **Module system**: Load Lua modules with `require` support
- [ ] **Sandboxing**: Create restricted Lua environments for untrusted code
- [ ] **Debug hooks**: Line/call/return hooks for debugging and profiling
- [ ] **Weak tables**: Support for weak keys/values
- [ ] **Registry access**: Direct access to Lua registry for advanced use cases

## Medium Term

### v0.4.0 - Performance

- [ ] **Zero-copy strings**: Avoid string copies where possible
- [ ] **Cached function refs**: Reuse LuaRef for frequently-called functions
- [ ] **Batch operations**: Push/pop multiple values efficiently
- [ ] **Benchmarks**: Performance test suite comparing to direct C calls

### v0.5.0 - Ecosystem Integration

- [ ] **JSON bridge**: Convert between Lua tables and Lean JSON (via a JSON library)
- [ ] **Reactive integration**: Fire Reactive events from Lua callbacks
- [ ] **Config files**: Load Lua files as configuration with schema validation
- [ ] **REPL**: Interactive Lua REPL with Lean function access

## Long Term

### v1.0.0 - Stability

- [ ] **API stabilization**: Finalize public API
- [ ] **Documentation**: Comprehensive user guide and API reference
- [ ] **Examples**: Collection of example projects
- [ ] **Cross-platform testing**: Verify Linux and Windows compatibility

### Future Ideas

- **LuaJIT support**: Alternative backend using LuaJIT for performance
- **Typed Lua**: Integration with typed Lua dialects (Teal, TypeScriptToLua)
- **Hot reloading**: Reload Lua scripts without restarting Lean application
- **Bidirectional tables**: Lean data structures that appear as Lua tables
- **Async/await**: Lean Tasks that can be awaited from Lua coroutines

## Contributing

Contributions are welcome! If you'd like to work on any of these items:

1. Open an issue to discuss the approach
2. Reference this roadmap in your PR description
3. Include tests for new functionality

## Versioning

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR**: Breaking API changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes, backwards compatible
