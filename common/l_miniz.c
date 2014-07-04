#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "LM.h"

#include <stdint.h>
#include "debug.h"
#include "str.h"

#define MINIZ_NO_ARCHIVE_APIS
#define MINIZ_NO_ZLIB_APIS
#include "miniz.c"

#include "buffer.h"



struct lua_miniz_compressor {
  tdefl_compressor c;
  struct buffer bout;
};

const char *lua_miniz_compressor_mt = "<miniz_compressor>";

mz_bool buf_put(const void *s, int n, void *_b)
{
  struct buffer *b = _b;
  return buffer_write(b, s, n);
}

static int lua_miniz_compressor (lua_State *L)
{
  static const int levels[11] = { 0, 1, 6, 32,  16, 32, 128, 256,  512, 768, 1500 };
  int dictsize = levels[6];
  int flags = dictsize;
  for (int i = 1; !lua_isnoneornil(L, i); i++) {
    int t = lua_type(L, i);
    if (t == LUA_TSTRING) {
      const char *flag = lua_tostring(L, i);
      if (!str_diff(flag, "zlib-header")) flags |= TDEFL_WRITE_ZLIB_HEADER;
          // FIXME: other flags?
      else                                luaL_argerror(L, i, "unknown flag");
    }
    if (t == LUA_TNUMBER) {
      int level = lua_tonumber (L, i);
      if (level > 10) return luaL_argerror(L, i, "invalid compression level [0-10 allowed]");
      dictsize = levels[level];
    }
  }
  struct lua_miniz_compressor *lc = luaLM_create_userdata (L, sizeof(struct lua_miniz_compressor), lua_miniz_compressor_mt);
  lc->bout = (struct buffer){ .data = 0 };
  tdefl_init(&lc->c, buf_put, &lc->bout, flags);
  return 1;
}

static int lua_miniz_compressor_write (lua_State *L)
{
  struct lua_miniz_compressor *lc = luaL_checkudata (L, 1, lua_miniz_compressor_mt);
  size_t n = 0;
  const char *s = luaL_checklstring (L, 2, &n);
  tdefl_status ret = tdefl_compress_buffer (&lc->c, s, n, TDEFL_NO_FLUSH);
  if(ret < 0) return luaL_error(L, "compression error: %d", ret);
  return 0;
}

static int lua_miniz_compressor_flush (lua_State *L)
{
  struct lua_miniz_compressor *lc = luaL_checkudata (L, 1, lua_miniz_compressor_mt);
  int flush = TDEFL_FINISH;
  const char *str = luaL_optstring(L, 2, NULL);
  if(str) {
         if (!str_diff(str, "sync"))   flush = TDEFL_SYNC_FLUSH;
    else if (!str_diff(str, "full"))   flush = TDEFL_FULL_FLUSH;
    else if ( str_diff(str, "finish")) luaL_argerror(L, 2, "invalid flush type");
  }
  tdefl_status ret = tdefl_compress_buffer (&lc->c, NULL, 0, flush);
  if(ret < 0) return luaL_error(L, "compression error: %d", ret);
  return 0;
}

static int lua_miniz_compressor__len (lua_State *L)
{
  struct lua_miniz_compressor *lc = luaL_checkudata (L, 1, lua_miniz_compressor_mt);
  const uint8_t *c;
  buflen_t a = buffer_rpeek (&lc->bout, &c);
  lua_pushnumber (L, a);
  return 1;
}

static int lua_miniz_compressor_read (lua_State *L)
{
  struct lua_miniz_compressor *lc = luaL_checkudata (L, 1, lua_miniz_compressor_mt);
  const uint8_t *s;
  buflen_t a = buffer_rpeek (&lc->bout, &s);
  if (!a) return 0;
  if (!lua_isnoneornil (L, 2)) {
    buflen_t n = luaL_checkinteger (L, 2);
    if (a < n) return 0;
    a = n;
  }
  lua_pushlstring (L, (char *)s, a);
  buffer_rseek (&lc->bout, a);
  return 1;
}

static int lua_miniz_compressor__tostring (lua_State *L)
{
  // struct lua_miniz_compressor *lc = luaL_checkudata (L, 1, lua_miniz_compressor_mt);
  lua_pushstring (L, "<compressor>");
  return 1;
}




struct lua_miniz_decompressor {
  tinfl_decompressor d;
  struct buffer bin;
  struct buffer bout;
  uint8_t dict[TINFL_LZ_DICT_SIZE];
  size_t dictoff;
  int flags;
};

const char *lua_miniz_decompressor_mt = "<miniz_decompressor>";

static int lua_miniz_decompressor (lua_State *L)
{
  struct lua_miniz_decompressor *ld = luaLM_create_userdata (L, sizeof(struct lua_miniz_decompressor), lua_miniz_decompressor_mt);
  ld->bin = (struct buffer){ .data = 0 };
  ld->bout = (struct buffer){ .data = 0 };
  tinfl_init(&ld->d);
  int flags = 0;
  for (int i = 1; !lua_isnoneornil(L, i); i++) {
    if (lua_type(L, i) == LUA_TSTRING) {
      const char *flag = lua_tostring(L, i);
           if (!str_diff(flag, "zlib-header"))  flags |= TINFL_FLAG_PARSE_ZLIB_HEADER;
      else if (!str_diff(flag, "calc-adler32")) flags |= TINFL_FLAG_COMPUTE_ADLER32;
      else                                      luaL_argerror(L, i, "unknown flag");
    }
  }
  return 1;
}

