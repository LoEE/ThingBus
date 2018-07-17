// Copyright (c) 2008-2010 Bjoern Hoehrmann <bjoern@hoehrmann.de>
// See http://bjoern.hoehrmann.de/utf-8/decoder/dfa/ for details.
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>

#include <lua.h>
#include <lauxlib.h>

#include <codepoint_width.h>

#include "debug.h"

#define UTF8_ACCEPT 0
#define UTF8_REJECT 12

static const uint8_t utf8d[] = {
  // The first part of the table maps bytes to character classes that
  // to reduce the size of the transition table and create bitmasks.
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,  9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
   7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
   8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
  10,3,3,3,3,3,3,3,3,3,3,3,3,4,3,3, 11,6,6,6,5,8,8,8,8,8,8,8,8,8,8,8,

  // The second part is a transition table that maps a combination
  // of a state of the automaton and a character class to a state.
   0,12,24,36,60,96,84,12,12,12,48,72, 12,12,12,12,12,12,12,12,12,12,12,12,
  12, 0,12,12,12,12,12, 0,12, 0,12,12, 12,24,12,12,12,12,12,24,12,24,12,12,
  12,12,12,12,12,12,12,24,12,12,12,12, 12,24,12,12,12,12,12,12,12,24,12,12,
  12,12,12,12,12,12,12,36,12,36,12,12, 12,36,12,12,12,12,12,36,12,36,12,12,
  12,36,12,12,12,12,12,12,12,12,12,12,
};

static inline uint32_t
decode(uint32_t* state, uint32_t* codep, unsigned char byte)
{
  uint32_t type = byte <= 0x7f ? 0 : utf8d[byte - 0x80];

  *codep = (*state != UTF8_ACCEPT) ?
    (byte & 0x3fu) | (*codep << 6) :
    (0xff >> type) & (byte);

  *state = utf8d[128 + *state + type];

  return *state;
}

int lua_codepoint_widths(lua_State *L)
{
  size_t n;
  const char *str = luaL_checklstring (L, 1, &n);
  const char *in = str;
  char *screenwidths = malloc(n+1);
  if(!screenwidths) return luaL_error (L, "cannot allocate memory");
  char *bytewidths = malloc(n+1);
  if(!bytewidths) return luaL_error (L, "cannot allocate memory");

  char *sout = screenwidths;
  char *bout = bytewidths;
  uint32_t codepoint;
  uint32_t state = 0;
  const char *previn = in;
  while (*in) {
    if (decode(&state, &codepoint, *in++) == 0) {
      int w = codepoint_width(codepoint);
      if (w == codepoint_nonprint || w == codepoint_combining) w = 0;
      else if (w == codepoint_widened_in_9) w = 2;
      else if (w < 0) w = 1;
      *sout++ = w;
      *bout++ = in - previn;
      previn = in;
    } else if (state == UTF8_REJECT) {
      return luaL_error (L, "invalid UTF-8 bytes encountered");
    }
  }
  lua_pushlstring(L, screenwidths, sout - screenwidths);
  lua_pushlstring(L, bytewidths, bout - bytewidths);
  return 2;
}

static const struct luaL_reg functions[] = {
  {"codepoint_widths", lua_codepoint_widths },
  { NULL,              NULL                 },
};

int luaopen_unicode (lua_State *L)
{
  luaL_register (L, "unicode", functions);
  return 1;
}
