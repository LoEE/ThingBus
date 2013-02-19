#ifndef LM_H
#define LM_H

#ifdef __MACH__
#include "mach/mach.h"
int luaLM_mach_error (lua_State *L, kern_return_t kr, const char *msg);
#endif
int luaLM_posix_error (lua_State *L, const char *msg);

#define abs_index(L, i)                    \
    ((i) > 0 || (i) <= LUA_REGISTRYINDEX ? \
     (i) : lua_gettop(L) + (i) + 1)

lua_Number luaLM_getnumfield (lua_State *L, int index, char *k, lua_Number d);
void luaLM_register_metatable (lua_State *L, const char *name, const struct luaL_reg *methods);
void luaLM_loadlib (lua_State *L, lua_CFunction fun);
void luaLM_preload (lua_State *L, const struct luaL_reg *mods);
void luaLM_dump_stack (lua_State *L);
int luaLM_getfd (lua_State *L, int i);
int luaLM_checkfd (lua_State *L, int i);

void luaLM_create_proxy_table(lua_State *L);
void luaLM_register_proxy(lua_State *L, void *o, int i);
void luaLM_register_strong_proxy(lua_State *L, void *o, int i);
void luaLM_unregister_strong_proxy (lua_State *L, void *o);
int luaLM_push_main_thread (lua_State *L);
lua_State *luaLM_get_main_state (lua_State *L);
int luaLM_push_proxy(lua_State *L, void *o);
int luaLM_push_strong_proxy(lua_State *L, void *o);
void *luaLM_create_userdata(lua_State *L, size_t n, const char *mt);

#endif
