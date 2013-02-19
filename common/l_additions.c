#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

#include <lua.h>
#include <lauxlib.h>

#include "LM.h"
#include "l_additions.h"
#include "debug.h"

static int io_isatty (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);

  lua_pushboolean (L, isatty(fd));

  return 1;
}

static int io_getfd (lua_State *L)
{
  int fd = luaLM_getfd (L, 1);
  if (fd < 0)
    lua_pushnil (L);
  else
    lua_pushnumber (L, fd);
  return 1;
}

int interrupt_pipe = -1;

static int os_set_interrupt_pipe (lua_State *L)
{
  interrupt_pipe = luaLM_checkfd (L, 1);
  luaLM_register_strong_proxy(L, &interrupt_pipe, 1);
  return 0;
}

char *realpath (const char *path, char *rpath);
static int os_realpath (lua_State *L)
{
  const char *path = luaL_checkstring (L, 1);
  char rpath[PATH_MAX];
  if(!realpath(path, rpath)) {
    const char *msg = strerror (errno);
    lua_pushnil (L);
    lua_pushstring (L, msg);
    return 2;
  }
  lua_pushstring (L, rpath);
  return 1;
}

int luaopen_additions(lua_State *L)
{
  const struct luaL_reg io_additions[] = {
    { "isatty",    io_isatty   },
    { "getfd",     io_getfd    },
    { 0,           0           },
  };
  luaL_register (L, "io", io_additions);

  const struct luaL_reg os_additions[] = {
    { "realpath",            os_realpath           },
    { "set_interrupt_pipe",  os_set_interrupt_pipe },
    { 0,                     0                     },
  };
  luaL_register (L, "os", os_additions);

  return 0;
}
