#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <Shlwapi.h> // PathRemoveFileSpec
#include <libgen.h> // dirname

// Lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "../common/LM.h"

#include "../common/debug.h"

char *realpath (const char *path, char *rpath)
{
  DWORD ret = GetFullPathNameA(path, PATH_MAX, rpath, NULL);
  FAIL_ON(ret == 0, "GetFullPathName[os_realpath]");
  rpath[ret] = '\0';
  return rpath;
}

char *get_executable_path (void)
{
  char exename[PATH_MAX];

  DWORD ret = GetModuleFileNameA(NULL, exename, sizeof(exename));
  FAIL_ON(ret == 0 || ret >= sizeof(exename), "GetModuleFileName[get_executable_path]");
  exename[ret] = 0;
  //PathRemoveFileSpecA(exename);

  return strdup (exename);
}

int luaopen_winapi(lua_State *L);
const struct luaL_reg platform_preloads[] = {
  { "winapi",         luaopen_winapi      },
  { 0,                0                   },
};

void keyboard_interrupt(void);
static BOOL WINAPI ctrl_handler (DWORD dwCtrlType)
{
  if (dwCtrlType == CTRL_C_EVENT)
  {
    keyboard_interrupt();
    return TRUE;
  }
  return FALSE;
}

void enable_keyboard_interrupt_handler (void)
{
  SetConsoleCtrlHandler(ctrl_handler, TRUE);
}

void disable_keyboard_interrupt_handler (void)
{
  SetConsoleCtrlHandler(ctrl_handler, FALSE);
}

void init_platform (void)
{
}

struct forwarder_ctx {
  HANDLE in_h, in_thd, out_fd;
  char buf[2048];
};

static DWORD WINAPI console_forwarder (LPVOID param)
{
  struct forwarder_ctx *c = param;
  while (1) {
    DWORD inlen;
    int ret = ReadFile(c->in_h, c->buf, sizeof(c->buf), &inlen, NULL);
    FAIL_ON(!ret, "ReadFile[in]");
    char *s = c->buf;
    while (inlen > 0) {
      OVERLAPPED ol;
      memset (&ol, 0, sizeof(ol));
      ret = WriteFile(c->out_fd, s, inlen, NULL, &ol);
      if (!ret) {
        DWORD err = GetLastError();
        if (err != ERROR_IO_PENDING) goto fail;
      }
      DWORD n;
      ret = GetOverlappedResult(c->out_fd, &ol, &n, TRUE);
      if (ret) {
        inlen -= n;
        s += ret;
      } else {
fail:
        FAIL_ON(1, "write[console_forwarder]");
      }
    }
  }
}

static int os_forward_console(lua_State *L)
{
  struct forwarder_ctx *c = malloc(sizeof(struct forwarder_ctx));
  if(!c) return luaL_error(L, "cannot allocate memory");
  c->out_fd = (HANDLE)luaLM_checkfd (L, 1);
  c->in_h = GetStdHandle(STD_INPUT_HANDLE);

  c->in_thd = CreateThread(NULL, 0, console_forwarder, c, 0, NULL);
  FAIL_ON(c->in_thd == NULL, "CreateThread[os_forward_console]");

  luaLM_register_strong_proxy(L, c, 1);

  return 0;
}

static int os_getpid (lua_State *L)
{
  pid_t pid = _getpid();
  lua_pushinteger(L, pid);
  return 1;
}

static int os_time_unix (lua_State *L)
{
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  // seconds from Windows epoch (1601-01-01 00:00:00 TAI):
  double t = (ft.dwHighDateTime * 4294967296.0 + ft.dwLowDateTime) * 100e-9;
  // converted to UNIX epoch (1970-01-01 00:00:00 TAI)
  t -= 11644473600;
  lua_pushnumber (L, t);
  return 1;
}

static LARGE_INTEGER PerformanceFrequency;

