#include "str.h"

char chr_lower (char c)
{
  unsigned char x = c - 'A';
  if (x <= 'Z' - 'A') return x + 'a';
  return c;
}

char chr_upper (char c)
{
  unsigned char x = c - 'a';
  if (x <= 'z' - 'a') return x + 'A';
  return c;
}

int str_idiff (const char *s, const char *t)
{
  char x, y;

  while (1) {
    x = chr_lower(*s); y = chr_lower(*t); if (x != y) break; if (!x) break; s++; t++;
    x = chr_lower(*s); y = chr_lower(*t); if (x != y) break; if (!x) break; s++; t++;
    x = chr_lower(*s); y = chr_lower(*t); if (x != y) break; if (!x) break; s++; t++;
    x = chr_lower(*s); y = chr_lower(*t); if (x != y) break; if (!x) break; s++; t++;
  }
  return (int)x - (int)y;
}

int str_diff (const char *s, const char *t)
{
  char x, y;

  while (1) {
    x = *s; y = *t; if (x != y) break; if (!x) break; s++; t++;
    x = *s; y = *t; if (x != y) break; if (!x) break; s++; t++;
    x = *s; y = *t; if (x != y) break; if (!x) break; s++; t++;
    x = *s; y = *t; if (x != y) break; if (!x) break; s++; t++;
  }
  return (int)x - (int)y;
}
