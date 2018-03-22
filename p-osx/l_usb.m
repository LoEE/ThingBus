///
/// This is a library for accessing arbitrary USB devices from Lua on Mac OS X.
///

/// ## Necessary declarations
// lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

// mach_error
#include <mach/mach.h>

// IO Kit
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

// CF* stuff
#include <Foundation/Foundation.h>

#include "../common/debug.h"
#include "../common/str.h"
#include "../common/LM.h"

// silence gcc warnings
#define UNUSED __attribute__((__unused__))

/*
 * userdata objects
 */
const char *usb_filter_mt = "<usb.filter>";
const char *usb_device_mt = "<usb.device>";
const char *usb_interface_mt = "<usb.interface>";
const char *usb_pipe_mt = "<usb.pipe>";

typedef struct usb_filter {
  lua_State *L;
  io_iterator_t add_iter, rem_iter;
  bool call_lua;
} usb_filter;

typedef struct usb_device {
  int connected;
  io_service_t ioservice;
  IOUSBDeviceInterface187 **i;
} usb_device;

typedef struct usb_interface {
  io_service_t ioservice;
  IOUSBInterfaceInterface190 **i;
  CFRunLoopSourceRef source;
} usb_interface;

typedef struct usb_pipe {
  usb_interface *i;
  int idx;
  uint8_t dir, number, type, interval;
  uint16_t size;
} usb_pipe;

usb_filter *check_filter (lua_State *L, int idx)
{
  return luaL_checkudata (L, idx, usb_filter_mt);
}

usb_device *check_device (lua_State *L, int idx)
{
  return luaL_checkudata (L, idx, usb_device_mt);
}

usb_device *check_opendevice (lua_State *L, int idx)
{
  usb_device *d = luaL_checkudata (L, idx, usb_device_mt);
  if (!d->i) luaL_error (L, "device not open");
  return d;
}

usb_interface *check_interface (lua_State *L, int idx)
{
  return luaL_checkudata (L, idx, usb_interface_mt);
}

usb_interface *check_openinterface (lua_State *L, int idx)
{
  usb_interface *i = luaL_checkudata (L, idx, usb_interface_mt);
  if (!i->i) luaL_error (L, "interface not open");
  return i;
}

usb_pipe *check_pipe (lua_State *L, int idx)
{
  usb_pipe *p = luaL_checkudata (L, idx, usb_pipe_mt);
  if (!p->i->i) luaL_error (L, "the pipe's interface is closed");
  return p;
}

/*
 * Lua IOKit USB objects
 */
static int filter_tostring (lua_State *L)
{
  usb_filter *f = check_filter (L, 1);
  lua_pushfstring (L, "usb_filter<%s>", f->add_iter ? "active" : "inactive");
  return 1;
}

static int filter_gc (lua_State *L)
{
  kern_return_t kr;
  usb_filter *f = check_filter (L, 1);

  if (f->add_iter) {
    kr = IOObjectRelease (f->add_iter);
    EXIT_ON_MACH_ERROR (kr, "IOObjectRelease(add_iter)");
    f->add_iter = 0;
  }
  if (f->rem_iter) {
    kr = IOObjectRelease (f->rem_iter);
    EXIT_ON_MACH_ERROR (kr, "IOObjectRelease(rem_iter)");
    f->rem_iter = 0;
  }

  return 0;
}

static int filter_index(lua_State *L)
{
  if (lua_getmetatable(L, 1)) {
    lua_pushvalue(L, 2);
    lua_gettable(L, -2);
    if (!lua_isnil(L, -1)) return 1;
    lua_pop(L, 1);
  }
  check_filter (L, 1);
  if (lua_type (L, 2) == LUA_TSTRING) {
    const char *s = lua_tostring (L, 2);
    if (!str_diff (s, "devices")) {
      lua_getfenv (L, 1);
      lua_getfield (L, -1, "devices");
      return 1;
    }
  }

  return 0;
}

// IO Kit device properties mapping
struct usb_dev_prop_names {
  const char *lua;
  const NSString *iokit;
};

static struct usb_dev_prop_names usb_dev_prop_names[] = {
    {"idVendor",      @kUSBVendorID                 },
    {"idProduct",     @kUSBProductID                },
    {"bcdDevice",     @kUSBDeviceReleaseNumber      },
    {"location",      @kUSBDevicePropertyLocationID },
    {"manufacturer",  @kUSBVendorString             },
    {"product",       @kUSBProductString            },
    {"serial",        @kUSBSerialNumberString       },
    {NULL,            NULL                          },
};

