#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>

#include "byte.h"

void byte_copy (void *_d, size_t n, const void *_s)
{
  uint8_t *d = _d;
  const uint8_t *s = _s;
  while (n--) *d++ = *s++;
}

size_t byte_findc (const void *_s, size_t sn, uint8_t c)
{
  const uint8_t *s = _s;
  size_t i = 0;
  while (sn-- && *s++ != c) i++;
  return i;
}

int byte_diff (const void *_s, size_t sn, const void *_x)
{
  const uint8_t *s = _s, *x = _x;
  while (sn && *s == *x) { sn--; s++; x++; }
  if (sn) return *s - *x;
  return 0;
}

size_t byte_find (const void *_s, size_t sn, const void *tok, size_t tokn)
{
  const uint8_t *s = _s;
  size_t osn = sn;
  while (sn >= tokn) {
    if (!byte_diff (s, tokn, tok)) return osn - sn;
    s++; sn--;
  }
  return osn;
}

void *byte_dup (const void *s, size_t n)
{
  void *d = malloc(n);
  if (d) byte_copy(d, n, s);
  return d;
}
