///
/// Simple resizable data buffers for Lua.
///

/// ## Necessary declarations
#include <unistd.h>
#include <stdint.h>

#include <lua.h>
#include <lauxlib.h>

#include "debug.h"
#include "luaP.h"
#include "LM.h"

#include "byte.h"
#include "buffer.h"
#include "l_binary.h"

struct lua_buffer {
  struct buffer b;
};

char *lua_buffer_mt = "<buffer>";

static int lua_buffer_new (lua_State *L)
{
  struct lua_buffer *lb = luaLM_create_userdata (L, sizeof(struct lua_buffer), lua_buffer_mt);
  lb->b = (struct buffer){ .data = 0 };
  return 1;
}

static int lua_buffer_get (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  buflen_t off = 0;
  uint8_t *s;
  buflen_t size = buffer_rpeek (&lb->b, &s);
  if (lua_isnumber (L, 3)) {
    size_t end = lua_tonumber (L, 3);
    if (end < size) size = end;
  }
  if (lua_isnumber (L, 2)) {
    off = lua_tonumber (L, 2) - 1;
    if (off > size) off = size;
  }
  lua_pushlstring (L, (char *)(s + off), size - off);
  return 1;
}

static int lua_buffer_write (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  size_t n;
  const char *x = luaL_checklstring (L, 2, &n);
  if (!buffer_write (&lb->b, x, n)) return luaL_error (L, "cannot allocate memory for the buffer");
  return 0;
}

static int lua_buffer_peek (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  uint8_t *s;
  buflen_t a = buffer_rpeek (&lb->b, &s);
  if (!a) return 0;
  if (!lua_isnoneornil (L, 2)) {
    buflen_t n = luaL_checkinteger (L, 2);
    if (a < n) return 0;
    a = n;
  }
  lua_pushlstring (L, (char *)s, a);
  return 1;
}

static int lua_buffer_read (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  uint8_t *s;
  buflen_t a = buffer_rpeek (&lb->b, &s);
  if (!a) return 0;
  if (!lua_isnoneornil (L, 2)) {
    buflen_t n = luaL_checkinteger (L, 2);
    if (a < n) return 0;
    a = n;
  }
  lua_pushlstring (L, (char *)s, a);
  buffer_rseek (&lb->b, a);
  return 1;
}

static int lua_buffer_readuntil (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  uint8_t *s;
  buflen_t a = buffer_rpeek (&lb->b, &s);
  if (!a) return 0;
  size_t n;
  const char *x = luaL_checklstring (L, 2, &n);
  lua_Integer drop = 0;
  if (lua_isnumber (L, 3)) drop = luaL_checknumber (L, 3);
  size_t i = byte_find (s, a, x, n);
  if (i == a) return 0;
  lua_pushlstring (L, (char *)s, i);
  buffer_rseek (&lb->b, i + drop);
  return 1;
}

static int lua_buffer_peekstruct (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  uint8_t *s;
  buflen_t a = buffer_rpeek (&lb->b, &s);
  const char *fmt = luaL_checkstring (L, 2);
  int results = 0;
  lua_pushnil (L);
  int starti = lua_gettop(L);
  size_t n = lua_binary_unpack_ll (L, s, a, fmt, &results);
  if (results < 0) return 0;
  lua_pushnumber (L, n); lua_replace (L, starti);
  return results + 1;
}

static int lua_buffer_readstruct (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  int results = lua_buffer_peekstruct (L);
  if (results == 0) return 0;
  size_t n = lua_tonumber (L, -results);
  buffer_rseek (&lb->b, n);
  return results - 1;
}

static int lua_buffer_rseek (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  size_t n = luaL_checkinteger (L, 2);
  uint8_t *c;
  size_t a = buffer_rpeek (&lb->b, &c);
  if (n > a) return 0;
  buffer_rseek (&lb->b, n);
  lua_pushnumber (L, n);
  return 1;
}

static int lua_buffer_len (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  uint8_t *c;
  buflen_t a = buffer_rpeek (&lb->b, &c);
  lua_pushnumber (L, a);
  return 1;
}

static int lua_buffer_debug (lua_State *L)
{
  struct lua_buffer *lb = luaL_checkudata (L, 1, lua_buffer_mt);
  lua_pushfstring (L, "data: %p, size: %d, start: %d, end: %d",
      lb->b.data, lb->b.size, lb->b.start, lb->b.end);
  return 1;
}

static const struct luaL_reg functions[] = {
  {"new",  lua_buffer_new },
  {NULL,   NULL           },
};

static const struct luaL_reg buffer_methods[] = {
  {"get",        lua_buffer_get        },
  {"write",      lua_buffer_write      },
  {"peek",       lua_buffer_peek       },
  {"read",       lua_buffer_read       },
  {"readuntil",  lua_buffer_readuntil  },
  {"peekstruct", lua_buffer_peekstruct },
  {"readstruct", lua_buffer_readstruct },
  {"rseek",      lua_buffer_rseek      },
  {"_debug",     lua_buffer_debug      },
  {"__len",      lua_buffer_len        },
  {NULL,         NULL                  },
};

int luaopen_buffer (lua_State *L)
{
  luaLM_register_metatable (L, lua_buffer_mt, buffer_methods);
  luaL_register (L, "buffer", functions);
  return 1;
}