static const NSString *lua_to_iokit_name (const char *name)
{
  struct usb_dev_prop_names *p = usb_dev_prop_names;
  while (p->lua) {
    if (!strcmp (p->lua, name)) return p->iokit;
    p++;
  }
  return NULL;
}

static void push_dev_location_str (lua_State *L, io_service_t service)
{
  const NSNumber *location = IORegistryEntryCreateCFProperty (
      service, (CFStringRef)@kUSBDevicePropertyLocationID, kCFAllocatorDefault, kNilOptions);
  NSString *loc_s = [[NSString alloc] initWithFormat:@"%08x", [location longValue]];
  lua_pushstring (L, [loc_s UTF8String]);
  [loc_s release]; [location release];
}

static void usb_device_added (void *user_data, io_iterator_t iter)
{
  usb_filter *f = user_data;
  lua_State *L = f->L;
  STACK_CHECK;

  if (!luaLM_push_proxy(L, f)) {
    // the GC already threw away our userdata but did not yet call the __gc metamethod
    while (IOIteratorNext (iter));
    return;
  }

  lua_getfenv (L, -1);
  lua_getfield (L, -1, "devices");

  io_service_t service;
  while ((service = IOIteratorNext (iter))) {
    usb_device *d = luaLM_create_userdata (L, sizeof (usb_device), usb_device_mt);
    d->ioservice = service;
    d->connected = 1;

    push_dev_location_str (L, service);
    lua_pushvalue (L, -2);
    lua_settable (L, -4);

    lua_getfield (L, -3, "connect");
    if(lua_isfunction (L, -1)) {
      // argument: device userdata
      lua_insert (L, -2);
      if (lua_pcall (L, 1, 0, 0))
        luaL_error (L, "%s\n", lua_tostring (L, -1));
    } else
      lua_pop (L, 2); // fun + 1 arg
  }
  lua_pop (L, 3); // filter userdata + 2 tables
  STACK_CHECK_END;
}

static int device_close (lua_State *L);

static void usb_device_removed (void *user_data, io_iterator_t iter)
{
  usb_filter *f = user_data;
  lua_State *L = f->L;
  STACK_CHECK;

  if (!luaLM_push_proxy(L, f)) {
    // the GC already threw away our userdata but did not yet call the __gc metamethod
    while (IOIteratorNext (iter));
    return;
  }

  lua_getfenv (L, -1);
  lua_getfield (L, -1, "devices");

  io_service_t service;
  while ((service = IOIteratorNext (iter))) {
    push_dev_location_str (L, service);
    lua_gettable (L, -2); // find userdata for this device
    usb_device *dev = luaL_checkudata (L, -1, usb_device_mt);
    dev->connected = 0;
    if (dev->i) {
      lua_pushcfunction (L, device_close);
      lua_pushvalue (L, -2);
      lua_call (L, 1, 0);
    }
    lua_getfield (L, -3, "disconnect");
    if(lua_isfunction (L, -1)) {
      // argument: device userdata
      lua_insert (L, -2);
      if (lua_pcall (L, 1, 0, 0))
        luaL_error (L, "%s\n", lua_tostring (L, -1));
    } else
      lua_pop (L, 2); // fun + 1 arg
  }
  lua_pop (L, 3); // filter userdata + 2 tables
  STACK_CHECK_END;
}

