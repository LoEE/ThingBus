#include <signal.h>
#include <errno.h>
#include <string.h>

// Lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <../common/LM.h>

void keyboard_interrupt(void);
static void sigint (int i)
{
  keyboard_interrupt();
}

void enable_keyboard_interrupt_handler (void)
{
  signal(SIGINT, sigint);
}

void disable_keyboard_interrupt_handler (void)
{
  signal(SIGINT, SIG_DFL);
}

#include <sys/types.h>
#include <unistd.h>

static int os_pipe (lua_State *L)
{
  int fds[2];
  if (pipe(fds) < 0) {
    const char *msg = strerror (errno);
    lua_pushnil (L);
    lua_pushstring (L, msg);
    return 2;
  }
  lua_pushnumber(L, fds[0]);
  lua_pushnumber(L, fds[1]);
  return 2;
}

static int os_getpid (lua_State *L)
{
  pid_t pid = getpid();
  lua_pushinteger(L, pid);
  return 1;
}

static int io_raw_read (lua_State *L)
{
  int fd = luaLM_checkfd (L, 1);

  char buffer[4096];
  int ret = read (fd, buffer, sizeof(buffer));
  if (!ret) { // EOF
    lua_pushnil (L);
    lua_pushliteral (L, "eof");
    return 2;
  }
  if (ret < 0) { // error
    const char *msg = strerror (errno);
    lua_pushnil (L);
    lua_pushstring (L, msg);
    return 2;
  }
  lua_pushlstring (L, buffer, ret);
  return 1;
}

static int io_raw_write (lua_State *L)
{
  int fd = luaLM_checkfd(L, 1);
  size_t n = 0;
  const char *s = luaL_checklstring(L, 2, &n);
  size_t off = luaL_optnumber(L, 3, 0) - 1;
  if (off > n) off = n;

  int ret = write(fd, s + off, n - off);
  if (ret < 0) { // error
    const char *msg = strerror(errno);
    lua_pushnil(L);
    lua_pushstring(L, msg);
    return 2;
  }
  // successful (though maybe partial) write
  lua_pushnumber(L, ret);
  return 1;
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


int luaopen_posix_c(lua_State *L);
const struct luaL_reg platform_posix_preloads[] = {
  //{ "posix",          luaopen_posix_c },
  { 0,                0               },
};

void lua_init_platform_posix(lua_State *L)
{
  luaLM_preload (L, platform_posix_preloads);
  const struct luaL_reg os_additions[] = {
    { "pipe",    os_pipe   },
    { "getpid",  os_getpid },
    { 0,         0         },
  };
  luaL_register (L, "os", os_additions);
  const struct luaL_reg io_additions[] = {
    { "raw_read",   io_raw_read  },
    { "raw_write",  io_raw_write },
    { "raw_close",  io_raw_close },
    { 0,            0            },
  };
  luaL_register (L, "io", io_additions);
}
