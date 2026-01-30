/*
 * Selene FFI Implementation
 * C bindings for Lua with external class registration
 */

#include <lean/lean.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <string.h>
#include <stdlib.h>

/* ========================================================================== */
/* External Class Registration                                                 */
/* ========================================================================== */

static lean_external_class* g_lua_state_class = NULL;
static lean_external_class* g_lua_ref_class = NULL;

/* Ref wrapper to track Lua state for cleanup */
typedef struct {
    lua_State* L;
    int ref;
} LuaRefWrapper;

/* ========================================================================== */
/* Finalizers                                                                  */
/* ========================================================================== */

static void lua_state_finalizer(void* ptr) {
    lua_State* L = (lua_State*)ptr;
    if (L) {
        lua_close(L);
    }
}

static void lua_ref_finalizer(void* ptr) {
    LuaRefWrapper* wrapper = (LuaRefWrapper*)ptr;
    if (wrapper) {
        if (wrapper->L && wrapper->ref != LUA_NOREF) {
            luaL_unref(wrapper->L, LUA_REGISTRYINDEX, wrapper->ref);
        }
        free(wrapper);
    }
}

static void noop_foreach(void* ptr, b_lean_obj_arg arg) {
    (void)ptr;
    (void)arg;
}

/* ========================================================================== */
/* Initialization                                                              */
/* ========================================================================== */

static void init_external_classes(void) {
    if (g_lua_state_class == NULL) {
        g_lua_state_class = lean_register_external_class(lua_state_finalizer, noop_foreach);
        g_lua_ref_class = lean_register_external_class(lua_ref_finalizer, noop_foreach);
    }
}

static lean_object* mk_io_error(const char* msg) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(msg)));
}

/* ========================================================================== */
/* Value Conversion                                                            */
/* ========================================================================== */

/*
 * Selene.Value layout:
 *   | nil                           -- tag 0, 0 fields
 *   | bool (v : Bool)               -- tag 1, 1 field (UInt8 scalar)
 *   | number (v : Float)            -- tag 2, 0 obj fields, Float scalar
 *   | integer (v : Int)             -- tag 3, 1 obj field (Int)
 *   | string (v : String)           -- tag 4, 1 obj field
 *   | table (ref : LuaRef)          -- tag 5, 1 obj field
 *   | function (ref : LuaRef)       -- tag 6, 1 obj field
 *   | userdata (ref : LuaRef)       -- tag 7, 1 obj field
 *   | thread (ref : LuaRef)         -- tag 8, 1 obj field
 */

/* Convert Lua stack value to Lean Value */
static lean_object* lua_to_lean_value(lua_State* L, int idx) {
    int type = lua_type(L, idx);
    lean_object* obj;

    switch (type) {
        case LUA_TNIL:
            return lean_alloc_ctor(0, 0, 0);

        case LUA_TBOOLEAN: {
            int b = lua_toboolean(L, idx);
            obj = lean_alloc_ctor(1, 0, 1);
            lean_ctor_set_uint8(obj, 0, b ? 1 : 0);
            return obj;
        }

        case LUA_TNUMBER: {
            if (lua_isinteger(L, idx)) {
                lua_Integer n = lua_tointeger(L, idx);
                obj = lean_alloc_ctor(3, 1, 0);
                lean_ctor_set(obj, 0, lean_int64_to_int(n));
                return obj;
            } else {
                lua_Number f = lua_tonumber(L, idx);
                obj = lean_alloc_ctor(2, 0, sizeof(double));
                lean_ctor_set_float(obj, 0, f);
                return obj;
            }
        }

        case LUA_TSTRING: {
            size_t len;
            const char* s = lua_tolstring(L, idx, &len);
            obj = lean_alloc_ctor(4, 1, 0);
            lean_ctor_set(obj, 0, lean_mk_string_from_bytes(s, len));
            return obj;
        }

        case LUA_TTABLE:
        case LUA_TFUNCTION:
        case LUA_TUSERDATA:
        case LUA_TTHREAD: {
            /* Create a reference in the registry */
            lua_pushvalue(L, idx);
            int ref = luaL_ref(L, LUA_REGISTRYINDEX);

            LuaRefWrapper* wrapper = (LuaRefWrapper*)malloc(sizeof(LuaRefWrapper));
            wrapper->L = L;
            wrapper->ref = ref;

            lean_object* ref_obj = lean_alloc_external(g_lua_ref_class, wrapper);

            int tag;
            if (type == LUA_TTABLE) tag = 5;
            else if (type == LUA_TFUNCTION) tag = 6;
            else if (type == LUA_TUSERDATA) tag = 7;
            else tag = 8;  /* LUA_TTHREAD */

            obj = lean_alloc_ctor(tag, 1, 0);
            lean_ctor_set(obj, 0, ref_obj);
            return obj;
        }

        default:
            return lean_alloc_ctor(0, 0, 0);  /* nil for unknown */
    }
}