static int watch_usb (lua_State *L)
{
  static IONotificationPortRef notification_ioport = NULL;

  if (!notification_ioport) {
    notification_ioport = IONotificationPortCreate (kIOMasterPortDefault);
    CFRunLoopSourceRef _runLoopSource = IONotificationPortGetRunLoopSource(notification_ioport);
    CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], _runLoopSource, kCFRunLoopDefaultMode);
  }

  kern_return_t kr;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  NSMutableDictionary *matching_dict = (NSMutableDictionary *)IOServiceMatching(kIOUSBDeviceClassName);
  if (!matching_dict) {
    fprintf (stderr, SRCLOC
        "register_for_notifications: could not create a IOKit matching dictionary\n");
    exit (3);
  }

  luaL_checktype (L, 1, LUA_TTABLE);
  lua_pushnil (L);
  while (lua_next (L, 1) != 0)
  {
    if (lua_type (L, -2) == LUA_TSTRING) {
      const char *s = lua_tostring (L, -2);
      const NSString *iokit_key = lua_to_iokit_name (s);
      if (iokit_key) {
        NSObject *o = NULL;
        if (lua_type (L, -1) == LUA_TSTRING) {
          o = [NSString stringWithUTF8String:lua_tostring (L, -1)];
        } else if (lua_type (L, -1) == LUA_TNUMBER) {
          o = [NSNumber numberWithDouble:lua_tonumber (L, -1)];
        }
        if (!o) {
          return luaL_error (L,
              "unknown type: %s for USB matching key: %s", luaL_typename (L, -1), s);
        }
        [matching_dict setObject:o forKey:iokit_key];
      } else if (str_diff (s, "connect") &&
                 str_diff (s, "disconnect") &&
                 str_diff (s, "coldplug_end")) {
        return luaL_error (L, "unknown USB matching key: %s", s);
      }
    } else {
      return luaL_error (L, "invalid USB matching table key type: %s", luaL_typename (L, -2));
    }
    lua_pop (L, 1);
  }

  usb_filter *f = luaLM_create_userdata (L, sizeof(usb_filter), usb_filter_mt);

  f->L = luaLM_get_main_state(L);
  lua_pushvalue (L, 1);
  lua_setfenv (L, -2);

  lua_newtable (L);
  lua_setfield (L, 1, "devices");

  kr = IOServiceAddMatchingNotification (notification_ioport,
                                         kIOFirstMatchNotification,
                                         (CFMutableDictionaryRef) [matching_dict retain],
                                         usb_device_added, f,
                                         &f->add_iter);
  if (kr) {
    [pool release];
    return luaLM_mach_error (L, kr, "IOServiceAddMatchingNotification[connect]");
  }
  kr = IOServiceAddMatchingNotification (notification_ioport,
                                         kIOTerminatedNotification,
                                         (CFMutableDictionaryRef) [matching_dict retain],
                                         usb_device_removed, f,
                                         &f->rem_iter);
  if (kr) {
    [pool release];
    return luaLM_mach_error (L, kr, "IOServiceAddMatchingNotification[disconnect]");
  }
  [matching_dict release];

  usb_device_added (f, f->add_iter);
  usb_device_removed (f, f->rem_iter);

  lua_getfield (L, 1, "coldplug_end");
  if (lua_isfunction (L, -1)) {
    lua_pushvalue (L, -2);
    if (lua_pcall (L, 1, 0, 0)) {
      luaL_error (L, "%s\n", lua_tostring (L, -1));
    }
  } else
    lua_pop (L, 1);

  [pool release];

  return 1;
}

static int device_tostring (lua_State *L)
{
  usb_device *dev = check_device (L, 1);

  NSMutableDictionary *props = NULL;
  kern_return_t kr = IORegistryEntryCreateCFProperties (
      dev->ioservice, (CFMutableDictionaryRef *)&props, kCFAllocatorDefault, kNilOptions);
  [props autorelease];
  EXIT_ON_MACH_ERROR (kr, "IORegistryEntryCreateCFProperties");
  NSString *s = [NSString stringWithFormat:
    @"usb_device<%@ / %@ / %@ @ 0x%08x %s>",
	[props objectForKey:@kUSBVendorString],
	[props objectForKey:@kUSBProductString],
	[props objectForKey:@kUSBSerialNumberString],
	[[props objectForKey:@kUSBDevicePropertyLocationID] unsignedIntValue],
	dev->i ? "open" : "closed"];
  lua_pushstring (L, [s UTF8String]);

  return 1;
}

static int device_close (lua_State *L)
{
  kern_return_t kr;
  usb_device *dev = check_opendevice (L, 1);

  // open device
  kr = (*dev->i)->USBDeviceClose (dev->i);
  if (kr && kr != kIOReturnNoDevice && kr != kIOReturnNotAttached)
    return luaLM_mach_error (L, kr, "USBDeviceClose");

  IOObjectRetain (dev->ioservice); // dev->i's Release wil release the service (BUG)
  kr = (*dev->i)->Release (dev->i);
  if (kr) return luaLM_mach_error (L, kr, "Release(device)");

  dev->i = 0;

  return 0;
}

static int device_gc (lua_State *L)
{
  kern_return_t kr;
  usb_device *dev = check_device (L, 1);
  //_D("device gc: %p", dev);

  if (dev->i) device_close(L);

  kr = IOObjectRelease (dev->ioservice);
  EXIT_ON_MACH_ERROR (kr, "IOObjectRelease");

  return 0;
}

