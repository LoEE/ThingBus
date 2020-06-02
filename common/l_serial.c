#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "LM.h"
#include "str.h"

#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

#include <fcntl.h>
#include <termios.h>
#include <sys/ioctl.h>

#if defined(__APPLE__)
#include <IOKit/serial/ioss.h>
#elif defined(__linux__)
#include <linux/serial.h>
#endif


static int serial_open(lua_State *L)
{
  size_t n = 0;
  const char *fname = luaL_checklstring(L, 1, &n);
  int fd = open(fname, O_RDWR | O_NOCTTY | O_NDELAY | O_CLOEXEC);
  if (fd < 0)
    return luaLM_posix_error (L, "serial.open");
  lua_pushnumber(L, fd);
  return 1;
}

static int serial_setup(lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  int baudrate = luaL_checknumber (L, 2);
  size_t __attribute__((__unused__)) n = 0;
  const char *charopts = luaL_optstring(L, 3, "8N1");

  if (str_diff(charopts, "8N1"))
    return luaL_error(L, "unsupported character options: %s", charopts);

  struct termios options;

  if (tcgetattr(fd, &options) == -1) return luaLM_posix_error(L, "tcgetattr");

#if defined(__APPLE__)
  // will be set later
#elif defined(__linux__)
  int baudopt = B0;
  switch (baudrate) {
    case 50:     baudopt = B50;     break;
    case 75:     baudopt = B75;     break;
    case 110:    baudopt = B110;    break;
    case 134:    baudopt = B134;    break;
    case 150:    baudopt = B150;    break;
    case 200:    baudopt = B200;    break;
    case 300:    baudopt = B300;    break;
    case 600:    baudopt = B600;    break;
    case 1200:   baudopt = B1200;   break;
    case 1800:   baudopt = B1800;   break;
    case 2400:   baudopt = B2400;   break;
    case 4800:   baudopt = B4800;   break;
    case 9600:   baudopt = B9600;   break;
    case 19200:  baudopt = B19200;  break;
    case 38400:  baudopt = B38400;  break;
    case 57600:  baudopt = B57600;  break;
    case 115200: baudopt = B115200; break;
    case 230400: baudopt = B230400; break;
  }
  if (baudopt == B0) {
    cfsetispeed(&options, B38400);
    cfsetospeed(&options, B38400);
  } else {
    cfsetispeed(&options, baudopt);
    cfsetospeed(&options, baudopt);
  }
#else
#error "custom baudrate setting: unknown platform"
#endif

  options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);

  options.c_iflag |= IGNPAR;

  options.c_iflag &= ~(IXON | IXOFF | IXANY);

  options.c_oflag &= ~OPOST;

  cfmakeraw(&options);

  options.c_cflag &= ~CSIZE;
  options.c_cflag |= CS8;
  options.c_cflag &= ~PARENB;
  options.c_cflag |= CSTOPB;

  options.c_cflag &= ~CRTSCTS;

  if (tcsetattr(fd, TCSANOW, &options) == -1) return luaLM_posix_error(L, "tcsetattr");

#if defined(__APPLE__)
  if (ioctl(fd, IOSSIOSPEED, &baudrate) == -1) return luaLM_posix_error(L, "custom baudrate ioctl (IOSSIOSPEED)");
#elif defined(__linux__)
  if (baudopt == B0) {
    struct serial_struct sstruct;
    if(ioctl(fd, TIOCGSERIAL, &sstruct) < 0) return luaLM_posix_error(L, "custom baudrate ioctl (TIOCGSERIAL)");
    sstruct.custom_divisor = sstruct.baud_base / baudrate;
    sstruct.flags &= ~ASYNC_SPD_MASK;
    sstruct.flags |= ASYNC_SPD_CUST;
    if(ioctl(fd, TIOCSSERIAL, &sstruct) < 0) return luaLM_posix_error(L, "custom baudrate ioctl (TIOCSSERIAL)");
  }
#endif

  lua_pushboolean(L, 1);
  return 1;
}

static const struct luaL_reg funcs[] = {
  { "open",  serial_open  },
  { "setup", serial_setup },
  { NULL,    NULL         },
};

int luaopen_serial (lua_State *L)
{
  lua_newtable(L);
  luaL_register (L, NULL, funcs);
  return 1;
}
