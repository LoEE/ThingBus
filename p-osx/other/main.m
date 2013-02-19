///
/// Main program file. It initializes the Lua intepreter, loads all the libraries and calls the scripts
/// passed in the command line arguments.

/// ## Necessary declarations
// stdlib
#include <stdio.h>
#include <string.h>
#include <libgen.h> // dirname

// mach_error
#include <mach/mach.h>

// _NSGetExecutablePath
#include <mach-o/dyld.h>

// CF* stuff
#include <Foundation/Foundation.h>

// Lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "common/LM.h"

// libraries
#include "common/debug.h"
#include "common/l_additions.h"
#include "common/l_preloads.h"
#include "l_usb.h"
#include "l_loop.h"

// for mach_error
static
int vprintf_stderr (const char *fmt, va_list args) {
  return vfprintf (stderr, fmt, args);
}

static const char *argv0 = NULL;
#define EXIT_ON_LUA_ERROR(msg) ({ eprintf ("%s: " msg ": error: %s\n", argv0, lua_tostring (L, -1)); exit (4); })

static int traceback(lua_State *L)
{
    if (!lua_isstring(L, 1)) return 1;
    lua_getfield(L, LUA_GLOBALSINDEX, "debug");
    if (!lua_istable(L, -1)) { lua_pop(L, 1); return 1; }

    lua_getfield(L, -1, "traceback");
    if (!lua_isfunction(L, -1)) { lua_pop(L, 2); return 1; }

    lua_pushvalue(L, 1);    /* pass error message */
    lua_pushinteger(L, 2);  /* skip this function in traceback */
    lua_call(L, 2, 1);      /* call debug.traceback */
    return 1;
}

static char *get_executable_path (void)
{
  char _dummy;
  uint32_t path_len = 0;
  _NSGetExecutablePath (&_dummy, &path_len);
  char *exepath = malloc (path_len);
  if (_NSGetExecutablePath (exepath, &path_len)) {
    eprintf ("cannot get executable path\n");
    exit (1);
  }
  char *rexepath = realpath (exepath, NULL);
  if (!rexepath) EXIT_ON_POSIX_ERROR("cannot resolve executable path", 1);
  char *exedir = dirname (rexepath);
  if (!exedir) EXIT_ON_POSIX_ERROR("cannot extract executable directory name", 1);
  free (rexepath);
  return strdup (exedir);
}

static void lbreak (lua_State *L, lua_Debug *ar);
static void sigint (int i);

static void lbreak (lua_State *L, lua_Debug *ar)
{
  ar = ar;
  lua_sethook (L, NULL, 0, 0);
  signal(SIGINT, sigint);
  luaL_error (L, "interrupt");
}

static lua_State *globalL;

static void sigint (int i)
{
  signal (i, SIG_DFL);
  lua_sethook (globalL, lbreak, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}

int main (int argc, char **argv)
{
  // for mach_error
  vprintf_stderr_func = vprintf_stderr;

  argv0 = argv[0];
  
  //NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  lua_State *L = luaL_newstate();
  globalL = L;
  signal(SIGINT, sigint);
  luaL_openlibs(L);

  const char *add_path = \
"local args = {...}\n"
"for i,p in ipairs(args) do\n"
"  package.path = p .. '/?.lua;' .. p .. '/?/init.lua;' .. p .. '/vendlib/?.lua;' -- .. package.path\n"
"  package.cpath = p .. '/?.so;' .. p .. '/vendlib/?.so;' -- .. package.cpath\n"
"end\n";
  if (luaL_loadstring (L, add_path)) EXIT_ON_LUA_ERROR("path setup code");
  char *exedir = get_executable_path ();
  lua_pushstring (L, exedir);
  free(exedir);
  if (lua_pcall (L, 1, 0, 0)) EXIT_ON_LUA_ERROR("path setup code");  

  luaLM_create_proxy_table (L);

  const struct luaL_reg osx_preloads[] = {
    { "_loop",          luaopen_loop        },
    { "_usb",           luaopen_usb         },
    { 0,                0                   },
  };
  luaLM_preload (L, preloads);
  luaLM_preload (L, osx_preloads);

  luaLM_loadlib (L, luaopen_additions);

  lua_createtable (L, argc, 0);
  for (int i = 0; i < argc; i++) {
    lua_pushstring (L, argv[i]);
    lua_rawseti (L, -2, i);
  }
  lua_setfield (L, LUA_GLOBALSINDEX, "arg");

  lua_getglobal(L, "os");
  lua_pushliteral(L, "osx");
  lua_setfield(L, -2, "platform");
  lua_pop(L, 1);

  //[pool release]; // the NSRunLoop provides it's own pool

  lua_pushcfunction(L, traceback);
  lua_getfield (L, LUA_GLOBALSINDEX, "require");
  char *exename = basename(argv[0]);
  lua_pushstring (L, exename);
  if (lua_pcall (L, 1, 0, -3)) EXIT_ON_LUA_ERROR("bootstrap code");
  
  lua_close(L);
}