static int device_index(lua_State *L)
{
  if (lua_getmetatable(L, 1)) {
    lua_pushvalue(L, 2);
    lua_gettable(L, -2);
    if (!lua_isnil(L, -1)) return 1;
    lua_pop(L, 1);
  }
  usb_device *dev = check_device (L, 1);
  if (lua_type (L, 2) == LUA_TSTRING) {
    const char *s = lua_tostring (L, 2);
    const NSString *iokit_key = lua_to_iokit_name (s);
    if (iokit_key) {
      CFTypeRef prop = IORegistryEntryCreateCFProperty (
          dev->ioservice, (CFStringRef)iokit_key, kCFAllocatorDefault, kNilOptions);
      if (prop) {
        CFTypeID t = CFGetTypeID(prop);
        if (t == CFNumberGetTypeID()) {
          double i;
          if (!CFNumberGetValue (prop, kCFNumberDoubleType, &i)) {
            NSString *s = [[NSString alloc] initWithFormat:@"<invalid CFNumber: %@>", prop];
            lua_pushlstring (L, [s UTF8String], [s length]);
            [s release];
          }
          lua_pushnumber (L, i);
        } else if (t == CFStringGetTypeID()) {
          const NSString *s = prop;
          lua_pushlstring (L, [s UTF8String], [s length]);
        } else {
          NSString *s = [[NSString alloc] initWithFormat:@"<unknown CFTypeRef: %@>", prop];
          lua_pushlstring (L, [s UTF8String], [s length]);
          [s release];
        }
        CFRelease (prop);
        return 1;
      }
    } else if (!str_diff (s, "isopen")) {
      lua_pushboolean (L, dev->i ? 1 : 0);
      return 1;
    }
  }

  return 0;
}

static void *create_and_query_interface (io_service_t service, CFUUIDRef pluginType, CFUUIDRef iid)
{
  kern_return_t kr;
  IOCFPlugInInterface **plugin = NULL;
  SInt32 _score; // unused
  kr = IOCreatePlugInInterfaceForService (service, pluginType, kIOCFPlugInInterfaceID,
      &plugin, &_score);
  EXIT_ON_MACH_ERROR (kr, "IOCreatePlugInInterfaceForService");

  void *interface = NULL;
  HRESULT result = (*plugin)->QueryInterface (plugin, CFUUIDGetUUIDBytes (iid),
                                              (void *)&interface);
  (*plugin)->Release (plugin);
  if (result) {
    fprintf (stderr, "error: QueryInterface: %08x\n", (int) result);
    exit (3);
  }
  return interface;
}

static int device_open (lua_State *L)
{
  kern_return_t kr;
  usb_device *dev = check_device (L, 1);
  if (dev->i) luaL_error (L, "device already open");

  dev->i = create_and_query_interface (dev->ioservice, kIOUSBDeviceUserClientTypeID,
      kIOUSBDeviceInterfaceID187);

  kr = (*dev->i)->USBDeviceOpen (dev->i);
  if (kr) {
    // if the failed object is not released before the next call to USBDeviceOpen
    // we leak a +2 on the kernel retain count (until the process ends) and gain some
    // random USB subsystem crashes
    IOObjectRetain (dev->ioservice); // dev->i's Release will release the service (BUG)
    kern_return_t kr2 = (*dev->i)->Release (dev->i);
    dev->i = 0;
    EXIT_ON_MACH_ERROR(kr2, "Release(open_device)");
  }
  if (kr) return luaLM_mach_error (L, kr, "USBDeviceOpen");

  return 0;
}

static int device_set_configuration (lua_State *L)
{
  kern_return_t kr;
  usb_device *od = check_opendevice (L, 1);
  uint8_t cval = lua_tonumber (L, 2);

  kr = (*od->i)->SetConfiguration (od->i, cval);
  if (kr) return luaLM_mach_error (L, kr, "SetConfiguration");

  lua_pushboolean (L, 1);
  return 1;
}


