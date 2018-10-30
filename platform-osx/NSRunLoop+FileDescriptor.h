#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSRunLoop.h>

@interface NSRunLoop (FileDescriptor)
  - (void) addReadCallback:(CFSocketCallBack)callback 
               withContext:(void *)ctx 
         forFileDescriptor:(int)fd 
                   andMode:(NSString *)mode;
@end
