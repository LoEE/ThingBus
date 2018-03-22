///
/// This is a library for adding Lua callbacks to NSRunLoops.
///

/// ## Necessary declarations
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/NSRunLoop.h>
#include <Foundation/NSTimer.h>

#include <lua.h>
#include <lauxlib.h>

#include "../common/debug.h"
#include "../common/luaP.h"
#include "../common/LM.h"

/// loop.file callback and context structure.
char *loop_file_mt = "<loop.file>";
static char *loop_file_proxy_table = "<loop.file.proxy_table>";
static struct file_obj *find_or_create_loop_file (lua_State *L, int i);
static void file_obj_callback (CFSocketRef sock, CFSocketCallBackType type, CFDataRef addr, const void *data, void *L);
static int _getfd (lua_State *L, int i);
struct file_obj {
  lua_State *L;
  int fd;
  CFSocketRef cfsock;
  CFRunLoopSourceRef cfsource;
};
/// run_after callback code
const char *loop_timer_mt = "<loop.timer>";
struct loop_objc {
  NSObject *obj;
};
@interface LuaTimer : NSObject {
  lua_State *L;
  NSTimer *timer;
}
+(LuaTimer *)timerAfter:(double)seconds state:(lua_State *)L callbackIndex:(int)i;
-(void)fired:(NSTimer *)_t;
-(void)cancel;
@end

/// ## Public API
static int cancel_readable (lua_State *L);
static int cancel_writeable (lua_State *L);

static int _async (lua_State *L, char *cbfield, CFOptionFlags flag, CFOptionFlags cflag)
{
  int cancel = lua_isnoneornil (L, 2);
  int continous = lua_toboolean (L, 3);
  struct file_obj *fo = find_or_create_loop_file (L, 1);

  if (cancel) {
    CFSocketDisableCallBacks (fo->cfsock, flag);
    return 0;
  }
  
  luaL_checktype (L, 2, LUA_TFUNCTION);

  lua_getfenv (L, -1);
  lua_pushvalue (L, 2);
  lua_setfield (L, -2, cbfield);
  lua_pop (L, 1); // env

  CFSocketEnableCallBacks (fo->cfsock, flag);
  CFOptionFlags sockopt = CFSocketGetSocketFlags(fo->cfsock);
  if (continous) sockopt |= cflag; else sockopt &= ~cflag;
  CFSocketSetSocketFlags(fo->cfsock, sockopt);

  lua_pushvalue (L, 1);
  switch (flag) {
    case kCFSocketReadCallBack: lua_pushcclosure (L, cancel_readable, 1); break;
    case kCFSocketWriteCallBack: lua_pushcclosure (L, cancel_writeable, 1); break;
  }
  return 1;
}

static int on_readable (lua_State *L)
{
  return _async (L, "read", kCFSocketReadCallBack, kCFSocketAutomaticallyReenableReadCallBack);
}

static int on_writeable (lua_State *L)
{
  return _async (L, "write", kCFSocketWriteCallBack, kCFSocketAutomaticallyReenableWriteCallBack);
}

static int cancel_readable (lua_State *L)
{
  int i = abs_index (L, -1);
  lua_pop (L, i);
  lua_pushvalue (L, lua_upvalueindex (1));
  return _async (L, "read", kCFSocketReadCallBack, 0);
}

static int cancel_writeable (lua_State *L)
{
  int i = abs_index (L, -1);
  lua_pop (L, i);
  lua_pushvalue (L, lua_upvalueindex (1));
  return _async (L, "write", kCFSocketWriteCallBack, 0);
}

static int loop_run (lua_State *L)
{
  L=L;
  [[NSRunLoop currentRunLoop] run];
  return 0;
}

#if 0
static int file_async_connect (lua_State *L)
{
  // USE: CFSocketConnectToAddress
  return _file_async (L, "connect", kCFSocketConnectCallBack, 0);
}
#endif

/// ### loop.run_after (seconds, function)
/// Registers a function to call after `seconds` seconds.
static int run_after (lua_State *L)
{
  double seconds = luaL_checknumber (L, 1);
  [LuaTimer timerAfter:seconds state:L callbackIndex:2];
  return 1;
}

/// ### timer.cancel (self)
/// Cancels the timer.
static int timer_cancel (lua_State *L)
{
  struct loop_objc *p = luaL_checkudata (L, 1, loop_timer_mt);
  [(LuaTimer *)p->obj cancel];
  return 0;
}

/// ### timer.__gc (self)
/// GC callback. Releases the Objective-C timer.
static int timer_gc (lua_State *L)
{
  struct loop_objc *p = luaL_checkudata (L, 1, loop_timer_mt);
  LuaTimer *lt = (LuaTimer *)p->obj;
  [lt cancel];
  [lt release];
  p->obj = nil;
  return 0;
}

