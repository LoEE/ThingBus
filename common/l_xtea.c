/// ## Necessary declarations
// lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <stdint.h>

/*
 * taken from: http://en.wikipedia.org/wiki/XTEA
 */

/* take 64 bits of data in v[0] and v[1] and 128 bits of key[0] - key[3] */ 
static void encipher(unsigned int num_rounds, uint32_t v[2], uint32_t const key[4]) {
    unsigned int i;
    uint32_t v0=v[0], v1=v[1], sum=0, delta=0x9E3779B9;
    for (i=0; i < num_rounds; i++) {
        v0 += (((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + key[sum & 3]);
        sum += delta;
        v1 += (((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + key[(sum>>11) & 3]);
    }
    v[0]=v0; v[1]=v1;
}
 
static void decipher(unsigned int num_rounds, uint32_t v[2], uint32_t const key[4]) {
    unsigned int i;
    uint32_t v0=v[0], v1=v[1], delta=0x9E3779B9, sum=delta*num_rounds;
    for (i=0; i < num_rounds; i++) {
        v1 -= (((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + key[(sum>>11) & 3]);
        sum -= delta;
        v0 -= (((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + key[sum & 3]);
    }
    v[0]=v0; v[1]=v1;
}

/*
 * end of: http://en.wikipedia.org/wiki/XTEA
 */

static void byte_copy (void *_d, size_t n, const void *_s)
{
  uint8_t *d = _d;
  const uint8_t *s = _s;
  while (n--) *d++ = *s++;
}

static int l_encipher (lua_State *L)
{
  size_t datan = 0, keyn = 0;
  const char *data = luaL_checklstring (L, 1, &datan);
  const char *key = luaL_checklstring (L, 2, &keyn);
  if (datan % 8 != 0)
    return luaL_error (L, "data length is not a multiple of 8 bytes: %d bytes", datan);
  if (keyn != 16)
    return luaL_error (L, "key length is not 16 bytes: %d bytes", keyn);

  uint32_t buf[datan / 4];
  uint32_t keybuf[keyn / 4];
  byte_copy (buf, datan, data);
  byte_copy (keybuf, keyn, key);
  for (size_t x = 0; x < datan / 4; x += 2) {
    encipher (32, buf + x, keybuf);
  }
  lua_pushlstring (L, (void *)buf, datan);
  return 1;
}

static int l_decipher (lua_State *L)
{
  size_t datan = 0, keyn = 0;
  const char *data = luaL_checklstring (L, 1, &datan);
  const char *key = luaL_checklstring (L, 2, &keyn);
  if (datan % 8 != 0)
    return luaL_error (L, "data length is not a multiple of 8 bytes: %d bytes", datan);
  if (keyn != 16)
    return luaL_error (L, "key length is not 16 bytes: %d bytes", keyn);

  uint32_t buf[datan / 4];
  uint32_t keybuf[keyn / 4];
  byte_copy (buf, datan, data);
  byte_copy (keybuf, keyn, key);
  for (size_t x = 0; x < datan / 4; x += 2) {
    decipher (32, buf + x, keybuf);
  }
  lua_pushlstring (L, (void *)buf, datan);
  return 1;
}

static const struct luaL_reg funcs[] = {
  {"encipher",  l_encipher },
  {"decipher",  l_decipher },
  {NULL,        NULL       },
};

int luaopen_xtea (lua_State *L)
{
  luaL_register (L, "xtea", funcs);
  return 1;
}
