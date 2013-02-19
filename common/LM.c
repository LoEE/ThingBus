///
/// This file contains various helpers for writing Lua programs.
///
/// Most of this file is not specific to USB/Mac OS X/IOKit.
///
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "debug.h"
#include "LM.h"

/// *The Mac OS X specific part*
#ifdef __MACH__
#include <mach/mach.h>
/// Converts mach syscall errors to lua errors (for OS X).
/// Call it if kr!=0 (because KERN_SUCCESS == 0 and kIOReturnSuccess == KERN_SUCCESS)
int luaLM_mach_error (lua_State *L, kern_return_t kr, const char *msg)
{
  return luaL_error (L, "%s: %s (%p)", msg, mach_error_string(kr), kr);
}
/// *End of the Mac OS X specific part*
#endif

#include <errno.h>
int luaLM_posix_error (lua_State *L, const char *msg)
{
  int err = errno;
  char *s = strerror (err);
  lua_pushnil (L);
  if (msg)
    lua_pushfstring (L, "%s: %s", msg, s);
  else
    lua_pushstring (L, s);
  lua_pushnumber (L, err);
  return 3;
}

/// A getfield for numbers. Returns 'd' when the field is nil.
lua_Number luaLM_getnumfield (lua_State *L, int index, char *k, lua_Number d)
{
  lua_getfield (L, index, k);
  if (lua_isnumber (L, -1))
    d = lua_tonumber (L, -1);
  lua_pop (L, 1);
  return d;
}

/// Creates a new metatable, registers it under 'name' and fill is with 'methods'.
void luaLM_register_metatable (lua_State *L, const char *name, const struct luaL_reg *methods)
{
  luaL_newmetatable (L, name);
  lua_pushvalue (L, -1);
  lua_setfield (L, -2, "__index");
  luaL_register (L, NULL, methods);
  lua_pop (L, 1);
}

/// Loads a C-based Lua library. 'fun' should be a pointer to a luaopen_* function.
void luaLM_loadlib (lua_State *L, lua_CFunction fun)
{
  if (lua_cpcall (L, fun, NULL)) {
    eprintf ("failed to load library: %s", lua_tostring (L, -1));
    exit (1);
  }
}

void luaLM_preload (lua_State *L, const struct luaL_reg *mods)
{
  lua_getglobal (L, "package");
  lua_getfield (L, -1, "preload");
  while (mods->name) {
    lua_pushcfunction (L, mods->func);
    lua_setfield (L, -2, mods->name);
    mods++;
  }
  lua_pop (L, 2);
}

/// Dumps the current Lua stack to stderr. Rather simple-minded.
void luaLM_dump_stack (lua_State *L)
{
  int i;
  int top = lua_gettop(L);
  for (i = 1; i <= top; i++) {
    int t = lua_type(L, i);
    switch (t) {
      case LUA_TSTRING:
        eprintf("`%s'", lua_tostring(L, i));
        break;
      case LUA_TBOOLEAN:
        eprintf(lua_toboolean(L, i) ? "true" : "false");
        break;
      case LUA_TNUMBER:
        eprintf("%g", lua_tonumber(L, i));
        break;
      default:
        eprintf("%s", lua_typename(L, t));
        break;
    }
    eprintf("  ");
  }
  eprintf("\n");
}

/// If the object on top of the stack is a number converts it to an int,
/// calls the `getfd` method on this object othwerwise. This method should
/// return a socket handle (an integer).
int luaLM_getfd (lua_State *L, int i)
{
  i = abs_index (L, i);
  { // simple file descriptor (int)
    if (lua_isnumber (L, i)) return lua_tonumber (L, i);
  }
  {
    if (lua_isnil (L, i)) return -1;
  }
  { // a Lua object (userdata or table) with a getfd method (like sockets)
    int fd = -1;
    lua_getfield (L, i, "getfd");
    if (!lua_isnil(L, -1)) {
      lua_pushvalue(L, i);
      lua_call(L, 1, 1);
      if (lua_isnumber(L, -1))
        fd = lua_tonumber(L, -1);
      lua_pop(L, 1);
      return fd;
    }
    lua_pop(L, 1);
  }
  { // Lua file object (userdata)
    FILE *f = *(FILE**)luaL_checkudata(L, 1, LUA_FILEHANDLE);
    return fileno(f);
  }
  return -1;
}

int luaLM_checkfd (lua_State *L, int i)
{
  int fd = luaLM_getfd (L, i);
  if (fd < 0) return luaL_typerror (L, i, "a file object or a file descriptor");
  return fd;
}

/// ## A pointers ↦ userdata objects mapping
///
/// Lua has  not built-in method  for converting userdata  pointers (proxies) back  into userdata
/// objects.  This is  especially  useful when  wrapping  APIs  callbacks. Most  of  them pass  a
/// programmer supplied pointer argument to the callback  procedure. Making this a pointer to the
/// innards of the userdata object allows one to  push the corresponding full object onto the Lua
/// stack from inside the callback function.
///
/// The functions below use a global weak table  in the Lua registry for mapping between userdata
/// pointers  and the  full userdata  objects. This  is a  unique pointer  value which  is (as  a
/// lightuserdata object) is used to store the proxy table is in the global Lua registry.
static char *luaLM_main_thread = "<luaLM.main_thread>";
static char *luaLM_proxy_table = "<luaLM.proxy_table>";
static char *luaLM_strong_proxy_table = "<luaLM.strong_proxy_table>";

