#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <libgen.h> // dirname
#include <unistd.h> // getpid & readlink

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
const struct luaL_reg platform_preloads[] = {
  { "udev",           luaopen_udev        },
  { "_usb",           luaopen_usb         },
  { 0,                0                   },
};

void init_platform (void)
{
}

void lua_init_platform_posix(lua_State *L);
void lua_init_platform (lua_State *L)
{
  lua_init_platform_posix(L);
}
