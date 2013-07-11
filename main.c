#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <libgen.h> // dirname

// Lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "common/LM.h"

// libraries
#include "common/debug.h"
#include "common/l_additions.h"
#include "common/l_preloads.h"

static const char *argv0 = NULL;
#define EXIT_ON_LUA_ERROR(msg) ({ eprintf ("%s: " msg ": error: %s\n", argv0, lua_tostring (L, -1)); exit (4); })

static int traceback (lua_State *L)
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

void enable_keyboard_interrupt_handler (void);
void disable_keyboard_interrupt_handler (void);

static lua_State *globalL;

static void lbreak (lua_State *L, lua_Debug *ar)
{
  lua_sethook (L, NULL, 0, 0);
  enable_keyboard_interrupt_handler();
  luaL_error (L, "interrupt");
}

void keyboard_interrupt(void)
{
  lua_sethook (globalL, lbreak, LUA_MASKCOUNT, 1);
  if (interrupt_pipe >= 0)
    if (write(interrupt_pipe, "I", 1) < 1)
      EXIT_ON_POSIX_ERROR("interrupt_pipe write", 5);
  disable_keyboard_interrupt_handler();
}

char *get_executable_path (void);
void init_platform(void);
void lua_init_platform(lua_State *L);

char *current_file;
int current_ln = -1;

#ifndef WIN32
#include <fcntl.h>
#include <errno.h>

static void record_line (lua_State *L, lua_Debug *ar)
{
  lua_gc(L, LUA_GCCOLLECT, 0);
  lua_getinfo(L, "S", ar);
  if (!current_file || strcmp(current_file, ar->short_src)) {
    if (current_ln != -1) free(current_file);
    current_file = strdup(ar->short_src);
  }
  current_ln = ar->currentline;
}

static void *l_dbg_alloc (void *ud, void *ptr, size_t osize, size_t nsize)
{
  void *r;
  if (nsize) {
    r = realloc(ptr, nsize);
  } else {
    free(ptr);
    r = NULL;
  }

  fprintf(ud, "%10p\t%zu\t->\t%10p\t%zu\t@\t%s\t%d\n", ptr, osize, r, nsize, current_file, current_ln);
  return r;
}
#endif

int main (int argc, char **argv)
{
  init_platform();

  argv0 = argv[0];

  lua_State *L;
#ifndef WIN32
  char *memdbg_fname = getenv("THB_MEMDBG_FILE");
  if (memdbg_fname) {
    FILE *memdbg = fopen(memdbg_fname, "w");
    current_file = "newstate";
    L = lua_newstate(l_dbg_alloc, memdbg);
    current_file = "sethook";
    lua_sethook(L, record_line, LUA_MASKLINE, 0);
  } else {
    L = luaL_newstate();
  }
#else
  L = luaL_newstate();
#endif

  current_file = "luaLM_create_proxy_table";
  luaLM_create_proxy_table (L);

  globalL = L;
  //enable_keyboard_interrupt_handler();

  current_file = "openlibs";
  luaL_openlibs(L);

  current_file = "preload";
  luaLM_preload (L, preloads);
  extern const struct luaL_reg platform_preloads[];
  current_file = "platform preload";
  luaLM_preload (L, platform_preloads);

  current_file = "additions";
  luaLM_loadlib (L, luaopen_additions);

  current_file = "checks";
  extern int luaopen_checks(lua_State *L);
  luaLM_loadlib (L, luaopen_checks);

  current_file = "init platform";
  lua_init_platform(L);

  current_file = "args";
  lua_createtable (L, argc, 0);
  for (int i = 0; i < argc; i++) {
    lua_pushstring (L, argv[i]);
    lua_rawseti (L, -2, i);
  }
  lua_setfield (L, LUA_GLOBALSINDEX, "arg");

  current_file = "setup init";
  int l_init(lua_State *L);
  lua_pushcfunction(L, traceback);
  lua_pushcfunction(L, l_init);
  char *exedir = get_executable_path ();
  lua_pushstring(L, exedir);
  lua_pushliteral(L, PLATFORM_STRING);
  free(exedir);
  current_file = "pcall init";
  if (lua_pcall (L, 2, 0, -4)) EXIT_ON_LUA_ERROR("initialization code");

  current_ln = -1; current_file = "close";
  lua_close(L);
}