static int device_interfaces (lua_State *L)
{
  usb_device *od = check_opendevice (L, 1);
  luaL_checktype (L, 2, LUA_TTABLE);

  IOUSBFindInterfaceRequest req = {
    .bInterfaceClass    = luaLM_getnumfield (L,  2,  "bInterfaceClass",    kIOUSBFindInterfaceDontCare),
    .bInterfaceSubClass = luaLM_getnumfield (L,  2,  "bInterfaceSubClass", kIOUSBFindInterfaceDontCare),
    .bInterfaceProtocol = luaLM_getnumfield (L,  2,  "bInterfaceProtocol", kIOUSBFindInterfaceDontCare),
    .bAlternateSetting  = luaLM_getnumfield (L,  2,  "bAlternateSetting",  kIOUSBFindInterfaceDontCare),
  };

  kern_return_t kr;
  io_iterator_t iter;

  kr = (*od->i)->CreateInterfaceIterator(od->i, &req, &iter);
  if (kr) return luaLM_mach_error (L, kr, "CreateInterfaceIterator");

  lua_newtable (L); int i = 1;
  io_service_t service; usb_interface *intf;
  while ((service = IOIteratorNext(iter))) {
    intf = luaLM_create_userdata (L, sizeof (usb_interface), usb_interface_mt);
    intf->ioservice = service;
    IOObjectRetain (service);
    lua_rawseti (L, -2, i);
    i++;
  }

  IOObjectRelease (iter);

  return 1;
}

static int device_reset (lua_State *L)
{
  usb_device *od = check_opendevice (L, 1);

  kern_return_t kr;

  kr = (*od->i)->ResetDevice(od->i);
  if (kr) return luaLM_mach_error (L, kr, "ResetDevice");

  return 1;
}

static int device_reenumerate (lua_State *L)
{
  usb_device *od = check_opendevice (L, 1);

  kern_return_t kr;

  kr = (*od->i)->USBDeviceReEnumerate(od->i, 0);
  if (kr) return luaLM_mach_error (L, kr, "USBDeviceReEnumerate");

  return 1;
}

static int interface_close (lua_State *L)
{
  kern_return_t kr;
  usb_interface *i = check_openinterface (L, 1);

  kr = (*i->i)->USBInterfaceClose (i->i);
  if (kr && kr != kIOReturnNoDevice)
    return luaLM_mach_error (L, kr, "USBInterfaceClose");

  CFRunLoopSourceInvalidate (i->source);
  CFRelease (i->source);

  i->source = 0;

  kr = (*i->i)->Release (i->i);
  if (kr) return luaLM_mach_error (L, kr, "Release(interface)");

  i->i = 0;

  return 0;
}

static int interface_gc (lua_State *L)
{
  kern_return_t kr;
  volatile usb_interface *i = check_interface (L, 1);
  //_D("interface gc: %p", i);

  if (i->i) interface_close (L);

  kr = IOObjectRelease (i->ioservice);
  EXIT_ON_MACH_ERROR (kr, "IOObjectRelease");

  return 0;
}

static int interface_index (lua_State *L)
{
  if (lua_getmetatable(L, 1)) {
    lua_pushvalue(L, 2);
    lua_gettable(L, -2);
    if (!lua_isnil(L, -1)) return 1;
    lua_pop(L, 1);
  }
  usb_interface *intf = check_interface (L, 1);
  if (lua_type (L, 2) == LUA_TSTRING) {
    const char *s = lua_tostring (L, 2);
    if (!str_diff (s, "isopen")) {
      lua_pushboolean (L, intf->i ? 1 : 0);
      return 1;
    }
  }

  return 0;
}

static int interface_tostring (lua_State *L)
{
  usb_interface *intf = check_interface (L, 1);

  NSMutableDictionary *props = NULL;
  kern_return_t kr = IORegistryEntryCreateCFProperties (
      intf->ioservice, (CFMutableDictionaryRef *)&props, kCFAllocatorDefault, kNilOptions);
  [props autorelease];
  if (kr == 0x10000003) { // (ipc/send) invalid destination port
	// we get this error when the device gets disconnected
	if (intf->i) {
	  // close the interface if it was open
	  lua_pushcfunction (L, interface_close);
	  lua_pushvalue (L, 1);
	  lua_call (L, 1, 0);
	}
	lua_pushstring (L, "usb_interface<missing in action>");
	return 1;
  }
  EXIT_ON_MACH_ERROR (kr, "IORegistryEntryCreateCFProperties");
  NSString *s = [NSString stringWithFormat:
    @"usb_interface<%d %s %x:%x:%x>",
    [[props objectForKey:@kUSBInterfaceNumber] intValue],
    intf->i ? "open" : "closed",
    [[props objectForKey:@kUSBInterfaceClass] intValue],
    [[props objectForKey:@kUSBInterfaceSubClass] intValue],
    [[props objectForKey:@kUSBInterfaceProtocol] intValue]];
  lua_pushstring (L, [s UTF8String]);

  return 1;
}

