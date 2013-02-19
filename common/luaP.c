///
/// This file contains procedures for managing userdata garbage collection in Lua code.
///
// Copyright (c) 2008-2011 Jakub Piotr Cłapa
// The contents of this file are released under the new BSD license.
#include <lua.h>

#define abs_index(L, i)                    \
    ((i) > 0 || (i) <= LUA_REGISTRYINDEX ? \
     (i) : lua_gettop(L) + (i) + 1)

void luaP_create_proxy_table (lua_State *L, void *key, const char *mode)
{
  lua_pushlightuserdata (L, key);
  lua_newtable (L);
  if (mode) {
    lua_createtable (L, 0, 1);
    lua_pushstring (L, mode);
    lua_setfield (L, -2, "__mode");
    lua_setmetatable (L, -2);
  }
  lua_rawset (L, LUA_REGISTRYINDEX);
}

void luaP_register_link (lua_State *L, void *key, int k, int v)
{
  k = abs_index (L, k);
  v = abs_index (L, v);

  lua_pushlightuserdata (L, key);
  lua_rawget (L, LUA_REGISTRYINDEX);
  
  lua_pushvalue (L, k);
  lua_pushvalue (L, v);
  lua_rawset (L, -3);
  lua_pop (L, 1);
}

void luaP_unregister_link (lua_State *L, void *key, int k)
{
  k = abs_index (L, k);
  lua_pushnil (L);
  luaP_register_link (L, key, k, -1);
  lua_pop (L, 1);
}

int luaP_push_link (lua_State *L, void *key, int k)
{
  k = abs_index (L, k);

  lua_pushlightuserdata (L, key);
  lua_rawget (L, LUA_REGISTRYINDEX);

  lua_pushvalue (L, k);
  lua_rawget (L, -2);

  lua_remove (L, -2);
  if (lua_type (L, -1) == LUA_TNIL) {
    lua_pop (L, 1);
    return 0;
  } else {
    return 1;
  }
}

void luaP_register_proxy (lua_State *L, void *key, void *o, int i)
{
  i = abs_index (L, i);
  lua_pushlightuserdata (L, o);
  luaP_register_link (L, key, -1, i);
}

void luaP_unregister_proxy (lua_State *L, void *key, void *o)
{
  lua_pushnil (L);
  luaP_register_proxy (L, key, o, -1);
  lua_pop (L, 1);
}

int luaP_push_proxy (lua_State *L, void *key, void *o)
{
  lua_pushlightuserdata (L, key);
  lua_rawget (L, LUA_REGISTRYINDEX);

  int reg_i = lua_gettop (L);

  lua_pushlightuserdata (L, o);
  lua_rawget (L, reg_i);

  lua_remove (L, reg_i);
  if (lua_type (L, -1) == LUA_TNIL) {
    lua_pop (L, 1);
    return 0;
  } else {
    return 1;
  }
}
