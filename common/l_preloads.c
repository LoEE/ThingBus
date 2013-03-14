#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>

#include <lua.h>
#include <lauxlib.h>
#include <lua-md5.h>

#include "LM.h"
#include "l_preloads.h"

#include "l_crc.h"
#include "l_xtea.h"
#include "l_binary.h"
#include "l_buffer.h"
#include "l_sha.h"
int luaopen_bit32(lua_State *L);
int luaopen_socket_core(lua_State *L);
int luaopen_lfs(lua_State *L);
int luaopen_yajl(lua_State *L);
int luaopen_ev(lua_State *L);
int luaopen_brimworks_zip(lua_State *L);

const struct luaL_reg preloads[] = {
  { "bit32",          luaopen_bit32         },
  { "socket.core",    luaopen_socket_core   },
  { "lfs",            luaopen_lfs           },
  { "_binary",        luaopen_binary        },
  { "crc",            luaopen_crc           },
  { "xtea",           luaopen_xtea          },
  { "buffer",         luaopen_buffer        },
  { "md5.core",       luaopen_md5_core      },
  { "sha",            luaopen_sha           },
  { "yajl",           luaopen_yajl          },
  { "ev",             luaopen_ev            },
  { "zip",            luaopen_brimworks_zip },
  { 0,                0                     },
};
