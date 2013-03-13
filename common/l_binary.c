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

#include "byte.h"
#include "l_binary.h"
#include "modp_b16.h"
#include "modp_b64.h"

static size_t scan_uint (const char *s, unsigned *u)
{
  const char *start = s;
  unsigned r = 0;
  while (*s >= '0' && *s <= '9') {
    r = r * 10 + (*s - '0'); s++;
  }
  *u = r;
  return s - start;
}

static int is_little_endian (void)
{
  union { int i; char c[sizeof(int)]; } u;
  u.i = 1;
  return u.c[0] == 1;
}

static lua_Number extract_number (const uint8_t *s, size_t n, int le, int issigned)
{
  uint32_t r = 0;
  if (le)
    for (size_t i = 0; i < n; i++) r += (uint32_t)*s++ << (i * 8);
  else
    for (size_t i = 0; i < n; i++) r = (r << 8) + *s++;
  if (!issigned) return r;
  uint32_t mask = ~(0UL) << (n * 8 - 1);
  if (r & mask) r |= mask; // sign extend
  return (int32_t)r;
}

static lua_Number extract_number_64 (const uint8_t *s, size_t n, int le, int issigned)
{
  uint64_t r = 0;
  if (le)
    for (size_t i = 0; i < n; i++) r += (uint64_t)*s++ << (i * 8);
  else
    for (size_t i = 0; i < n; i++) r = (r << 8) + *s++;
  if (!issigned) return r;
  uint64_t mask = ~(0UL) << (n * 8 - 1);
  if (r & mask) r |= mask; // sign extend
  return (int64_t)r;
}

size_t lua_binary_unpack_ll (lua_State *L, const uint8_t *s, size_t n, const char *f, int *results)
{
  int le = is_little_endian();
  size_t startn = n;
  int starti = lua_gettop(L);
  while (1) {
    const char *c = f++;
    if (!*c) {
      *results = lua_gettop(L) - starti;
      return startn - n;
    }
    unsigned size;
    f += scan_uint (f, &size);
    if (f - c <= 1) size = 1;
    if (n < size) goto tooshort;
    switch (*c) {
      case 'u':
      case 's':
        if (size <= 4)
          lua_pushnumber (L, extract_number (s, size, le, *c == 's'));
        else
          lua_pushnumber (L, extract_number_64 (s, size, le, *c == 's'));
        s += size; n -= size;
        break;
      case 'c':
        if(size == 0) {
          if (!lua_isnumber (L, -1)) return luaL_error (L, "a size must come before the c0 format");
          size = lua_tonumber (L, -1);
          lua_pop (L, 1);
        }
        if (n < size) goto tooshort;
        lua_pushlstring (L, (char *)s, size);
        s += size; n -= size;
        break;
      case 'z':
        size = byte_findc (s, n, 0);
        if (n < size) goto tooshort;
        lua_pushlstring (L, (char *)s, size);
        s += size; n -= size;
        break;
      case '<': le = 1; break;
      case '>': le = 0; break;
      case '_': s += size; n -= size; break;
      case ' ':
      case '\r':
      case '\n':
      case '\t':
        break;
    }
    c = f;
  }
tooshort:
  lua_pop(L, lua_gettop(L) - starti);
  *results = -1;
  return startn - n;
}

static int lua_binary_unpack (lua_State *L)
{
  size_t off = 0, size;
  const char *s = luaL_checklstring (L, 1, &size);
  const char *fmt = luaL_checkstring (L, 2);
  if (lua_isnumber (L, 4)) {
    size_t end = lua_tonumber (L, 4);
    if (end < size) size = end;
  }
  if (lua_isnumber (L, 3)) {
    off = lua_tonumber (L, 3) - 1;
    if (off > size) off = size;
  }
  s += off; size -= off;
  int results = 0;
  int results_start = lua_gettop (L);
  size_t n = lua_binary_unpack_ll (L, (const uint8_t *)s, size, fmt, &results);
  lua_pushnumber (L, n); lua_insert (L, results_start + 1);
  return results + 1;
}

static int lua_binary_unpackbits (lua_State *L)
{
  uint32_t num = luaL_checknumber (L, 1);
  size_t n;
  const char *fmt = luaL_checklstring (L, 2, &n);
  if (!lua_istable (L, 3)) {
    lua_newtable (L);
    lua_insert (L, 3);
  }
  lua_pushliteral (L, "_");
  int starti = lua_gettop(L);
  while (1) {
    size_t item_len = byte_findc (fmt, n, ' ');
    size_t name_len = byte_findc (fmt, item_len, ':');
    lua_checkstack (L, 2);
    lua_pushlstring (L, fmt, name_len);
    size_t size;
    if (item_len > name_len + 1) {
      // has an argument
      name_len++; // the colon
      const char *arg = fmt + name_len;
      size_t arg_len = item_len - name_len;
      size = 0;
      while (arg_len-- && *arg >= '0' && *arg <= '9')
        size = size * 10 + (*arg++ - '0');
    } else {
      size = 1;
    }
    lua_pushnumber (L, size);
    if (item_len == n) break;
    item_len++; // space
    fmt += item_len; n -= item_len;
  }
  int parts = (lua_gettop(L) - starti) / 2;
  while (parts--) {
    size_t size = lua_tonumber (L, -1); lua_pop (L, 1);
    if (lua_rawequal (L, -1, starti)) {
      // ignore '_' fields
      lua_pop (L, 1);
    } else {
      if (size > 1) {
        uint32_t mask = ~(0U) >> (32 - size);
        lua_pushnumber (L, num & mask);
      } else {
        lua_pushboolean (L, num & 1);
      }
      lua_settable (L, 3);
    }
    num >>= size;
  }
  lua_pushvalue (L, 3);
  return 1;
}

static int lua_binary_b64_encode (lua_State *L)
{
  size_t ilen = 0;
  const char *is = luaL_checklstring (L, 1, &ilen);
  size_t olen = modp_b64_encode_len(ilen);
  char os[olen];
  olen = modp_b64_encode(os, is, ilen);
  lua_pushlstring(L, os, olen);
  return 1;
}

static int lua_binary_b64_decode (lua_State *L)
{
  size_t ilen = 0;
  const char *is = luaL_checklstring (L, 1, &ilen);
  size_t olen = modp_b64_decode_len(ilen);
  char os[olen];
  olen = modp_b64_decode(os, is, ilen);
  lua_pushlstring(L, os, olen);
  return 1;
}

static int lua_binary_strxor (lua_State *L)
{
  size_t ilen = 0, klen = 0;
  const char *is = luaL_checklstring (L, 1, &ilen);
  const char *ks = luaL_checklstring (L, 2, &klen);
  char os[ilen], *op = os;
  size_t i = 0;
  while (ilen--) {
    *op++ = *is++ ^ ks[i++];
    if (i == klen) i = 0;
  }
  lua_pushlstring (L, os, op - os);
  return 1;
}

static const struct luaL_reg functions[] = {
  {"unpack",     lua_binary_unpack     },
  {"unpackbits", lua_binary_unpackbits },
  {"b64_encode", lua_binary_b64_encode },
  {"b64_decode", lua_binary_b64_decode },
  {"strxor",     lua_binary_strxor     },
  {NULL,         NULL                  },
};

int luaopen_binary (lua_State *L)
{
  lua_newtable (L);
  luaL_register (L, NULL, functions);
  return 1;
}