/// Call `luaopen_oninput` to load the library.
static const struct luaL_reg functions[] = {
  {"run_after",      run_after    },
  {"on_readable",    on_readable  },
  {"on_writeable",   on_writeable },
  {"on_acceptable",  on_readable  }, // acceptable and readable are the same events on OS X
  {"run",            loop_run     },
  {NULL,             NULL         },
};

static const struct luaL_reg timer_methods[] = {
  {"__gc",        timer_gc     },
  {"__call",      timer_cancel },
  {NULL,          NULL         },
};

static int file_gc (lua_State *L);
static const struct luaL_reg file_methods[] = {
  {"__gc",        file_gc          },
  {NULL,          NULL             },
};

static int traceback(lua_State *L)
{
    if (!lua_isstring(L, 1)) return 1;
    lua_getglobal(L, "debug");
    if (!lua_istable(L, -1)) { lua_pop(L, 1); return 1; }

    lua_getfield(L, -1, "traceback");
    if (!lua_isfunction(L, -1)) { lua_pop(L, 2); return 1; }

    lua_pushvalue(L, 1);    /* pass error message */
    lua_pushinteger(L, 2);  /* skip this function in traceback */
    lua_call(L, 2, 1);      /* call debug.traceback */
    return 1;
}

int luaopen_loop (lua_State *L)
{
  luaP_create_proxy_table (L, loop_file_proxy_table, "k");
  luaLM_register_metatable (L, loop_timer_mt, timer_methods);
  luaLM_register_metatable (L, loop_file_mt, file_methods);

  lua_newtable (L);
  luaL_register (L, NULL, functions);

  return 1;
}

/// ## Private functions
/// Registers the file object found under the index `i` (which has to be an integer or has 
/// to implement the `getfd` method) with the run loop. Returns a (private) loop.file object pointer.
static struct file_obj *find_or_create_loop_file (lua_State *L, int i)
{
  i = abs_index (L, i);

  if (luaP_push_link (L, loop_file_proxy_table, i)) {
    return luaL_checkudata (L, -1, loop_file_mt);
  }

  int fd = _getfd (L, i);

  if (fd < 0) luaL_error (L, "file object's getfd method did not return a valid file descriptor");

  struct file_obj *fo = luaLM_create_userdata (L, sizeof(struct file_obj), loop_file_mt);

  fo->cfsock = 0; fo->cfsource = 0;

  CFSocketContext cfsocket_ctx = { 0, fo, 0, 0, 0 };
  fo->cfsock = CFSocketCreateWithNative(NULL, fd,
      kCFSocketReadCallBack | kCFSocketWriteCallBack, file_obj_callback, &cfsocket_ctx); // FIXME: kCFSocketConnectCallBack
  if(!fo->cfsock) return (void *)(intptr_t)luaL_error (L, "CFSocketCreateWithNative[add_fd] failed");
#if 0
  // FIXME: what to do here?
  if(luaLM_push_proxy (L, fo->cfsock)) {
    // this native handle already has a CFSocket so we'll return it's Lua wrapper
    // and discard the one created above
    return 1;
  }
#endif

  CFOptionFlags sockopt = CFSocketGetSocketFlags(fo->cfsock);
  sockopt &= ~kCFSocketCloseOnInvalidate;
  CFSocketSetSocketFlags(fo->cfsock, sockopt);

  fo->L = luaLM_get_main_state (L);
  fo->fd = fd;

  luaLM_register_proxy (L, fo->cfsock, i);
  luaP_register_link (L, loop_file_proxy_table, i, -1);
  lua_newtable (L);
  lua_setfenv (L, -2);

  fo->cfsource = CFSocketCreateRunLoopSource (NULL, fo->cfsock, 0);
  if(!fo->cfsource) return (void *)(intptr_t)luaL_error (L, "CFSocketCreateRunLoopSource[add_fd] failed");

  CFRunLoopAddSource ([[NSRunLoop currentRunLoop] getCFRunLoop], fo->cfsource, (CFStringRef)NSDefaultRunLoopMode);

  // CFSocketDisableCallBacks must be called after CFRunLoopAddSource (undocumented behaviour)
  CFSocketDisableCallBacks (fo->cfsock, kCFSocketReadCallBack | kCFSocketWriteCallBack); // FIXME: kCFSocketConnectCallBack

  return fo;
}

static int file_gc (lua_State *L)
{
  struct file_obj *fo = luaL_checkudata (L, 1, loop_file_mt);
  if (fo->cfsock) {
    CFSocketInvalidate (fo->cfsock);
    CFRelease (fo->cfsock);
  }
  if (fo->cfsource) CFRelease (fo->cfsource);
  return 0;
}