static int interface_open (lua_State *L)
{
  kern_return_t kr;
  usb_interface *intf = check_interface (L, 1);
  if (intf->i) luaL_error (L, "interface already open");

  intf->i = create_and_query_interface (intf->ioservice, kIOUSBInterfaceUserClientTypeID,
      kIOUSBInterfaceInterfaceID190);

  kr = (*intf->i)->CreateInterfaceAsyncEventSource (intf->i, &intf->source);
  EXIT_ON_MACH_ERROR (kr, "CreateDeviceAsyncEventSource");
  CFRunLoopAddSource(
      [[NSRunLoop currentRunLoop] getCFRunLoop], intf->source, kCFRunLoopDefaultMode);

  kr = (*intf->i)->USBInterfaceOpen (intf->i);
  if (kr) {
    kern_return_t kr2 = (*intf->i)->Release (intf->i);
    intf->i = 0;
    EXIT_ON_MACH_ERROR(kr2, "Release(open_interface)");
  }
  if (kr) return luaLM_mach_error (L, kr, "USBInterfaceOpen");

  return 1;
}

static usb_pipe *create_pipe (lua_State *L, int oi_index, usb_interface *oi, int idx,
                 uint8_t dir, uint8_t number, uint8_t type, uint16_t size, uint8_t interval)
{
  oi_index = abs_index (L, oi_index);

  usb_pipe *p = luaLM_create_userdata (L, sizeof(usb_pipe), usb_pipe_mt);
  p->i = oi; p->idx = idx;
  p->dir = dir; p->number = number; p->type = type; p->size = size; p->interval = interval;

  lua_newtable (L);
  lua_pushvalue (L, oi_index);
  lua_setfield (L, -2, "interface");
  lua_setfenv (L, -2);

  return p;
}

static int pipe_tostring (lua_State *L)
{
  usb_pipe *p = check_pipe (L, 1);

  const char *type = "N/A", *dir = "N/A";
  if      (p->dir  == kUSBIn) dir = "in";
  else if (p->dir  == kUSBOut) dir = "out";
  else if (p->dir  == kUSBAnyDirn) dir = "in/out";
  if      (p->type == kUSBControl) type = "control";
  else if (p->type == kUSBIsoc) type = "isoc";
  else if (p->type == kUSBBulk) type = "bulk";
  else if (p->type == kUSBInterrupt) type = "interrupt";
  NSString *s = [[NSString alloc] initWithFormat:
    @"usb_pipe<%d: %s %s 0x%02x (%d bytes, %d ms)>",
    p->idx, type, dir, p->number | (p->dir == kUSBIn ? 0x80 : 0), p->size, p->interval];
  lua_pushstring (L, [s UTF8String]);
  [s release];
  return 1;
}

static int interface_get_pipe (lua_State *L)
{
  kern_return_t kr;
  usb_interface *oi = check_openinterface (L, 1);
  luaL_checktype (L, 2, LUA_TNUMBER);
  uint8_t enumber = lua_tonumber (L, 2);

  uint8_t edir;
  if (lua_isnoneornil (L, 3)) {
    edir = enumber & 0x80 ? kUSBIn : kUSBOut;
    enumber &= ~0x80;
  } else {
    luaL_checktype (L, 3, LUA_TSTRING);
    const char *s = lua_tostring (L, 3);
    if (!str_idiff (s, "in")) edir = kUSBIn;
    else if (!str_idiff (s, "out")) edir = kUSBOut;
    else luaL_error (L, "invalid USB direction: %s", s);
  }

  uint8_t max;
  kr = (*oi->i)->GetNumEndpoints (oi->i, &max);
  if (kr) return luaLM_mach_error (L, kr, "GetNumEndpoints");
  // the default control endpoint is at p = 0
  for (int p = 1; p <= max; p++) {
    uint8_t dir, number, type, interval;
    uint16_t size;
    kr = (*oi->i)->GetPipeProperties (oi->i, p, &dir, &number, &type, &size, &interval);
    if (kr) return luaLM_mach_error (L, kr, "GetPipeProperties");
    if (dir == edir && number == enumber) {
      create_pipe (L, 1, oi, p, dir, number, type, size, interval);
      return 1;
    }
  }

  return 0;
}

