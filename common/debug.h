///
/// This file contains macros for error handling and printing debugging information.
/// 

/// Macro expanding to the current source file name and line number.
#define __TOSTRING(x) #x
#define _TOSTRING(x) __TOSTRING(x)
#define SRCLOC __FILE__ ":" _TOSTRING(__LINE__) ":"

/// These macros check for errors from syscalls.
#define EXIT_ON_MACH_ERROR(retval, msg) \
  if (retval != 0) { mach_error (SRCLOC msg ":", retval); exit (3); }

#define WARN_ON_MACH_ERROR(retval, msg) \
  if (retval != 0) { mach_error (SRCLOC msg ":", retval); }

#define EXIT_ON_POSIX_ERROR(msg, code) \
  do { perror (msg); exit (code); } while (0)
#define EXIT_ON_ERROR(msg, code) \
  do { eprintf (msg); exit (code); } while (0)

/// A printf that outputs to stderr.
#define eprintf(fmt, ...) ({ fprintf (stderr, fmt , ##__VA_ARGS__); fflush (stderr); })
#define _D(fmt, ...) eprintf (SRCLOC "[%s] " fmt "\n" , __FUNCTION__, ##__VA_ARGS__)

/// A macro for quickly dumping the Lua stack contents.
#define _SD ({ eprintf(SRCLOC " stack: "); luaLM_dump_stack(L); });

/// A macro for checking the retain counts of IOKit objects.
#define IR(o) ({eprintf(SRCLOC " retain: %d / %d\n", IOObjectGetUserRetainCount(o), IOObjectGetRetainCount(o) );});

#define STACK_CHECK int __stack_level = abs_index (L, 0); luaL_checkstack (L, LUA_MINSTACK, SRCLOC "cannot allocate stack space")
#define STACK_CHECK_END do { int i = abs_index (L, 0) - __stack_level; if (i != 0) { eprintf (SRCLOC "detected stack unbalance (%d elements)\n", i); _SD } } while (0)

#ifdef _WIN32
#include <windows.h>

__attribute__((__unused__)) static char *win32_strerror (DWORD err)
{
  char *s;

  if (FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER |
                     FORMAT_MESSAGE_FROM_SYSTEM,
                     NULL, err, 0, (LPSTR)&s, 0,
                     NULL)) {
    char *str = strdup(s);
    LocalFree(s);
    return str;
  } else {
    return "formatting error";
  }
}

__attribute__((__unused__)) static int win32_perror (char *msg)
{
  char *s;
  unsigned long err = GetLastError ();

  if (FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER |
                     FORMAT_MESSAGE_FROM_SYSTEM,
                     NULL, err, 0, (LPSTR)&s, 0,
                     NULL)) {
    eprintf ("%s: %ld: %s", msg, err, s);
    LocalFree (s);
    return 0;
  } else {
    eprintf ("%s: %ld: %s", msg, err, "formatting error");
    return 1;
  }
}

#define __TOSTR(X) #X
#define _TOSTR(X) __TOSTR(X)
#define FAIL_ON(cond, msg) if(cond) { win32_perror (SRCLOC msg); exit (2); }
#define WARN_ON(cond, msg) if(cond) { win32_perror (SRCLOC msg); }
#endif