/// Creates a  global proxy table and  saves it in the  registry. **This function must  be called
/// once before other functions can be used.**
void luaLM_create_proxy_table (lua_State *L)
{
  lua_pushlightuserdata (L, &luaLM_main_thread);
  if (lua_pushthread (L) != 1) luaL_error (L, "luaLM has to be initialized in the main Lua thread");
  lua_rawset (L, LUA_REGISTRYINDEX);

  lua_pushlightuserdata (L, &luaLM_proxy_table);
  lua_newtable (L);

  lua_createtable (L, 0, 1);
  lua_pushstring (L, "v");
  lua_setfield (L, -2, "__mode");
  lua_setmetatable (L, -2);

  lua_rawset (L, LUA_REGISTRYINDEX);

  lua_pushlightuserdata (L, &luaLM_strong_proxy_table);
  lua_newtable (L);
  lua_rawset (L, LUA_REGISTRYINDEX);
}

int luaLM_push_main_thread (lua_State *L)
{
  lua_pushlightuserdata (L, &luaLM_main_thread);
  lua_rawget (L, LUA_REGISTRYINDEX);

  if (lua_type (L, -1) != LUA_TTHREAD)
    return luaL_error (L, "main thread not found; maybe luaLM was not initialized?");

  return 1;
}

lua_State *luaLM_get_main_state (lua_State *L)
{
  luaLM_push_main_thread (L);
  lua_State *mainL = lua_tothread (L, -1);
  lua_pop (L, 1);
  return mainL;
}

static void _register_proxy (lua_State *L, void *key, void *o, int i);

/// Weakly registers the Lua object at index `i` on the stack as a proxy for the `o` C pointer.
/// The registration **will not** prevent the Lua object from being dealocated.
void luaLM_register_proxy (lua_State *L, void *o, int i)
{
  return _register_proxy (L, &luaLM_proxy_table, o, i);
}

/// Registers the Lua object at index `i` on the stack as a proxy for the `o` C pointer.
/// The registration **will** prevent the Lua object from being dealocated.
void luaLM_register_strong_proxy (lua_State *L, void *o, int i)
{
  return _register_proxy (L, &luaLM_strong_proxy_table, o, i);
}

static void _register_proxy (lua_State *L, void *key, void *o, int i)
{
  i = abs_index (L, i);

  lua_pushlightuserdata (L, key);
  lua_rawget (L, LUA_REGISTRYINDEX);

  lua_pushlightuserdata (L, o);
  lua_pushvalue (L, i);
  lua_rawset (L, -3);
  lua_pop (L, 1);
}

/// Unregisters the strong proxy for pointer `o`.
void luaLM_unregister_strong_proxy (lua_State *L, void *o)
{
  lua_pushnil (L);
  luaLM_register_strong_proxy (L, o, -1);
  lua_pop (L, 1);
}

static int _push_proxy (lua_State *L, void *key, void *o);

/// Pushes the Lua object corresponding to the `o` pointer. Returns 0 (without pushing anything)
/// if the pointer was not registered or the userdata object got garbage collected in the mean time.
int luaLM_push_proxy (lua_State *L, void *o)
{
  return _push_proxy (L, &luaLM_proxy_table, o);
}

/// Pushes the Lua object corresponding to the `o` pointer. Returns 0 (without pushing anything)
/// if the pointer was not registered.
int luaLM_push_strong_proxy (lua_State *L, void *o)
{
  return _push_proxy (L, &luaLM_strong_proxy_table, o);
}

static int _push_proxy (lua_State *L, void *key, void *o)
{
  lua_pushlightuserdata (L, key);
  lua_rawget (L, LUA_REGISTRYINDEX);

  int reg_i = lua_gettop (L);

  lua_pushlightuserdata (L, o);
  lua_rawget (L, reg_i);

  lua_remove (L, reg_i);
  if (lua_type (L, -1) == LUA_TNIL) {
    lua_pop (L, 1);
    return 0;
  } else {
    return 1;
  }
}

/// Creates a new userdata object of size `n` and asigns it the `mt` metatable. It also
/// stores the returned pointer in a proxy table (see `luaLM_register_proxy`). `mt` should be
/// the same pointer that was passed to `luaLM_register_metatable`.
void *luaLM_create_userdata (lua_State *L, size_t n, const char *mt)
{
  void *x = lua_newuserdata (L, n);
  memset (x, 0, n);
  if (mt) {
    luaL_getmetatable (L, mt);
    lua_setmetatable (L, -2);
  }
  luaLM_register_proxy (L, x, -1);
  return x;
}