static int os_time_monotonic (lua_State *L)
{
  LARGE_INTEGER ti;
  QueryPerformanceCounter(&ti); // cannot fail on Windows newer than XP
  double t = (double)ti.QuadPart / PerformanceFrequency.QuadPart;
  lua_pushnumber (L, t);
  return 1;
}

static int io_open_osfhandle(lua_State *L)
{
  int handle = luaLM_checkfd (L, 1);
  int fd = _open_osfhandle(handle, 0);

  // _D("handle: %d, fd: %d", handle, fd);
  if (fd < 0)
    return luaLM_posix_error(L, "_open_osfhandle");

  lua_pushnumber(L, fd);
  return 1;
}

static int io_get_osfhandle(lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);
  intptr_t handle = _get_osfhandle(fd);

  // _D("handle: %d, fd: %d", handle, fd);
  if (handle < 0)
    return luaLM_posix_error(L, "_get_osfhandle");

  lua_pushnumber(L, handle);
  return 1;
}

static int io_raw_read (lua_State *L)
{
  HANDLE fd = (HANDLE)luaLM_checkfd (L, 1);

  char buffer[4096];
  OVERLAPPED ol;
  memset (&ol, 0, sizeof(ol));
  DWORD n, err;
  int ret = ReadFile(fd, buffer, sizeof(buffer), NULL, &ol);
  if (!ret) {
    err = GetLastError();
    if (err != ERROR_IO_PENDING) goto fail;
  }
  ret = GetOverlappedResult(fd, &ol, &n, FALSE);
  if (ret) {
    if (n > 0) {
      lua_pushlstring(L, buffer, n);
      return 1;
    } else {
      lua_pushnil(L);
      lua_pushliteral(L, "eof");
      return 2;
    }
    err = GetLastError();
    goto fail;
  }
fail:;
  const char *msg = win32_strerror(err);
  lua_pushnil (L);
  lua_pushstring (L, msg);
  return 2;
}

static int io_raw_close (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);

  int ret = close(fd);
  if (!ret) {
    const char *msg = strerror (errno);
    lua_pushnil (L);
    lua_pushstring (L, msg);
    return 2;
  }

  return 0;
}

static int io_setinherit (lua_State *L)
{
  HANDLE handle = (HANDLE)luaLM_checkfd (L, 1);
  int inherit = lua_toboolean(L, 2);
  int flags = inherit ? HANDLE_FLAG_INHERIT : 0;

  int ret = SetHandleInformation (handle, HANDLE_FLAG_INHERIT, flags);
  if (!ret) {
    const char *msg = win32_strerror(GetLastError());
    lua_pushnil (L);
    lua_pushstring (L, msg);
    return 2;
  }

  return 0;
}

static int io_fsync (lua_State *L)
{
  int fd = luaLM_getfd (L, 1);
  intptr_t handle = _get_osfhandle(fd);

  if (!FlushFileBuffers ((HANDLE)handle)) {
    const char *msg = win32_strerror(GetLastError());
    lua_pushnil (L);
    lua_pushstring (L, msg);
    return 2;
  }

  lua_pushboolean(L, 1);
  return 1;
}


void lua_init_platform (lua_State *L)
{
  QueryPerformanceFrequency(&PerformanceFrequency); // cannot fail on Windows newer than XP
  const struct luaL_reg os_additions[] = {
    { "forward_console",  os_forward_console },
    { "getpid",           os_getpid          },
    { "time_unix",        os_time_unix       },
    { "time_monotonic",   os_time_monotonic  },
    { 0,                  0                  },
  };
  luaL_register (L, "os", os_additions);
  const struct luaL_reg io_additions[] = {
    { "open_osfhandle",  io_open_osfhandle },
    { "get_osfhandle",   io_get_osfhandle  },
    { "raw_read",        io_raw_read       },
    { "raw_close",       io_raw_close      },
    { "setinherit",      io_setinherit     },
    { "fsync",           io_fsync          },
    { 0,                 0                 },
  };
  luaL_register (L, "io", io_additions);
}