static int interface_find_pipes (lua_State *L)
{
  kern_return_t kr;
  usb_interface *oi = check_openinterface (L, 1);
  luaL_checktype (L, 2, LUA_TTABLE);

  int i;

  uint8_t edir = kUSBAnyDirn;
  uint8_t etype = kUSBAnyType;
  uint8_t enumber = 0;

  i = 1;
  while (1) {
    lua_rawgeti (L, 2, i); i++;
    if (lua_isnil (L, -1)) break;
    if (lua_type (L, -1) == LUA_TSTRING) {
      const char *s = lua_tostring (L, -1);
      if (!strcmp (s, "in")) edir = kUSBIn;
      else if (!strcmp (s, "out")) edir = kUSBOut;
      else if (!strcmp (s, "control")) etype = kUSBControl;
      else if (!strcmp (s, "isoc")) etype = kUSBIsoc;
      else if (!strcmp (s, "bulk")) etype = kUSBBulk;
      else if (!strcmp (s, "interrupt")) etype = kUSBInterrupt;
      else luaL_error (L, "invalid pipe search term: %s", s);
    } else if (lua_type (L, -1) == LUA_TNUMBER) {
      enumber = lua_tonumber (L, -1);
    } else {
      luaL_error (L, "invalid pipe search term type: %s", luaL_typename (L, -1));
    }
    lua_pop (L, 1);
  }
  lua_pop (L, 1);

  uint8_t max;
  kr = (*oi->i)->GetNumEndpoints (oi->i, &max);
  if (kr) return luaLM_mach_error (L, kr, "GetNumEndpoints");
  // the default control endpoint is at p = 0
  lua_newtable (L);
  i = 1;
  for (int p = 1; p <= max; p++) {
    uint8_t dir, number, type, interval;
    uint16_t size;
    kr = (*oi->i)->GetPipeProperties (oi->i, p, &dir, &number, &type, &size, &interval);
    if (kr) return luaLM_mach_error (L, kr, "GetPipeProperties");
    if (edir    != kUSBAnyDirn && dir    != edir) continue;
    if (etype   != kUSBAnyType && type   != etype) continue;
    if (enumber != 0           && number != enumber) continue;
    create_pipe (L, 1, oi, p, dir, number, type, size, interval);
    lua_rawseti (L, -2, i); i++;
  }

  return 1;
}

typedef struct pipe_read_ctx {
  lua_State *L;
  char *s;
  usb_pipe *p;
} pipe_read_ctx;

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

static void pipe_read_callback (void *refcon, IOReturn result, void *arg0)
{
  pipe_read_ctx *ctx = refcon;
  lua_State *L = ctx->L;
  size_t n = (size_t)arg0;
  STACK_CHECK;

  if (!luaLM_push_strong_proxy(L, ctx)) {
    eprintf ("cannot retrieve the strong Lua proxy for a pipe read context: %p\n", ctx);
    goto cleanup;
  }

  lua_getfenv (L, -1);
  lua_pushcfunction(L, traceback);
  lua_pushlightuserdata (L, ctx);
  lua_rawget (L, -3);
  lua_pushlightuserdata (L, ctx);
  lua_pushnil (L);
  lua_rawset (L, -5);
  if (result == kIOReturnSuccess) {
    lua_pushlstring (L, ctx->s, n);
    if (lua_pcall (L, 1, 0, -3)) {
      eprintf ("pipe read callback error: %s\n", lua_tostring (L, -1));
      lua_pop (L, 1);
    }
  } else {
    const char *s = mach_error_string (result);
    lua_pushnil (L);
    lua_pushstring (L, s); // message
    lua_pushboolean (L, (unsigned)result != 0xe00002ed && (unsigned)result != 0xe00002eb); // fatal?
    lua_pushnumber (L, (unsigned)result); // errno
    if (lua_pcall (L, 4, 0, -6)) {
      eprintf ("pipe read callback error: %s\n", lua_tostring (L, -1));
      lua_pop (L, 1);
    }
  }
  lua_pop (L, 2); // pipe environment and async read callback
  luaLM_unregister_strong_proxy (L, ctx);
cleanup:
  lua_pop (L, 1); // pipe userdata
  free (ctx->s);
  free (ctx);
  STACK_CHECK_END;
}

