#ifndef LUAP_H
#define LUAP_H

void luaP_create_proxy_table (lua_State *L, void *key, const char *mode);
void luaP_register_link (lua_State *L, void *key, int k, int v);
void luaP_unregister_link (lua_State *L, void *key, int k);
int luaP_push_link (lua_State *L, void *key, int k);
void luaP_register_proxy (lua_State *L, void *key, void *o, int i);
void luaP_unregister_proxy (lua_State *L, void *key, void *o);
int luaP_push_proxy (lua_State *L, void *key, void *o);

#endif
