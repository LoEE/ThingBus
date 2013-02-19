#import "NSRunLoop+FileDescriptor.h"

@implementation NSRunLoop (FileDescriptor)

/// This method registers the  `callback` C function to be called by the  NSRunLoop when the `fd`
/// file descriptor  is readable. The  functions is registered  to run when  the loop is  in mode
/// `mode`. See Apple documentation for `CFSocketCallBack` for the actual callback arguments.
- (void) addReadCallback:(CFSocketCallBack)callback 
             withContext:(void *)ctx 
       forFileDescriptor:(int)fd
                 andMode:(NSString *)mode;
{
  CFSocketContext sock_ctx = { 0, ctx, 0, 0, 0 };
  CFSocketRef sock = CFSocketCreateWithNative(NULL, fd, kCFSocketReadCallBack, callback, &sock_ctx);
  if(!sock) { NSLog (@"CFSocketCreateWithNative failed\n"); exit (2); }
  CFRunLoopSourceRef source = CFSocketCreateRunLoopSource (NULL, sock, 0);
  if(!source) { NSLog (@"CFSocketCreateRunLoopSource failed\n"); exit (2); }
  CFRunLoopAddSource ([self getCFRunLoop], source, (CFStringRef)mode);
  CFRelease (sock);
  CFRelease (source);
}

@end
