#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "../common/LM.h"
#include "../common/debug.h"

#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

#if !defined(__ANDROID__)
#include <sys/ioctl.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>

static int get_funcs (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  long funcs;
  if(ioctl(fd, I2C_FUNCS, &funcs) < 0) {
    return luaLM_posix_error (L, __FUNCTION__);
  }
  return (lua_pushnumber(L, funcs), 1);
}

static int xchg (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  size_t n = 0;
  const char *_s = luaL_checklstring (L, 2, &n);
  const char *s = _s;
  struct i2c_msg msgs[I2C_RDRW_IOCTL_MAX_MSGS];
  int i = -1;

  const char *err;

  while(n) {
    n--;
    switch(*s++) {
      case '{':
        i++;
        msgs[i].flags = 0; // important to properly call free() in case of any errors
        msgs[i].buf = 0;
        if (i >= I2C_RDRW_IOCTL_MAX_MSGS) {
          err = "too many STARTs in one transaction at %d"; goto error;
        }
        if(!n) {
          err = "command string too short at %d"; goto error;
        }
        msgs[i].addr = *s++;
        break;
      case '}':
        n = 0;
        break;
      case 'w':
        if(msgs[i].buf) {
          err = "cannot switch directions without a new START condition at %d"; goto error;
        }
        if(i < 0) {
          err = "missing START before %d"; goto error;
        }
        if(!n) {
          err = "command string too short at %d"; goto error;
        }
        msgs[i].len = *s++;
        if(msgs[i].len == 0 || n < msgs[i].len) {
          err = "invalid length at %d"; goto error;
        }
        msgs[i].buf = (uint8_t *)s;
        s += msgs[i].len;
        break;
      case 'r':
        if(msgs[i].buf) {
          err = "cannot switch directions without a new START condition at %d"; goto error;
        }
        if(i < 0) {
          err = "missing START before %d"; goto error;
        }
        if(!n) {
          err = "command string too short at %d"; goto error;
        }
        msgs[i].len = *s++;
        if(msgs[i].len == 0) {
          err = "invalid length at %d"; goto error;
        }
        msgs[i].buf = malloc(msgs[i].len);
        if (!msgs[i].buf) {
          err = "could not allocate the receive buffer at %d"; goto error;
        }
        msgs[i].flags = I2C_M_RD;
        break;
      default:
        err = "error in command string at %d";
        goto error;
        break;
    }
  }
  i++;

  struct i2c_rdwr_ioctl_data cmds = {
    .msgs = msgs,
    .nmsgs = i,
  };

  if(ioctl(fd, I2C_RDWR, &cmds) < 0) {
    return luaLM_posix_error (L, __FUNCTION__);
  }

  int r = 0;
  for(int j = 0; j < i; j++) {
    if(msgs[j].flags & I2C_M_RD) {
      lua_pushlstring(L, (char *)msgs[j].buf, msgs[j].len); r++;
      free(msgs[j].buf);
    }
  }

  return r;

error:
  for(int j = 0; j < i; j++) {
    if (msgs[j].flags & I2C_M_RD)
      free(msgs[j].buf);
  }
  return luaL_error(L, err, s - _s);
}

static const struct luaL_reg funcs[] = {
  { "get_funcs", get_funcs },
  { "xchg",      xchg      },
  { NULL,        NULL      },
};
#endif

int luaopen_i2c (lua_State *L)
{
#if !defined(__ANDROID__)
  lua_newtable(L);
  luaL_register (L, NULL, funcs);
  return 1;
#else
  return 0;
#endif
}
