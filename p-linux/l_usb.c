#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "../common/LM.h"
#include "../common/debug.h"

#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

#include <sys/ioctl.h>

#define USBDEVFS_URB_TYPE_ISO              0
#define USBDEVFS_URB_TYPE_INTERRUPT        1
#define USBDEVFS_URB_TYPE_CONTROL          2
#define USBDEVFS_URB_TYPE_BULK             3

#define USBDEVFS_MAXDRIVERNAME 255

struct usbdevfs_getdriver {
  unsigned int intf;
  char name[USBDEVFS_MAXDRIVERNAME + 1];
};

struct usbdevfs_ioctl {
  int intf;
  int code;
  void *data;
};

struct usbdevfs_iso_packet_desc {
  unsigned int length;
  unsigned int actual_length;
  unsigned int status;
};

struct usbdevfs_urb {
  unsigned char type;
  unsigned char endpoint;
  int status;
  unsigned int flags;
  void *buffer;
  int buffer_length;
  int actual_length;
  int start_frame;
  int number_of_packets;
  int error_count;
  unsigned int signr;     /* signal to be sent on completion,
                             or 0 if none should be sent. */
  void *usercontext;
  struct usbdevfs_iso_packet_desc iso_frame_desc[0];
};

#define USBDEVFS_SETCONFIGURATION  _IOR('U', 5, unsigned int)
#define USBDEVFS_GETDRIVER         _IOW('U', 8, struct usbdevfs_getdriver)
#define USBDEVFS_SUBMITURB         _IOR('U', 10, struct usbdevfs_urb)
#define USBDEVFS_REAPURBNDELAY     _IOW('U', 13, void *)
#define USBDEVFS_CLAIMINTERFACE    _IOR('U', 15, unsigned int)
#define USBDEVFS_RELEASEINTERFACE  _IOR('U', 16, unsigned int)
#define USBDEVFS_IOCTL             _IOWR('U', 18, struct usbdevfs_ioctl)
#define USBDEVFS_DISCONNECT        _IO('U', 22)
#define USBDEVFS_CONNECT           _IO('U', 23)

static int _ioctl(lua_State *L, int fd, int code, void *arg, const char *name)
{
  if(ioctl (fd, code, arg) < 0)
    return luaLM_posix_error (L, name);
  return 0;
}

static int _simple_ioctl(lua_State *L, int fd, int code, void *arg, const char *name)
{
  int r;
  return (r = _ioctl(L, fd, code, arg, name)) ? r
    : (lua_pushboolean (L, 1), 1);
}

static int set_configuration (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int cfgv = luaL_checknumber (L, 2);
  return _simple_ioctl(L, fd, USBDEVFS_SETCONFIGURATION, &cfgv, __FUNCTION__);
}

static int get_driver (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int intf = luaL_checknumber (L, 2);
  struct usbdevfs_getdriver arg = { .intf = intf };
  if(ioctl (fd, USBDEVFS_GETDRIVER, &arg) < 0) {
    if (errno == ENODATA) return (lua_pushnil(L), 1);
    return luaLM_posix_error (L, __FUNCTION__);
  }
  return (lua_pushstring (L, arg.name), 1);
}

static int claim_interface (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int intf = luaL_checknumber (L, 2);
  return _simple_ioctl(L, fd, USBDEVFS_CLAIMINTERFACE, &intf, __FUNCTION__);
}

static int release_interface (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int intf = luaL_checknumber (L, 2);
  return _simple_ioctl(L, fd, USBDEVFS_RELEASEINTERFACE, &intf, __FUNCTION__);
}

static int connect_kernel (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int intf = luaL_checknumber (L, 2);
  struct usbdevfs_ioctl cmd = {
    .intf = intf,
    .code = USBDEVFS_CONNECT,
  };
  return _simple_ioctl(L, fd, USBDEVFS_IOCTL, &cmd, __FUNCTION__);
}

static int disconnect_kernel (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int intf = luaL_checknumber (L, 2);
  struct usbdevfs_ioctl cmd = {
    .intf = intf,
    .code = USBDEVFS_DISCONNECT,
  };
  return _simple_ioctl(L, fd, USBDEVFS_IOCTL, &cmd, __FUNCTION__);
}

static int bulk_write (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int ep = luaL_checknumber (L, 2);
  size_t n = 0;
  const char *s = luaL_checklstring (L, 3, &n);
  struct usbdevfs_urb *urb = malloc (sizeof(struct usbdevfs_urb));
  if (!urb) return luaL_error (L, "could not allocate the URB struct");
  memset (urb, 0, sizeof(struct usbdevfs_urb));
  urb->usercontext = urb;
  urb->type = USBDEVFS_URB_TYPE_BULK;
  urb->endpoint = ep;
  urb->buffer = (char *)s;
  urb->buffer_length = n;
  luaLM_register_strong_proxy (L, urb, 3);
  return _ioctl(L, fd, USBDEVFS_SUBMITURB, urb, __FUNCTION__)
    | (lua_pushlightuserdata (L, urb), 1);
}

static int bulk_read (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int ep = luaL_checknumber (L, 2);
  size_t n = luaL_checknumber (L, 3);
  char *s = malloc (n);
  if (!s) return luaL_error (L, "could not allocate %s bytes", n);
  struct usbdevfs_urb *urb = malloc (sizeof(struct usbdevfs_urb));
  if (!urb) return luaL_error (L, "could not allocate the URB struct");
  memset (urb, 0, sizeof(struct usbdevfs_urb));
  urb->usercontext = urb;
  urb->type = USBDEVFS_URB_TYPE_BULK;
  urb->endpoint = ep;
  urb->buffer = s;
  urb->buffer_length = n;
  return _ioctl(L, fd, USBDEVFS_SUBMITURB, urb, __FUNCTION__)
    | (lua_pushlightuserdata (L, urb), 1);
}

static int reap_urb (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  struct usbdevfs_urb *urb;
  if (ioctl(fd, USBDEVFS_REAPURBNDELAY, &urb) < 0) {
    if (errno == EAGAIN) return 0;
    return luaLM_posix_error (L, NULL);
  }
  lua_pushlightuserdata (L, urb->usercontext);
  if (urb->status == 0 || urb->status == -EREMOTEIO) { // success
    if (urb->endpoint & 0x80) { // IN
      lua_pushlstring (L, urb->buffer, urb->actual_length);
      free (urb->buffer);
      free (urb);
      return 2;
    } else { // OUT
      lua_pushnumber (L, urb->actual_length);
      luaLM_unregister_strong_proxy (L, urb);
      free (urb);
      return 2;
    }
  } else {
    int err = urb->status;
    if (err != ENODEV) err = -err;
    lua_pushnil (L);
    lua_pushstring (L, strerror (err)); // message
    lua_pushboolean (L, err != EPIPE); // fatal
    lua_pushnumber (L, err); // errno
    return 5;
  }
} 

static const struct luaL_reg funcs[] = {
  { "set_configuration",  set_configuration },
  { "get_driver",         get_driver        },
  { "claim_interface",    claim_interface   },
  { "release_interface",  release_interface },
  { "connect_kernel",     connect_kernel    },
  { "disconnect_kernel",  disconnect_kernel },
  { "bulk_read",          bulk_read         },
  { "bulk_write",         bulk_write        },
  { "reap_urb",           reap_urb          },
  { NULL,                 NULL              },
};

int luaopen_usb (lua_State *L)
{
  lua_newtable(L);
  luaL_register (L, NULL, funcs);
  return 1;
}
