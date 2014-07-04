#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#include "byte.h"
#include "debug.h"
#include "buffer.h"

/* untested
void byte_copyr (void *d, size_t n, const void *s)
{
  char *d = d + n, *s = s + n;
  while (n--) *--d = *--s;
}
*/

static buflen_t good_size (buflen_t size)
{
  buflen_t newsize = 16;
  while (newsize < size) newsize <<= 1;
  return newsize;
}

int buffer_ensure (struct buffer *b, buflen_t space)
{
  if (b->data) {
    buflen_t free = b->size - b->end;
    if (free >= space) { return 1; }
    free += b->start;
    if (free >= space) {
      byte_copy (b->data, b->end - b->start, b->data + b->start);
      b->end -= b->start; b->start = 0;
      return 1;
    }
  }
  buflen_t nsize = good_size (b->end - b->start + space);
  uint8_t *ndata = malloc (nsize);
  if (!ndata) return 0;
  byte_copy (ndata, b->end - b->start, b->data + b->start);
  if (b->data) free (b->data);
  b->data = ndata;
  b->size = nsize;
  b->end -= b->start; b->start = 0;
  return 1;
}

buflen_t buffer_rpeek (struct buffer *b, const uint8_t **s)
{
  *s = b->data + b->start;
  return b->end - b->start;
}

void buffer_rseek (struct buffer *b, buflen_t n)
{
  b->start += n;
}

buflen_t buffer_wpeek (struct buffer *b, uint8_t **s)
{
  *s = b->data + b->end;
  return b->size - b->end;
}

void buffer_wseek (struct buffer *b, buflen_t n)
{
  b->end += n;
}

int buffer_write (struct buffer *b, const void *s, buflen_t len)
{
  if (!buffer_ensure (b, len)) return 0;
  uint8_t *d;
  buffer_wpeek (b, &d);
  byte_copy (d, len, s);
  buffer_wseek (b, len);
  return 1;
}
