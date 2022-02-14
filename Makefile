# Copyright (c) 2008-2018 Jakub Piotr Cłapa
# This program is released under the new BSD license.
#
# Tool definitions

ARCH   = none
BASEARCH = $(subst -jit,,$(ARCH))
ifeq ($(findstring -jit,$(ARCH)),)
	LUA_LDFLAGS = -llua
	PUC_LUA=1
else
	LUA_LDFLAGS = -lluajit-5.1
	LUAJIT=1
endif
export BASEARCH LUA_LDFLAGS
STRIP  = toolchains/$(BASEARCH)/strip
PAGER ?= less
DATE  := $(shell date +%Y.%m.%d)

# Source files
CSRCS  = main.c l_init.c $(wildcard toolchains/$(BASEARCH)/*.c) $(wildcard toolchains/$(BASEARCH)/*.m)
CSRCS += $(addprefix common/,LM.c luaP.c l_additions.c l_preloads.c)
ifeq ($(findstring -jit,$(ARCH)),)
	CSRCS += common/compat-5_2.c
endif
CSRCS += $(addprefix common/,l_buffer.c buffer.c l_binary.c str.c byte.c l_crc.c l_xtea.c l_sha.c lbitlib.c l_miniz.c)
CSRCS += $(addprefix common/,l_unicode.c)
ifneq ($(ARCH),none)
-include .Makefile.$(ARCH)
endif

INSTALLED_FILES += testy.lua lotest.lua
ifneq ($(ARCH),win32)
INSTALLED_FILES += raw-usb.lua
endif

OBJS   = $(join $(dir $(CSRCS)), $(addprefix .,$(addsuffix .$(ARCH).o,$(notdir $(basename $(CSRCS))))))
EXE    = thb
INST   = install/$(ARCH)
PKG    = thb-$(ARCH)-$(DATE)

PLATFORMS = $(subst toolchains/,,$(wildcard toolchains/*))
PLATFORMS := $(PLATFORMS) $(addsuffix -jit,$(PLATFORMS))
INSTALLS = $(addprefix install/,$(PLATFORMS))
PKGS = $(addprefix pkg/,$(PLATFORMS))

.PHONY: default all docs clean nuke $(PLATFORMS) install $(INSTALLS)
.PRECIOUS: %-$(ARCH)$(EXE_SUFFIX)

default:
	@echo "Please choose a platform:"
	@echo "   $(PLATFORMS)"

$(PLATFORMS):
	make ARCH=$@ all

$(INSTALLS):
	make ARCH=$(subst install/,,$@) install

$(PKGS):
	make ARCH=$(subst pkg/,,$@) pkg


all: $(EXE)-$(ARCH)-stripped$(EXE_SUFFIX)

install: all .errno.$(BASEARCH).lua
	@echo »»» installing $(ARCH) to $(INST)
	rm -rf $(INST)
	mkdir -p $(INST)/lualib
	rsync -t $(EXE)-$(ARCH)-stripped$(EXE_SUFFIX) $(INST)/thb$(EXE_SUFFIX)
	$(if $(INSTALLED_FILES),rsync -t $(INSTALLED_FILES) $(INST)/)
	rsync -rt lualib/*.lua lualib/http $(INST)/lualib
	rsync -rtL lualib/$(PLATFORM_STRING) $(INST)/lualib
	$(if $(LUAJIT),rsync -rt toolchains/$(BASEARCH)/lib/lualib-luajit/ $(INST)/lualib/jit/)
	rsync -rt .errno.$(BASEARCH).lua $(INST)/lualib/$(PLATFORM_STRING)/errno.lua
	./generate-thb-ver "$(DATE)" > $(INST)/lualib/thb-ver.lua

pkg: install
	@echo »»» packing $(ARCH) to $(PKG).tar.xz
	cp -r $(INST) install/$(PKG)
	cd install && tar -c $(PKG)|xz > $(PKG).tar.xz
	rm -rf install/$(PKG)

l_init.c: luatoc.lua extensions.lua lualib-vendor/* l_init.lua
	@./quiet "$@" lua $< l_init extensions.lua lualib-vendor/* +l_init.lua

.Makefile.$(ARCH): generate-platform-Makefile
	@./quiet "$@" ./generate-platform-Makefile "$@"

ifneq ($(BASEARCH),osx)
.errno.$(BASEARCH).h: ./compile-c
	@./compile-c $@ -include "errno.h" -E -dM - < /dev/null

.errno.$(BASEARCH).lua: .errno.$(BASEARCH).h
	@./quiet "$@" lua5.1 extract_errno.lua "$@" < "$<"
endif

.errno.osx.lua .errno.osx64.lua:
	@cat lualib/osx/errno.lua > "$@"

%-$(ARCH)$(EXE_SUFFIX): $(OBJS) ./link-%
	@./link-$* $@ $(OBJS)

%-$(ARCH)-stripped$(EXE_SUFFIX): %-$(ARCH)$(EXE_SUFFIX)
	@$(STRIP) $< -o $@

.%.$(ARCH).o: %.c ./compile-c
	@rm -f .$*.$(ARCH).d
	@./compile-c $@ -MMD -MP -c $<

.%.$(ARCH).o: %.m ./compile-c
	@rm -f .$*.$(ARCH).d
	@./compile-c $@ -MMD -MP -c $<

%.c.i: %.c
	@./compile-c - -E $< | $(PAGER)

%.c.s: %.c
	@./compile-c - -S $< | $(PAGER)

%.m.i: %.m
	@./compile-c - -E $< | $(PAGER)

%.m.s: %.m
	@./compile-c - -S $< | $(PAGER)

result_files = $(OBJS) $(OBJS:.o=.d)

clean::
	@rm -f quiet.log
	@./quiet ".d .c" rm -f $(foreach ARCH,$(PLATFORMS),$(result_files))
	@./quiet ".l_init.*" rm -f .l_init.d l_init.c

nuke: clean
	@./quiet "thb-*" rm -f $(addprefix thb-,$(PLATFORMS))*

ifneq ($(MAKECMDGOALS),clean)
  ifneq ($(MAKECMDGOALS),nuke)
-include $(OBJS:.o=.d)
-include .l_init.d
  endif
endif
