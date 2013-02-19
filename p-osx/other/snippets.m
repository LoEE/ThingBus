void io_service_dump_properties (char *msg, io_service_t ioservice)
{
  NSMutableDictionary *props = NULL;
  kern_return_t kr = IORegistryEntryCreateCFProperties (ioservice, (CFMutableDictionaryRef *)&props, kCFAllocatorDefault, kNilOptions);
  EXIT_ON_MACH_ERROR ("IORegistryEntryCreateCFProperties", kr, KERN_SUCCESS);
  NSLog (@"%s: %@\n", msg, [props description]);
  [props release];
}




#include "debug.h"

static void printhex (const void *_s, size_t n)
{
  const uint8_t *x = _s;
  while (n >= 2) {
    n -= 2;
    eprintf ("%02x%02x%s", *x, *(x+1), n ? " " : "");
    x+= 2;
  }
  if (n) eprintf ("%02x", *x++);
  eprintf ("\n");
}
