#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <libgen.h> // dirname
#include <unistd.h> // getpid & readlink
#include <time.h> // clock_gettime

// Lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "../common/debug.h"

char *get_executable_path (void)
{
  char linkname[PATH_MAX];
  char exename[PATH_MAX];

  pid_t pid = getpid();
  if (snprintf(linkname, sizeof(linkname), "/proc/%i/exe", pid) < 0) {
    eprintf ("error: could not build the /proc/*/exe file name\n"); exit(1);
  }

  ssize_t ret = readlink(linkname, exename, sizeof(exename));
  if (ret < 0) EXIT_ON_POSIX_ERROR("cannot read the /proc/*/exe link", 1);
  if (ret >= (ssize_t)sizeof(exename)) { 
    eprintf ("error: /proc/*/exe link length is > PATH_MAX\n"); exit(1);
  }
  exename[ret] = 0;
  return strdup (exename);
}

int luaopen_ev(lua_State *L);
int luaopen_udev(lua_State *L);
int luaopen_usb(lua_State *L);
int luaopen_i2c(lua_State *L);
const struct luaL_reg platform_preloads[] = {
  { "udev",           luaopen_udev        },
  { "_usb",           luaopen_usb         },
  { "_i2c",           luaopen_i2c         },
  { 0,                0                   },
};

static int os_time_monotonic (lua_State *L)
{
  struct timespec ts;
  int ret = clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
  if (ret < 0) EXIT_ON_POSIX_ERROR("cannot get the CLOCK_MONOTONIC_RAW time", 1);
  double t = ts.tv_sec + ts.tv_nsec / 1.0e9;
  lua_pushnumber (L, t);
  return 1;
}

void init_platform (void)
{
}

void lua_init_platform_posix(lua_State *L);
void lua_init_platform (lua_State *L)
{
  lua_init_platform_posix(L);
  const struct luaL_reg os_additions[] = {
    { "time_monotonic", os_time_monotonic },
    { 0,                0                 },
  };
  luaL_register (L, "os", os_additions);
}