static int lua_miniz_decompressor_write (lua_State *L)
{
  struct lua_miniz_decompressor *ld = luaL_checkudata (L, 1, lua_miniz_decompressor_mt);
  int finalflag = TINFL_FLAG_HAS_MORE_INPUT;
  if(!lua_isnoneornil(L, 3)) {
    const char *flag = luaL_checkstring(L, 3);
    if(!str_diff(flag, "final")) finalflag = 0;
    else luaL_argerror(L, 3, "expected either 'final' or no argument");
  }
  const uint8_t *s;
  buflen_t n;
  s = (const uint8_t *)luaL_checklstring (L, 2, &n);
  if(!buffer_write(&ld->bin, s, n)) return luaL_error (L, "cannot allocate memory for the input buffer");
rerun:
  n = buffer_rpeek (&ld->bin, &s);
  size_t osize = TINFL_LZ_DICT_SIZE - ld->dictoff;
  tinfl_status ret = tinfl_decompress(&ld->d, s, &n, ld->dict, ld->dict + ld->dictoff, &osize, ld->flags | finalflag);
  buffer_rseek(&ld->bin, n);
  if(osize) {
    if(!buffer_write(&ld->bout, ld->dict + ld->dictoff, osize)) return luaL_error (L, "cannot allocate memory for the input buffer");
    ld->dictoff = (ld->dictoff + osize) & (TINFL_LZ_DICT_SIZE - 1);
  }
  if(ret == TINFL_STATUS_HAS_MORE_OUTPUT) goto rerun;
  if(ret >= 0) {
    lua_pushboolean(L, ret == TINFL_STATUS_DONE);
    return 1;
  }
  switch(ret) {
    case TINFL_STATUS_BAD_PARAM:
      return luaL_error(L, "bad param to tinfl_decompress???");
    case TINFL_STATUS_ADLER32_MISMATCH:
      lua_pushboolean(L, 1); lua_pushstring(L, "Adler-32 checksum mismatch");
      return 2;
    case TINFL_STATUS_FAILED:
      lua_pushboolean(L, 1); lua_pushstring(L, "decompression error");
      return 2;
    case TINFL_STATUS_DONE:
    case TINFL_STATUS_NEEDS_MORE_INPUT:
    case TINFL_STATUS_HAS_MORE_OUTPUT:
      ; // handled above
  }
  return 0; // never happens
}

static int lua_miniz_decompressor__len (lua_State *L)
{
  struct lua_miniz_decompressor *ld = luaL_checkudata (L, 1, lua_miniz_decompressor_mt);
  const uint8_t *s;
  buflen_t a = buffer_rpeek (&ld->bout, &s);
  lua_pushnumber (L, a);
  return 1;
}

static int lua_miniz_decompressor_read (lua_State *L)
{
  struct lua_miniz_decompressor *ld = luaL_checkudata (L, 1, lua_miniz_decompressor_mt);
  const uint8_t *s;
  buflen_t a = buffer_rpeek (&ld->bout, &s);
  if (!a) return 0;
  if (!lua_isnoneornil (L, 2)) {
    buflen_t n = luaL_checkinteger (L, 2);
    if (a < n) return 0;
    a = n;
  }
  lua_pushlstring (L, (char *)s, a);
  buffer_rseek (&ld->bout, a);
  return 1;
}

static int lua_miniz_decompressor_adler32 (lua_State *L)
{
  struct lua_miniz_decompressor *ld = luaL_checkudata (L, 1, lua_miniz_decompressor_mt);
  lua_pushnumber (L, tinfl_get_adler32(&ld->d));
  return 1;
}

static int lua_miniz_decompressor__tostring (lua_State *L)
{
  // struct lua_miniz_decompressor *ld = luaL_checkudata (L, 1, lua_miniz_decompressor_mt);
  lua_pushstring (L, "<decompressor>");
  return 1;
}



static const struct luaL_reg funcs[] = {
  {"compressor",   lua_miniz_compressor   },
  {"decompressor", lua_miniz_decompressor },
  {NULL,           NULL                   },
};

static const struct luaL_reg miniz_compressor_methods[] = {
  {"write",      lua_miniz_compressor_write     },
  {"flush",      lua_miniz_compressor_flush     },
  {"__len",      lua_miniz_compressor__len      },
  {"read",       lua_miniz_compressor_read      },
  {"__tostring", lua_miniz_compressor__tostring },
  {NULL,         NULL                           },
};

static const struct luaL_reg miniz_decompressor_methods[] = {
  {"write",      lua_miniz_decompressor_write     },
  {"__len",      lua_miniz_decompressor__len      },
  {"read",       lua_miniz_decompressor_read      },
  {"adler32",    lua_miniz_decompressor_adler32   },
  {"__tostring", lua_miniz_decompressor__tostring },
  {NULL,         NULL                             },
};

int luaopen_miniz (lua_State *L)
{
  luaLM_register_metatable (L, lua_miniz_compressor_mt, miniz_compressor_methods);
  luaLM_register_metatable (L, lua_miniz_decompressor_mt, miniz_decompressor_methods);
  luaL_register (L, "miniz", funcs);
  return 1;
}
