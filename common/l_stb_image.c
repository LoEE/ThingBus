///
/// Simple binary data utilities for Lua.
///

/// ## Necessary declarations
#include <unistd.h>
#include <stdint.h>

#include <lua.h>
#include <lauxlib.h>

#include "debug.h"
#include "luaP.h"
#include "LM.h"

#include "l_sha.h"
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_LINEAR
#include "stb_image.h"

static int lua_stbi_info (lua_State *L)
{
  const char *fname = luaL_checkstring (L, 1);
  int x, y, comp;
  stbi_info(fname, &x, &y, &comp);
  lua_pushnumber(L, x);
  lua_pushnumber(L, y);
  lua_pushnumber(L, comp);
  return 3;
}

static const struct luaL_reg functions[] = {
  {"info",  lua_stbi_info },
  {NULL,    NULL          },
};

int luaopen_stb_image (lua_State *L)
{
  lua_newtable (L);
  luaL_register (L, NULL, functions);
  return 1;
}
