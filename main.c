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
#include <ev.h>

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

ev_async keyboard_interrupt_watcher;

static int should_break = 0;

static void lbreak (lua_State *L, lua_Debug *ar)
{
  if (!should_break) return;
  lua_sethook (L, NULL, 0, 0);
  enable_keyboard_interrupt_handler();
  luaL_error (L, "interrupt");
}

void keyboard_interrupt_watcher_cb(struct ev_loop *loop, ev_async *w, int revents) {
  ev_break(EV_DEFAULT, EVBREAK_ALL);
}

void keyboard_interrupt(void)
{
  should_break = 1;
  ev_async_send(EV_DEFAULT, &keyboard_interrupt_watcher);
  disable_keyboard_interrupt_handler();
}

char *get_executable_path (void);
void init_platform(void);
void lua_init_platform(lua_State *L);

int main (int argc, char **argv)
{
  init_platform();

  argv0 = argv[0];

  lua_State *L;
  L = luaL_newstate();

  luaLM_create_proxy_table (L);

  ev_async_init(&keyboard_interrupt_watcher, keyboard_interrupt_watcher_cb);
  ev_async_start(EV_DEFAULT, &keyboard_interrupt_watcher);
  lua_sethook (L, lbreak, LUA_MASKCOUNT, 10000);
  enable_keyboard_interrupt_handler();

  luaL_openlibs(L);

  luaLM_preload (L, preloads);
  extern const struct luaL_reg platform_preloads[];
  luaLM_preload (L, platform_preloads);

  luaLM_loadlib (L, luaopen_additions);

  extern int luaopen_checks(lua_State *L);
  luaLM_loadlib (L, luaopen_checks);

  lua_init_platform(L);

  lua_createtable (L, argc, 0);
  for (int i = 0; i < argc; i++) {
    lua_pushstring (L, argv[i]);
    lua_rawseti (L, -2, i);
  }
  lua_setfield (L, LUA_GLOBALSINDEX, "arg");

  int l_init(lua_State *L);
  lua_pushcfunction(L, traceback);
  lua_pushcfunction(L, l_init);
  char *exedir = get_executable_path ();
  lua_pushstring(L, exedir);
  lua_pushliteral(L, PLATFORM_STRING);
  free(exedir);
  if (lua_pcall (L, 2, 0, -4)) EXIT_ON_LUA_ERROR("initialization code");

  lua_close(L);
}