static int pipe_read (lua_State *L)
{
  // async
  kern_return_t kr;
  usb_pipe *p = check_pipe (L, 1);
  if (!lua_isnumber (L, 2)) {
    lua_pushnumber (L, 1024);
    lua_insert (L, 2);
  }
  lua_Number n = luaL_checknumber (L, 2);
  luaL_checktype (L, 3, LUA_TFUNCTION);

  pipe_read_ctx *ctx = malloc (sizeof (pipe_read_ctx));
  if (!ctx) return luaL_error (L, "failed to allocate the asynchronous read context");

  ctx->L = luaLM_get_main_state (L);
  ctx->p = p;
  ctx->s = malloc (n);
  if (!ctx->s) { free(ctx); return luaL_error (L, "failed to allocate the read buffer"); }
  lua_getfenv (L, 1);
  lua_pushlightuserdata (L, ctx);
  lua_pushvalue (L, 3);
  lua_rawset (L, -3);
  lua_pop (L, 1);
  luaLM_register_strong_proxy (L, ctx, 1);
  kr = (*p->i->i)->ReadPipeAsync (p->i->i, p->idx, ctx->s, n, pipe_read_callback, ctx);
  if (kr) {
    free (ctx->s); free(ctx);
    const char *s = mach_error_string (kr);
    lua_pushnil (L);
    lua_pushstring (L, s); // message
    lua_pushboolean (L, (unsigned)kr != 0xe00002ed && (unsigned)kr != 0xe00002eb); // fatal?
    lua_pushnumber (L, (unsigned)kr); // errno
    return 4;
    // luaLM_mach_error (L, kr, "ReadPipeAsync");
  }
  lua_pushboolean(L, 1);
  return 1;
}

static int pipe_write (lua_State *L)
{
  // FIXME: force full async operation with yielding on the Lua side
  kern_return_t kr;
  usb_pipe *p = check_pipe (L, 1);
  size_t n = 0;
  const char *s = luaL_checklstring (L, 2, &n);

  kr = (*p->i->i)->WritePipe (p->i->i, p->idx, (void *)s, n);
  if (kr) {
    const char *s = mach_error_string (kr);
    lua_pushnil (L);
    lua_pushstring (L, s); // message
    lua_pushboolean (L, (unsigned)kr != 0xe00002ed && (unsigned)kr != 0xe00002eb); // fatal?
    lua_pushnumber (L, (unsigned)kr); // errno
    return 4;
    // luaLM_mach_error (L, kr, "WritePipe");
  }
  lua_pushboolean(L, 1);
  return 1;
}

static int pipe_reset (lua_State *L)
{
  kern_return_t kr;
  usb_pipe *p = check_pipe (L, 1);

  kr = (*p->i->i)->ClearPipeStallBothEnds (p->i->i, p->idx);
  if (kr) return luaLM_mach_error (L, kr, "ClearPipeStallBothEnds");
  return 0;
}

static const struct luaL_reg funcs[] = {
  {"watch_usb",  watch_usb },
  {NULL,         NULL      },
};

static const struct luaL_reg filter_methods[] =  {
  {"__gc",        filter_gc       },
  {"__index",     filter_index    },
  {"__tostring",  filter_tostring },
  {"close",       filter_gc       },
  {NULL,          NULL            },
};

static const struct luaL_reg device_methods[] = {
  {"__gc",               device_gc                },
  {"__index",            device_index             },
  {"__tostring",         device_tostring          },
  {"open",               device_open              },
  {"close",              device_close             },
  {"set_configuration",  device_set_configuration },
  {"list_interfaces",    device_interfaces        },
  {"reset",              device_reset             },
  {"reenumerate",        device_reenumerate       },
  {NULL,                 NULL                     },
};

static const struct luaL_reg interface_methods[] = {
  {"__gc",        interface_gc         },
  {"__index",     interface_index      },
  {"__tostring",  interface_tostring   },
  {"open",        interface_open       },
  {"close",       interface_close      },
  {"get_pipe",    interface_get_pipe   },
  {"find_pipes",  interface_find_pipes },
  {NULL,          NULL                 },
};

static const struct luaL_reg pipe_methods[] = {
  {"__tostring",  pipe_tostring },
  {"read",        pipe_read     },
  {"write",       pipe_write    },
  {"reset",       pipe_reset    },
  {NULL,          NULL          },
};

int luaopen_usb (lua_State *L)
{
  luaLM_register_metatable (L, usb_filter_mt, filter_methods);
  luaLM_register_metatable (L, usb_device_mt, device_methods);
  luaLM_register_metatable (L, usb_interface_mt, interface_methods);
  luaLM_register_metatable (L, usb_pipe_mt, pipe_methods);

  lua_newtable (L);
  luaL_register (L, NULL, funcs);
  return 1;
}
