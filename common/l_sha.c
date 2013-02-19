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
#include "sha2/sha1.h"
#include "sha2/sha2.h"

static int lua_sha_sha1 (lua_State *L)
{
  char hash[20];
  size_t ilen = 0;
  const char *is = luaL_checklstring (L, 1, &ilen);
  sha1((uint8_t *)hash, (uint8_t *)is, ilen);
  lua_pushlstring(L, hash, sizeof(hash));
  return 1;
}

static const struct luaL_reg functions[] = {
  {"sha1",  lua_sha_sha1 },
  {NULL,    NULL         },
};

int luaopen_sha (lua_State *L)
{
  lua_newtable (L);
  luaL_register (L, NULL, functions);
  return 1;
}