/// If the object on top of the stack is a number converts it to an int,
/// calls the `getfd` method on this object othwerwise. This method should 
/// return a socket handle (an integer).
static int _getfd (lua_State *L, int i)
{
  i = abs_index (L, i);
  int fd = -1;
  if (lua_isnumber (L, i)) return lua_tonumber (L, i);
  lua_getfield (L, i, "getfd");
  if (!lua_isnil(L, -1)) {
    lua_pushvalue(L, i);
    lua_call(L, 1, 1);
    if (lua_isnumber(L, -1))
      fd = lua_tonumber(L, -1);
    lua_pop(L, 1);
  } else {
    lua_pop(L, 1);
  }
  return fd;
}

/// The file callback function passed to the NSRunLoop.
static void file_obj_callback (CFSocketRef sock, CFSocketCallBackType type, CFDataRef addr, const void *data, void *info)
{
  sock = sock; addr = addr, data = data; // unused args
  struct file_obj *fo = info;
  lua_State *L = fo->L;
  STACK_CHECK;
  
  if(!luaLM_push_proxy (L, fo->cfsock)) return; // should not happen (__gc invalidates the socket)
  if(!luaP_push_link (L, loop_file_proxy_table, -1)) {
    eprintf ("no Lua proxy found for CFSocket: %p\n", fo->cfsock);
    return;
  }
  char *cbfield = 0;

  switch (type) {
    case kCFSocketReadCallBack:
      cbfield = "read";
      break;
    case kCFSocketWriteCallBack:
      cbfield = "write";
      break;
    // FIXME: kCFSocketConnectCallBack
    // kCFSocketAcceptCallBack, kCFSocketDataCallBack -- these fetch data themselves which makes them 
    // incompatible with LuaSocket
  }

  if (!cbfield) {
    int t = type;
    _D("invalid CFSocket callback type: %d, for socket: %p (fd: %d)",
        t, lua_touserdata (L, -2), fo->fd);
    lua_pop (L, 2); // userdata, file object
    STACK_CHECK_END;
    return;
  }

  lua_pushcfunction(L, traceback);
  lua_getfenv (L, -2);
  lua_getfield (L, -1, cbfield);
  if (lua_isnil (L, -1)) {
    // spurious callback
    int t = type;
    _D("spurious CFSocket callback of type: %d, for socket: %p (fd: %d)",
        t, lua_touserdata (L, -2), fo->fd);
    lua_pop (L, 2); // env, nil
  } else {
    lua_insert (L, -2);
    lua_pop (L, 1); // env
    // lua file object = -4, ud = -3, traceback, callback
    lua_pushvalue (L, -3);
    lua_pushvalue (L, -5);

    if (lua_pcall (L, 2, 0, -4)) {
      eprintf ("loop callback error: %s\n", lua_tostring (L, -1));
      exit(4);
    }
  }

  lua_pop (L, 3); // userdata, file object, traceback
  STACK_CHECK_END;
}

@implementation LuaTimer

+ (LuaTimer *)timerAfter:(double)seconds state:(lua_State *)L callbackIndex:(int)i
{
  luaL_checktype (L, i, LUA_TFUNCTION);

  LuaTimer *lt = [[LuaTimer alloc] init];

  struct loop_objc *p = luaLM_create_userdata (L, sizeof(struct loop_objc), loop_timer_mt);
  luaLM_register_strong_proxy (L, lt, -1);

  p->obj = [lt retain];

  lua_createtable (L, 0, 1);
  lua_pushvalue (L, i);
  lua_setfield (L, -2, "callback");
  lua_setfenv (L, -2);

  lt->L = luaLM_get_main_state (L);
  lt->timer = [[NSTimer scheduledTimerWithTimeInterval:seconds target:lt selector:@selector(fired:) userInfo:NULL repeats:false] retain];

  return [lt autorelease];
}

- (void)fired:(NSTimer *)_t
{
  STACK_CHECK;
  _t = _t;
  
  if (!luaLM_push_strong_proxy(L, self)) {
    eprintf ("cannot retrieve the strong Lua proxy for a timer context: %p\n", self);
    return;
  }
  luaLM_unregister_strong_proxy (L, self);
  
  lua_getfenv (L, -1);
  lua_pushstring (L, "callback");
  lua_rawget (L, -2);

  if (lua_pcall (L, 0, 0, 0))
    luaL_error (L, "timer %p callback error: %s\n", self, lua_tostring (L, -1));

  lua_pop (L, 2); // timer userdata + its environment
  STACK_CHECK_END;
}

- (void)cancel
{
  [timer invalidate];
}

- (void)dealloc
{
  [timer release];
  [super dealloc];
}

@end