/* Push Lean Value onto Lua stack */
static void lean_value_to_lua(lua_State* L, lean_object* val) {
    unsigned tag = lean_obj_tag(val);

    switch (tag) {
        case 0:  /* nil */
            lua_pushnil(L);
            break;

        case 1: {  /* bool */
            uint8_t b = lean_ctor_get_uint8(val, 0);
            lua_pushboolean(L, b);
            break;
        }

        case 2: {  /* number */
            double f = lean_ctor_get_float(val, 0);
            lua_pushnumber(L, f);
            break;
        }

        case 3: {  /* integer */
            lean_object* n = lean_ctor_get(val, 0);
            lua_pushinteger(L, lean_int64_of_int(n));
            break;
        }

        case 4: {  /* string */
            lean_object* s = lean_ctor_get(val, 0);
            const char* str = lean_string_cstr(s);
            size_t len = lean_string_size(s) - 1;
            lua_pushlstring(L, str, len);
            break;
        }

        case 5:  /* table */
        case 6:  /* function */
        case 7:  /* userdata */
        case 8: {  /* thread */
            lean_object* ref_obj = lean_ctor_get(val, 0);
            LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(ref_obj);
            lua_rawgeti(L, LUA_REGISTRYINDEX, wrapper->ref);
            break;
        }

        default:
            lua_pushnil(L);
            break;
    }
}

/* ========================================================================== */
/* State Operations                                                            */
/* ========================================================================== */

LEAN_EXPORT lean_obj_res selene_state_new(lean_obj_arg world) {
    init_external_classes();

    lua_State* L = luaL_newstate();
    if (!L) {
        return mk_io_error("Failed to create Lua state");
    }

    lean_object* obj = lean_alloc_external(g_lua_state_class, L);
    return lean_io_result_mk_ok(obj);
}

LEAN_EXPORT lean_obj_res selene_state_new_with_libs(lean_obj_arg world) {
    init_external_classes();

    lua_State* L = luaL_newstate();
    if (!L) {
        return mk_io_error("Failed to create Lua state");
    }

    luaL_openlibs(L);

    lean_object* obj = lean_alloc_external(g_lua_state_class, L);
    return lean_io_result_mk_ok(obj);
}

