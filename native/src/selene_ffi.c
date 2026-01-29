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
