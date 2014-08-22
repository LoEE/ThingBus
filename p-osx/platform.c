#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <libgen.h> // dirname

// mach_error
#include <mach/mach.h>
// mach_absolute_time & co.
#include <mach/mach_time.h>

// _NSGetExecutablePath
#include <mach-o/dyld.h>

// Lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "../common/debug.h"

// for mach_error
static
int vprintf_stderr (const char *fmt, va_list args) {
  return vfprintf (stderr, fmt, args);
}

char *get_executable_path (void)
{
  char _dummy;
  uint32_t path_len = 0;
  _NSGetExecutablePath(&_dummy, &path_len);
  char *exepath = malloc(path_len);
  if (_NSGetExecutablePath(exepath, &path_len)) {
    eprintf ("cannot get executable path\n");
    exit (1);
  }
  char *rexepath = realpath(exepath, NULL);
  if (!rexepath) EXIT_ON_POSIX_ERROR("cannot resolve executable path", 1);
  return rexepath;
}

#include "l_usb.h"
#include "l_loop.h"

const struct luaL_reg platform_preloads[] = {
  { "_loop",          luaopen_loop        },
  { "_usb",           luaopen_usb         },
  { 0,                0                   },
};

static mach_timebase_info_data_t sTimebaseInfo;

static int os_time_monotonic (lua_State *L)
{
  double t = (double)mach_absolute_time() * sTimebaseInfo.numer / sTimebaseInfo.denom / 1.0e9;
  lua_pushnumber (L, t);
  return 1;
}

void init_platform (void)
{
  // for mach_error
  vprintf_stderr_func = vprintf_stderr;

  // for os_time_monotonic
  mach_timebase_info(&sTimebaseInfo);
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
