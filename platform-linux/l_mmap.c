#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "../common/LM.h"
#include "../common/debug.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "../common/byte.h"

#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

struct lua_mmap {
  void *mem;
  size_t size;
  void *base;
  size_t basesize;
  intptr_t mapbase;
  size_t mapsize;
};

char *lua_mmap_mt = "<mmap>";

static int lua_mmap_new (lua_State *L)
{
  intptr_t addr = luaL_checknumber (L, 1);
  size_t size = luaL_checknumber (L, 2);
  struct lua_mmap *lmm = luaLM_create_userdata (L, sizeof(struct lua_mmap), lua_mmap_mt);

  int fd = open("/dev/mem", O_RDWR);
  if (fd < 0)
    return luaLM_posix_error (L, __FUNCTION__);

  size_t pagesize = sysconf(_SC_PAGESIZE);
  size_t pagemask = ~(pagesize - 1); // assumes pagesize is always a power of two

  intptr_t mapstart = addr & pagemask;
  intptr_t mapend = (addr + size + pagesize-1) & pagemask;
  size_t mapsize = mapend - mapstart;

  lmm->base = mmap(0, mapsize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mapstart);
  if (lmm->base == MAP_FAILED) {
    close(fd);
    return luaLM_posix_error (L, __FUNCTION__);
  }
  lmm->basesize = mapsize;

  off_t offset = addr - mapstart;
  lmm->mem = lmm->base + offset;
  lmm->size = mapsize - offset;
  lmm->mapbase = mapstart;
  lmm->mapsize = mapsize;

  close(fd);

  return 1;
}

static int lua_mmap_read (lua_State *L)
{
  struct lua_mmap *lmm = luaL_checkudata (L, 1, lua_mmap_mt);
  size_t start = 0;
  if (lua_isnumber (L, 2)) {
    start = lua_tonumber (L, 2);
    if (start > lmm->size) return luaL_error(L, "start address out of range");
  }
  size_t len = lmm->size;
  if (lua_isnumber (L, 3)) {
    len = lua_tonumber (L, 3);
    if (start + len > lmm->size) return luaL_error(L, "end address out of range");
  }
  lua_pushlstring (L, (char *)(lmm->mem + start), len);
  return 1;
}

static int lua_mmap_write (lua_State *L)
{
  struct lua_mmap *lmm = luaL_checkudata (L, 1, lua_mmap_mt);
  size_t start = 0;
  size_t len;
  const char *x = luaL_checklstring (L, 2, &len);
  if (lua_isnumber (L, 3)) {
    start += lua_tonumber (L, 3);
    if (start > lmm->size) return luaL_argerror(L, 2, "address out of range");
  }
  if (start + len > lmm->size) return luaL_argerror(L, 3, "address out of range");
  byte_copy(lmm->mem + start, len, x);
  return 0;
}

static int lua_mmap_get (lua_State *L)
{
  struct lua_mmap *lmm = luaL_checkudata (L, 1, lua_mmap_mt);
  size_t start = lua_tonumber (L, 2);
  if (start > lmm->size) return luaL_argerror(L, 2, "address out of range");
  size_t len = lua_tonumber (L, 3);
  if (start + len > lmm->size) return luaL_argerror(L, 3, "address out of range");
  switch (len) {
    case 1: lua_pushnumber(L, *( uint8_t *)(lmm->mem + start)); break;
    case 2: lua_pushnumber(L, *(uint16_t *)(lmm->mem + start)); break;
    case 4: lua_pushnumber(L, *(uint32_t *)(lmm->mem + start)); break;
    case 8: lua_pushnumber(L, *(uint64_t *)(lmm->mem + start)); break;
    default: return luaL_argerror(L, 3, "unsupported read size");
  }
  return 1;
}

static int lua_mmap_put (lua_State *L)
{
  struct lua_mmap *lmm = luaL_checkudata (L, 1, lua_mmap_mt);
  size_t start = 0;
  if (lua_isnumber (L, 2)) {
    start += lua_tonumber (L, 2);
    if (start > lmm->size) return luaL_argerror(L, 2, "address out of range");
  }
  size_t len = sizeof(size_t);
  if (lua_isnumber (L, 3)) {
    len = lua_tonumber (L, 3);
    if (start + len > lmm->size) return luaL_argerror(L, 3, "address out of range");
  }
  lua_Number x = luaL_checknumber(L, 4);
  switch (len) {
    case 1: *( uint8_t *)(lmm->mem + start) = x; break;
    case 2: *(uint16_t *)(lmm->mem + start) = x; break;
    case 4: *(uint32_t *)(lmm->mem + start) = x; break;
    case 8: *(uint64_t *)(lmm->mem + start) = x; break;
    default: return luaL_argerror(L, 3, "unsupported write size");
  }
  return 1;
}

static int lua_mmap__len (lua_State *L)
{
  struct lua_mmap *lmm = luaL_checkudata (L, 1, lua_mmap_mt);
  lua_pushnumber(L, lmm->size);
  return 1;
}

static int lua_mmap__tostring (lua_State *L)
{
  struct lua_mmap *lmm = luaL_checkudata (L, 1, lua_mmap_mt);
  lua_pushfstring(L, "<mmap %p + %p @ %p>", lmm->mapbase, lmm->size, lmm->mem);
  return 1;
}

static int lua_mmap__gc (lua_State *L)
{
  struct lua_mmap *lmm = luaL_checkudata (L, 1, lua_mmap_mt);
  munmap(lmm->base, lmm->basesize);
  lmm->mem = 0; lmm->size = 0;
  lmm->base = 0; lmm->basesize = 0;
  return 1;
}

static const struct luaL_reg functions[] = {
  { "new", lua_mmap_new },
  { NULL,  NULL         },
};

static const struct luaL_reg mmap_methods[] = {
  {"read",       lua_mmap_read       },
  {"write",      lua_mmap_write      },
  {"get",        lua_mmap_get        },
  {"put",        lua_mmap_put        },
  // {"getle",      lua_mmap_getle      },
  // {"getbe",      lua_mmap_getbe      },
  // {"putle",      lua_mmap_putle      },
  // {"putbe",      lua_mmap_putbe      },
  {"__tostring", lua_mmap__tostring  },
  {"__len",      lua_mmap__len       },
  {"__gc",       lua_mmap__gc        },
  {NULL,         NULL                },
};


int luaopen_mmap (lua_State *L)
{
  luaLM_register_metatable (L, lua_mmap_mt, mmap_methods);
  luaL_register (L, "mmap", functions);
  return 1;
}