LEAN_EXPORT lean_obj_res selene_state_close(b_lean_obj_arg state_obj, lean_obj_arg world) {
    /* No-op: finalizer handles cleanup */
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_do_string(b_lean_obj_arg state_obj, b_lean_obj_arg code_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    const char* code = lean_string_cstr(code_obj);

    int status = luaL_dostring(L, code);
    if (status != LUA_OK) {
        const char* err = lua_tostring(L, -1);
        lean_object* result = lean_alloc_ctor(1, 1, 0);  /* some */
        lean_ctor_set(result, 0, lean_mk_string(err ? err : "Unknown error"));
        lua_pop(L, 1);
        return lean_io_result_mk_ok(result);
    }

    return lean_io_result_mk_ok(lean_box(0));  /* none */
}

LEAN_EXPORT lean_obj_res selene_do_file(b_lean_obj_arg state_obj, b_lean_obj_arg path_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    const char* path = lean_string_cstr(path_obj);

    int status = luaL_dofile(L, path);
    if (status != LUA_OK) {
        const char* err = lua_tostring(L, -1);
        lean_object* result = lean_alloc_ctor(1, 1, 0);  /* some */
        lean_ctor_set(result, 0, lean_mk_string(err ? err : "Unknown error"));
        lua_pop(L, 1);
        return lean_io_result_mk_ok(result);
    }

    return lean_io_result_mk_ok(lean_box(0));  /* none */
}

LEAN_EXPORT lean_obj_res selene_pcall(b_lean_obj_arg state_obj, uint32_t nargs, uint32_t nresults, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int actual_nresults = (nresults == 0xFFFFFFFF) ? LUA_MULTRET : (int)nresults;
    int status = lua_pcall(L, (int)nargs, actual_nresults, 0);
    return lean_io_result_mk_ok(lean_int_to_int(status));
}

LEAN_EXPORT lean_obj_res selene_version(b_lean_obj_arg state_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_Number ver = lua_version(L);
    return lean_io_result_mk_ok(lean_box_float(ver));
}

/* ========================================================================== */
/* Stack Operations                                                            */
/* ========================================================================== */

LEAN_EXPORT lean_obj_res selene_push_nil(b_lean_obj_arg state_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_pushnil(L);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_push_boolean(b_lean_obj_arg state_obj, uint8_t val, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_pushboolean(L, val);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_push_number(b_lean_obj_arg state_obj, double val, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_pushnumber(L, val);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_push_integer(b_lean_obj_arg state_obj, b_lean_obj_arg val_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_Integer val = lean_int64_of_int(val_obj);
    lua_pushinteger(L, val);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_push_string(b_lean_obj_arg state_obj, b_lean_obj_arg str_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    const char* str = lean_string_cstr(str_obj);
    size_t len = lean_string_size(str_obj) - 1;
    lua_pushlstring(L, str, len);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_to_boolean(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_toboolean(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_to_number(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    lua_Number result = lua_tonumber(L, idx);
    return lean_io_result_mk_ok(lean_box_float(result));
}

LEAN_EXPORT lean_obj_res selene_to_integer(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    lua_Integer result = lua_tointeger(L, idx);
    return lean_io_result_mk_ok(lean_int64_to_int(result));
}

LEAN_EXPORT lean_obj_res selene_to_string(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    size_t len;
    const char* str = lua_tolstring(L, idx, &len);
    if (str == NULL) {
        return lean_io_result_mk_ok(lean_mk_string(""));
    }
    return lean_io_result_mk_ok(lean_mk_string_from_bytes(str, len));
}

LEAN_EXPORT lean_obj_res selene_type(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int t = lua_type(L, idx);
    return lean_io_result_mk_ok(lean_int_to_int(t));
}

LEAN_EXPORT lean_obj_res selene_typename(b_lean_obj_arg state_obj, b_lean_obj_arg tp_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int tp = (int)lean_int64_of_int(tp_obj);
    const char* name = lua_typename(L, tp);
    return lean_io_result_mk_ok(lean_mk_string(name ? name : ""));
}

LEAN_EXPORT lean_obj_res selene_pop(b_lean_obj_arg state_obj, uint32_t n, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_pop(L, (int)n);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_get_top(b_lean_obj_arg state_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int top = lua_gettop(L);
    return lean_io_result_mk_ok(lean_int_to_int(top));
}

LEAN_EXPORT lean_obj_res selene_set_top(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    lua_settop(L, idx);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_push_value(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    lua_pushvalue(L, idx);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_check_stack(b_lean_obj_arg state_obj, uint32_t n, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int ok = lua_checkstack(L, (int)n);
    return lean_io_result_mk_ok(lean_box(ok ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_is_nil(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_isnil(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_is_boolean(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_isboolean(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_is_number(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_isnumber(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_is_integer(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_isinteger(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_is_string(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_isstring(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_is_table(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_istable(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_is_function(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_isfunction(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

/* ========================================================================== */
/* Table Operations                                                            */
/* ========================================================================== */

LEAN_EXPORT lean_obj_res selene_new_table(b_lean_obj_arg state_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_newtable(L);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_create_table(b_lean_obj_arg state_obj, uint32_t narr, uint32_t nrec, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_createtable(L, (int)narr, (int)nrec);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_get_table(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int t = lua_gettable(L, idx);
    return lean_io_result_mk_ok(lean_int_to_int(t));
}

LEAN_EXPORT lean_obj_res selene_set_table(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    lua_settable(L, idx);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_get_field(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, b_lean_obj_arg name_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    const char* name = lean_string_cstr(name_obj);
    int t = lua_getfield(L, idx, name);
    return lean_io_result_mk_ok(lean_int_to_int(t));
}

LEAN_EXPORT lean_obj_res selene_set_field(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, b_lean_obj_arg name_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    const char* name = lean_string_cstr(name_obj);
    lua_setfield(L, idx, name);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_get_global(b_lean_obj_arg state_obj, b_lean_obj_arg name_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    const char* name = lean_string_cstr(name_obj);
    int t = lua_getglobal(L, name);
    return lean_io_result_mk_ok(lean_int_to_int(t));
}

LEAN_EXPORT lean_obj_res selene_set_global(b_lean_obj_arg state_obj, b_lean_obj_arg name_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    const char* name = lean_string_cstr(name_obj);
    lua_setglobal(L, name);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_get_metatable(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_getmetatable(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_set_metatable(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_setmetatable(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_raw_len(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    lua_Unsigned len = lua_rawlen(L, idx);
    return lean_io_result_mk_ok(lean_box_uint64(len));
}

LEAN_EXPORT lean_obj_res selene_raw_geti(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, b_lean_obj_arg i_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    lua_Integer i = lean_int64_of_int(i_obj);
    int t = lua_rawgeti(L, idx, i);
    return lean_io_result_mk_ok(lean_int_to_int(t));
}

LEAN_EXPORT lean_obj_res selene_raw_seti(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, b_lean_obj_arg i_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    lua_Integer i = lean_int64_of_int(i_obj);
    lua_rawseti(L, idx, i);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_next(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_next(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

/* ========================================================================== */
/* Function Operations                                                         */
/* ========================================================================== */

LEAN_EXPORT lean_obj_res selene_call(b_lean_obj_arg state_obj, uint32_t nargs, uint32_t nresults, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int actual_nresults = (nresults == 0xFFFFFFFF) ? LUA_MULTRET : (int)nresults;
    lua_call(L, (int)nargs, actual_nresults);
    return lean_io_result_mk_ok(lean_box(0));
}

/* Lean callback context stored as upvalue */
typedef struct {
    lean_object* callback;  /* Array Value -> IO (Array Value) */
} LeanCallbackContext;

/* Lean userdata payload */
typedef struct {
    lean_object* finalizer;  /* IO Unit */
} LeanUserdata;

static int selene_userdata_gc(lua_State* L) {
    LeanUserdata* ud = (LeanUserdata*)lua_touserdata(L, 1);
    if (!ud || !ud->finalizer) {
        return 0;
    }

    lean_object* finalizer = ud->finalizer;
    ud->finalizer = NULL;

    lean_object* io_result = lean_apply_1(finalizer, lean_io_mk_world());
    if (lean_io_result_is_ok(io_result)) {
        /* ignore result */
    }
    lean_dec(io_result);
    lean_dec(finalizer);
    return 0;
}

/* Trampoline function that calls back into Lean */
static int lean_callback_trampoline(lua_State* L) {
    init_external_classes();

    /* Get callback from upvalue */
    LeanCallbackContext* ctx = (LeanCallbackContext*)lua_touserdata(L, lua_upvalueindex(1));
    if (!ctx || !ctx->callback) {
        lua_pushstring(L, "Invalid callback context");
        lua_error(L);
        return 0;
    }

    /* Build Array of Values from arguments */
    int nargs = lua_gettop(L);
    lean_object* args = lean_mk_empty_array();
    for (int i = 1; i <= nargs; i++) {
        lean_object* val = lua_to_lean_value(L, i);
        args = lean_array_push(args, val);
    }

    /* Call Lean function: callback : Array Value -> IO (Array Value) */
    lean_inc(ctx->callback);
    lean_object* io_action = lean_apply_1(ctx->callback, args);
    lean_object* io_result = lean_apply_1(io_action, lean_io_mk_world());

    /* Check for errors */
    if (!lean_io_result_is_ok(io_result)) {
        lean_object* err = lean_io_result_get_error(io_result);
        const char* msg = "Lean callback error";
        if (lean_is_ctor(err) && lean_obj_tag(err) == 0) {
            lean_object* str = lean_ctor_get(err, 0);
            if (lean_is_string(str)) {
                msg = lean_string_cstr(str);
            }
        }
        lean_dec(io_result);
        lua_pushstring(L, msg);
        lua_error(L);
        return 0;
    }

    /* Push results onto Lua stack */
    lean_object* results = lean_io_result_get_value(io_result);
    size_t nresults = lean_array_size(results);
    for (size_t i = 0; i < nresults; i++) {
        lean_object* val = lean_array_get_core(results, i);
        lean_value_to_lua(L, val);
    }
    lean_dec(io_result);

    return (int)nresults;
}

/* Garbage collection callback for Lean callback context */
static int lean_callback_gc(lua_State* L) {
    LeanCallbackContext* ctx = (LeanCallbackContext*)lua_touserdata(L, 1);
    if (ctx && ctx->callback) {
        lean_dec(ctx->callback);
        ctx->callback = NULL;
    }
    return 0;
}

static int lean_yielding_callback_call(lua_State* L, LeanCallbackContext* ctx);

static int lean_yielding_callback_continue(lua_State* L, int status, lua_KContext ctx) {
    (void)status;
    return lean_yielding_callback_call(L, (LeanCallbackContext*)ctx);
}

static int lean_yielding_callback_trampoline(lua_State* L) {
    LeanCallbackContext* ctx = (LeanCallbackContext*)lua_touserdata(L, lua_upvalueindex(1));
    return lean_yielding_callback_call(L, ctx);
}

static int lean_yielding_callback_call(lua_State* L, LeanCallbackContext* ctx) {
    if (!ctx || !ctx->callback) {
        lua_pushstring(L, "Invalid callback context");
        lua_error(L);
        return 0;
    }

    /* Build Array of Values from arguments */
    int nargs = lua_gettop(L);
    lean_object* args = lean_mk_empty_array();
    for (int i = 1; i <= nargs; i++) {
        lean_object* val = lua_to_lean_value(L, i);
        args = lean_array_push(args, val);
    }

    /* Call Lean function: callback : Array Value -> IO CallbackResult */
    lean_inc(ctx->callback);
    lean_object* io_action = lean_apply_1(ctx->callback, args);
    lean_object* io_result = lean_apply_1(io_action, lean_io_mk_world());

    /* Check for errors */
    if (!lean_io_result_is_ok(io_result)) {
        lean_object* err = lean_io_result_get_error(io_result);
        const char* msg = "Lean callback error";
        if (lean_is_ctor(err) && lean_obj_tag(err) == 0) {
            lean_object* str = lean_ctor_get(err, 0);
            if (lean_is_string(str)) {
                msg = lean_string_cstr(str);
            }
        }
        lean_dec(io_result);
        lua_pushstring(L, msg);
        lua_error(L);
        return 0;
    }

    lean_object* result = lean_io_result_get_value(io_result);
    if (!lean_is_ctor(result)) {
        lean_dec(io_result);
        lua_pushstring(L, "Invalid callback result");
        lua_error(L);
        return 0;
    }

    unsigned tag = lean_obj_tag(result);
    lean_object* values = lean_ctor_get(result, 0);
    size_t nresults = lean_array_size(values);
    for (size_t i = 0; i < nresults; i++) {
        lean_object* val = lean_array_get_core(values, i);
        lean_value_to_lua(L, val);
    }
    lean_dec(io_result);

    if (tag == 0) {
        return (int)nresults;
    }
    if (tag == 1) {
        return lua_yieldk(L, (int)nresults, (lua_KContext)ctx, lean_yielding_callback_continue);
    }

    lua_pushstring(L, "Unknown callback result");
    lua_error(L);
    return 0;
}

LEAN_EXPORT lean_obj_res selene_register_function(
    b_lean_obj_arg state_obj,
    b_lean_obj_arg name_obj,
    lean_obj_arg callback,
    lean_obj_arg world
) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    const char* name = lean_string_cstr(name_obj);

    /* Create userdata for callback context */
    LeanCallbackContext* ctx = (LeanCallbackContext*)lua_newuserdata(L, sizeof(LeanCallbackContext));
    ctx->callback = callback;  /* Takes ownership */

    /* Create metatable with __gc for cleanup */
    if (luaL_newmetatable(L, "LeanCallback")) {
        lua_pushcfunction(L, lean_callback_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);

    /* Create closure with callback context as upvalue */
    lua_pushcclosure(L, lean_callback_trampoline, 1);

    /* Set as global */
    lua_setglobal(L, name);

    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_register_yielding_function(
    b_lean_obj_arg state_obj,
    b_lean_obj_arg name_obj,
    lean_obj_arg callback,
    lean_obj_arg world
) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    const char* name = lean_string_cstr(name_obj);

    /* Create userdata for callback context */
    LeanCallbackContext* ctx = (LeanCallbackContext*)lua_newuserdata(L, sizeof(LeanCallbackContext));
    ctx->callback = callback;  /* Takes ownership */

    /* Create metatable with __gc for cleanup */
    if (luaL_newmetatable(L, "LeanCallback")) {
        lua_pushcfunction(L, lean_callback_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);

    /* Create closure with callback context as upvalue */
    lua_pushcclosure(L, lean_yielding_callback_trampoline, 1);

    /* Set as global */
    lua_setglobal(L, name);

    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_new_userdata(
    b_lean_obj_arg state_obj,
    lean_obj_arg finalizer_obj,
    lean_obj_arg world
) {
    init_external_classes();

    lua_State* L = (lua_State*)lean_get_external_data(state_obj);

    LeanUserdata* ud = (LeanUserdata*)lua_newuserdatauv(L, sizeof(LeanUserdata), 0);
    ud->finalizer = finalizer_obj;  /* Takes ownership */

    if (luaL_newmetatable(L, "SeleneUserdata")) {
        lua_pushcfunction(L, selene_userdata_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);

    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    LuaRefWrapper* wrapper = (LuaRefWrapper*)malloc(sizeof(LuaRefWrapper));
    wrapper->L = L;
    wrapper->ref = ref;

    lean_object* obj = lean_alloc_external(g_lua_ref_class, wrapper);
    return lean_io_result_mk_ok(obj);
}

LEAN_EXPORT lean_obj_res selene_ref(b_lean_obj_arg state_obj, lean_obj_arg world) {
    init_external_classes();

    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    LuaRefWrapper* wrapper = (LuaRefWrapper*)malloc(sizeof(LuaRefWrapper));
    wrapper->L = L;
    wrapper->ref = ref;

    lean_object* obj = lean_alloc_external(g_lua_ref_class, wrapper);
    return lean_io_result_mk_ok(obj);
}

LEAN_EXPORT lean_obj_res selene_unref(b_lean_obj_arg state_obj, b_lean_obj_arg ref_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(ref_obj);

    if (wrapper && wrapper->ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, wrapper->ref);
        wrapper->ref = LUA_NOREF;
    }

    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_push_ref(b_lean_obj_arg state_obj, b_lean_obj_arg ref_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(ref_obj);

    if (wrapper && wrapper->ref != LUA_NOREF) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, wrapper->ref);
    } else {
        lua_pushnil(L);
    }

    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_to_value(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    init_external_classes();

    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);

    lean_object* val = lua_to_lean_value(L, idx);
    return lean_io_result_mk_ok(val);
}

/* Note: This shadows the FFI.Stack.pushValue function but with a different signature for Value */
LEAN_EXPORT lean_obj_res selene_push_from_value(b_lean_obj_arg state_obj, b_lean_obj_arg val_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lean_value_to_lua(L, val_obj);
    return lean_io_result_mk_ok(lean_box(0));
}

/* ========================================================================== */
/* Coroutine Operations                                                        */
/* ========================================================================== */

static lua_State* thread_state_from_ref(LuaRefWrapper* wrapper) {
    if (!wrapper || !wrapper->L || wrapper->ref == LUA_NOREF) {
        return NULL;
    }

    lua_State* L = wrapper->L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, wrapper->ref);
    if (!lua_isthread(L, -1)) {
        lua_pop(L, 1);
        return NULL;
    }

    lua_State* co = lua_tothread(L, -1);
    lua_pop(L, 1);
    return co;
}

enum {
    CO_STATUS_RUNNING = 0,
    CO_STATUS_DEAD = 1,
    CO_STATUS_SUSPENDED = 2,
    CO_STATUS_NORMAL = 3
};

static int coroutine_auxstatus(lua_State* L, lua_State* co) {
    if (L == co) {
        return CO_STATUS_RUNNING;
    }

    switch (lua_status(co)) {
        case LUA_YIELD:
            return CO_STATUS_SUSPENDED;
        case LUA_OK: {
            lua_Debug ar;
            if (lua_getstack(co, 0, &ar)) {
                return CO_STATUS_NORMAL;
            } else if (lua_gettop(co) == 0) {
                return CO_STATUS_DEAD;
            } else {
                return CO_STATUS_SUSPENDED;
            }
        }
        default:
            return CO_STATUS_DEAD;
    }
}

LEAN_EXPORT lean_obj_res selene_new_thread(b_lean_obj_arg state_obj, lean_obj_arg world) {
    init_external_classes();

    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    lua_newthread(L); /* pushes thread */

    /* Create registry ref for the thread (pops it) */
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    LuaRefWrapper* wrapper = (LuaRefWrapper*)malloc(sizeof(LuaRefWrapper));
    wrapper->L = L;
    wrapper->ref = ref;

    lean_object* obj = lean_alloc_external(g_lua_ref_class, wrapper);
    return lean_io_result_mk_ok(obj);
}

LEAN_EXPORT lean_obj_res selene_running_thread(b_lean_obj_arg state_obj, lean_obj_arg world) {
    init_external_classes();

    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int ismain = lua_pushthread(L);

    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    LuaRefWrapper* wrapper = (LuaRefWrapper*)malloc(sizeof(LuaRefWrapper));
    wrapper->L = L;
    wrapper->ref = ref;

    lean_object* thread_obj = lean_alloc_external(g_lua_ref_class, wrapper);
    lean_object* pair = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(pair, 0, thread_obj);
    lean_ctor_set(pair, 1, lean_box(ismain ? 1 : 0));
    return lean_io_result_mk_ok(pair);
}

LEAN_EXPORT lean_obj_res selene_thread_state(b_lean_obj_arg state_obj, b_lean_obj_arg ref_obj, lean_obj_arg world) {
    (void)state_obj;
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(ref_obj);
    lua_State* L = wrapper ? wrapper->L : NULL;
    if (!L) {
        return mk_io_error("Thread reference has no state");
    }

    lua_rawgeti(L, LUA_REGISTRYINDEX, wrapper->ref);
    if (!lua_isthread(L, -1)) {
        lua_pop(L, 1);
        return mk_io_error("Value is not a thread");
    }
    lua_pop(L, 1);

    lean_inc(ref_obj);
    return lean_io_result_mk_ok(ref_obj);
}

LEAN_EXPORT lean_obj_res selene_resume(b_lean_obj_arg co_obj, uint32_t nargs, lean_obj_arg world) {
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!co) {
        return mk_io_error("Value is not a thread");
    }

    int nresults = 0;
    int status = lua_resume(co, wrapper->L, (int)nargs, &nresults);

    /* Return tuple: (status, nresults) */
    lean_object* pair = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(pair, 0, lean_int_to_int(status));
    lean_ctor_set(pair, 1, lean_int_to_int(nresults));
    return lean_io_result_mk_ok(pair);
}

LEAN_EXPORT lean_obj_res selene_coroutine_status(b_lean_obj_arg state_obj, b_lean_obj_arg co_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!L || !co) {
        return mk_io_error("Value is not a thread");
    }
    int status = coroutine_auxstatus(L, co);
    return lean_io_result_mk_ok(lean_int_to_int(status));
}

LEAN_EXPORT lean_obj_res selene_status(b_lean_obj_arg co_obj, lean_obj_arg world) {
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!co) {
        return mk_io_error("Value is not a thread");
    }
    int status = lua_status(co);
    return lean_io_result_mk_ok(lean_int_to_int(status));
}

LEAN_EXPORT lean_obj_res selene_close_thread(b_lean_obj_arg state_obj, b_lean_obj_arg co_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!L || !co) {
        return mk_io_error("Value is not a thread");
    }
    int status = lua_closethread(co, L);
    return lean_io_result_mk_ok(lean_int_to_int(status));
}

LEAN_EXPORT lean_obj_res selene_is_yieldable(b_lean_obj_arg co_obj, lean_obj_arg world) {
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!co) {
        return mk_io_error("Value is not a thread");
    }
    int yieldable = lua_isyieldable(co);
    return lean_io_result_mk_ok(lean_box(yieldable ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_is_thread(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);
    int result = lua_isthread(L, idx);
    return lean_io_result_mk_ok(lean_box(result ? 1 : 0));
}

LEAN_EXPORT lean_obj_res selene_to_thread(b_lean_obj_arg state_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    init_external_classes();

    lua_State* L = (lua_State*)lean_get_external_data(state_obj);
    int idx = (int)lean_int64_of_int(idx_obj);

    if (!lua_isthread(L, idx)) {
        return mk_io_error("Value at index is not a thread");
    }

    lua_pushvalue(L, idx);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    LuaRefWrapper* wrapper = (LuaRefWrapper*)malloc(sizeof(LuaRefWrapper));
    wrapper->L = L;
    wrapper->ref = ref;

    lean_object* obj = lean_alloc_external(g_lua_ref_class, wrapper);
    return lean_io_result_mk_ok(obj);
}

LEAN_EXPORT lean_obj_res selene_xmove(b_lean_obj_arg from_obj, b_lean_obj_arg to_obj, uint32_t n, lean_obj_arg world) {
    LuaRefWrapper* from_wrap = (LuaRefWrapper*)lean_get_external_data(from_obj);
    LuaRefWrapper* to_wrap = (LuaRefWrapper*)lean_get_external_data(to_obj);
    lua_State* from = thread_state_from_ref(from_wrap);
    lua_State* to = thread_state_from_ref(to_wrap);
    if (!from || !to) {
        return mk_io_error("Value is not a thread");
    }
    lua_xmove(from, to, (int)n);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_xmove_to_thread(b_lean_obj_arg from_obj, b_lean_obj_arg to_obj, uint32_t n, lean_obj_arg world) {
    lua_State* from = (lua_State*)lean_get_external_data(from_obj);
    LuaRefWrapper* to_wrap = (LuaRefWrapper*)lean_get_external_data(to_obj);
    lua_State* to = thread_state_from_ref(to_wrap);
    if (!to) {
        return mk_io_error("Value is not a thread");
    }
    lua_xmove(from, to, (int)n);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_xmove_from_thread(b_lean_obj_arg from_obj, b_lean_obj_arg to_obj, uint32_t n, lean_obj_arg world) {
    LuaRefWrapper* from_wrap = (LuaRefWrapper*)lean_get_external_data(from_obj);
    lua_State* from = thread_state_from_ref(from_wrap);
    lua_State* to = (lua_State*)lean_get_external_data(to_obj);
    if (!from) {
        return mk_io_error("Value is not a thread");
    }
    lua_xmove(from, to, (int)n);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_co_get_top(b_lean_obj_arg co_obj, lean_obj_arg world) {
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!co) {
        return mk_io_error("Value is not a thread");
    }
    int top = lua_gettop(co);
    return lean_io_result_mk_ok(lean_int_to_int(top));
}

LEAN_EXPORT lean_obj_res selene_co_to_value(b_lean_obj_arg co_obj, b_lean_obj_arg idx_obj, lean_obj_arg world) {
    init_external_classes();

    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!co) {
        return mk_io_error("Value is not a thread");
    }
    int idx = (int)lean_int64_of_int(idx_obj);

    lean_object* val = lua_to_lean_value(co, idx);
    return lean_io_result_mk_ok(val);
}

LEAN_EXPORT lean_obj_res selene_co_pop(b_lean_obj_arg co_obj, uint32_t n, lean_obj_arg world) {
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!co) {
        return mk_io_error("Value is not a thread");
    }
    lua_pop(co, (int)n);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res selene_co_push_from_value(b_lean_obj_arg co_obj, b_lean_obj_arg val_obj, lean_obj_arg world) {
    LuaRefWrapper* wrapper = (LuaRefWrapper*)lean_get_external_data(co_obj);
    lua_State* co = thread_state_from_ref(wrapper);
    if (!co) {
        return mk_io_error("Value is not a thread");
    }
    lean_value_to_lua(co, val_obj);
    return lean_io_result_mk_ok(lean_box(0));
}
