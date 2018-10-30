#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "../common/LM.h"
#include "../common/debug.h"
#include "../common/str.h"

#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

#if !defined(__ANDROID__)
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>

#define SPI_MAX_TRANSFERS 10

#include <linux/types.h>

/*
 * linux-sunxi 3.4 changed the size of the struct so we have to act accordingly
 */
struct spi_ioc_transfer_sunxi34 {
  __u64   tx_buf;
  __u64   rx_buf;

  __u32   len;
  __u32   speed_hz;

  __u16   delay_usecs;
  __u16   interbyte_usecs;
  __u8    bits_per_word;
  __u8    cs_change;
  __u32   pad;
};

/* not all platforms use <asm-generic/ioctl.h> or _IOC_TYPECHECK() ... */
#define SPI_MSGSIZE_SUNXI34(N) \
  ((((N)*(sizeof (struct spi_ioc_transfer_sunxi34))) < (1 << 13)) \
    ? ((N)*(sizeof (struct spi_ioc_transfer_sunxi34))) : 0)
#define SPI_IOC_MESSAGE_SUNXI34(N) _IOW(SPI_IOC_MAGIC, 0, char[SPI_MSGSIZE_SUNXI34(N)])



static int xchg (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  uint8_t mode = luaL_checknumber (L, 2);
  size_t n = 0;
  const char *_s = luaL_checklstring (L, 3, &n);
  const char *s = _s;
  struct spi_ioc_transfer msgs[SPI_MAX_TRANSFERS] = {{0}};
  int i = 0;
  const char *special = luaL_optstring (L, 4, 0);

  uint32_t speed_hz = 0;
  uint8_t bits_per_word = 0;

  const char *err;

  while(n) {
    n--;
    if (i > SPI_MAX_TRANSFERS) {
      err = "too many transfer in one transaction at %d"; goto error;
    }
    msgs[i].speed_hz = speed_hz;
    msgs[i].bits_per_word = bits_per_word;
    switch(*s++) {
      case 'w':
        if(!n) {
          err = "command string too short at %d"; goto error;
        }
        msgs[i].len = *s++; n--;
        if(msgs[i].len == 0 || n < msgs[i].len) {
          err = "invalid length at %d"; goto error;
        }
        msgs[i].tx_buf = (uint64_t)(intptr_t)s;
        s += msgs[i].len; n -= msgs[i].len;
        i++;
        break;
      case 'x':
        if(!n) {
          err = "command string too short at %d"; goto error;
        }
        msgs[i].len = *s++; n--;
        if(msgs[i].len == 0 || n < msgs[i].len) {
          err = "invalid length at %d"; goto error;
        }
        msgs[i].tx_buf = (uint64_t)(intptr_t)s;
        s += msgs[i].len; n -= msgs[i].len;
        msgs[i].rx_buf = (uint64_t)(intptr_t)malloc(msgs[i].len);
        if (!msgs[i].rx_buf) {
          err = "could not allocate the receive buffer at %d"; goto error;
        }
        i++;
        break;
      case 'r':
        msgs[i].len = *s++; n--;
        if(msgs[i].len == 0) {
          err = "invalid length at %d"; goto error;
        }
        msgs[i].rx_buf = (uint64_t)(intptr_t)malloc(msgs[i].len);
        if (!msgs[i].rx_buf) {
          err = "could not allocate the receive buffer at %d"; goto error;
        }
        i++;
        break;
      case '!':
        msgs[i].cs_change = 1;
        break;
      case 'd':
        msgs[i].delay_usecs = (s[0] << 8) + s[1];
        s += 2; n -= 2;
        break;
      case '@':
        speed_hz = (s[0] << 24) + (s[1] << 16) + (s[2] << 8) + s[3];
        s += 4; n -= 4;
        break;
      case '#':
        bits_per_word = *s++; n--;
        break;
      default:
        err = "error in command string at %d";
        goto error;
        break;
    }
  }

  if(ioctl(fd, SPI_IOC_WR_MODE, &mode) < 0)
    goto posix_error;

  if(special && !str_diff("sunxi34", special)) {
    if(ioctl(fd, SPI_IOC_MESSAGE_SUNXI34(i), msgs) < 0)
      goto posix_error;
  } else {
    if(ioctl(fd, SPI_IOC_MESSAGE(i), msgs) < 0)
      goto posix_error;
  }

  int r = 0;
  for(int j = 0; j < i; j++) {
    if(msgs[j].rx_buf) {
      lua_pushlstring(L, (char *)(intptr_t)msgs[j].rx_buf, msgs[j].len); r++;
      free((void *)(intptr_t)msgs[j].rx_buf);
    }
  }

  if (r == 0) {
    lua_pushboolean(L, 1);
    return 1;
  }

  return r;

posix_error:
  for(int j = 0; j < i; j++) {
    if (msgs[j].rx_buf) free((void *)(intptr_t)msgs[j].rx_buf);
  }
  return luaLM_posix_error (L, __FUNCTION__);

error:
  for(int j = 0; j < i; j++) {
    if (msgs[j].rx_buf) free((void *)(intptr_t)msgs[j].rx_buf);
  }
  return luaL_error(L, err, s - _s);
}

static const struct luaL_reg funcs[] = {
  { "xchg",      xchg      },
  { NULL,        NULL      },
};
#endif

int luaopen_spi (lua_State *L)
{
#if !defined(__ANDROID__)
  lua_newtable(L);
  luaL_register (L, NULL, funcs);
  return 1;
#else
  return 0;
#endif
}
