# Copyright (c) 2008-2012 Jakub Piotr Cłapa
# This program is released under the new BSD license.
#
# Tool definitions
-include p-$P/Makefile
export PLATFORM_STRING

P      = none
CC     = p-$P/cc
LD     = p-$P/ld
STRIP  = p-$P/strip
PAGER ?= less
DATE  := $(shell date +%Y.%m.%d)

# Source files
CSRCS  = main.c l_init.c $(wildcard p-$P/*.c) $(wildcard p-$P/*.m)
CSRCS += $(addprefix common/,LM.c luaP.c l_additions.c l_preloads.c)
CSRCS += $(addprefix common/,l_buffer.c buffer.c l_binary.c str.c byte.c l_crc.c l_xtea.c l_sha.c lbitlib.c l_miniz.c)

OBJS   = $(join $(dir $(CSRCS)), $(addprefix .,$(addsuffix .$(P).o,$(notdir $(basename $(CSRCS))))))
EXE    = thb
INST   = install/$P
PKG    = thb-$P-$(DATE)

PLATFORMS = $(subst p-,,$(wildcard p-*))
INSTALLS = $(addprefix install/,$(PLATFORMS))
PKGS = $(addprefix pkg/,$(PLATFORMS))

.PHONY: default all docs clean nuke $(PLATFORMS) install $(INSTALLS)

default:
	@echo "Please choose a platform:"
	@echo "   $(PLATFORMS)"

$(PLATFORMS):
	make P=$@ all

$(INSTALLS):
	make P=$(subst install/,,$@) install

$(PKGS):
	make P=$(subst pkg/,,$@) pkg


$(CC): cfg
$(LD): cfg

all: $(EXE)-$P-stripped$(EXE_SUFFIX)

install: all
	@echo »»» installing $P to $(INST)
	rm -rf $(INST)
	mkdir -p $(INST)/lualib
	rsync -t $(EXE)-$P-stripped$(EXE_SUFFIX) $(INST)/thb$(EXE_SUFFIX)
	$(if $(INSTALLED_FILES),rsync -t $(INSTALLED_FILES) $(INST)/)
	rsync -rt lualib/*.lua lualib/http $(INST)/lualib
	rsync -rtL lualib/$(PLATFORM_STRING) $(INST)/lualib

pkg: install
	@echo »»» packing $P to $(PKG).tar.xz
	cp -r $(INST) install/$(PKG)
	cd install && tar -c $(PKG)|xz > $(PKG).tar.xz
	rm -rf install/$(PKG)

l_init.c: luatoc.lua
	@./quiet "$@" lua -lluarocks.loader $< l_init extensions.lua lualib-vendor/ +l_init.lua

$(EXE)-$P$(EXE_SUFFIX): $(OBJS) $(LD)
	@$(LD) $@ $(OBJS)

$(EXE)-$P-stripped$(EXE_SUFFIX): $(EXE)-$P$(EXE_SUFFIX)
	@$(STRIP) $< -o $@

.%.$(P).o: %.c $(CC)
	@rm -f .$*.$(P).d
	@$(CC) $@ -MMD -MP -c $<

.%.$(P).o: %.m $(CC)
	@rm -f .$*.$(P).d
	@$(CC) $@ -MMD -MP -c $<

%.c.i: %.c
	@$(CC) - -E $< | $(PAGER)

%.c.s: %.c
	@$(CC) - -S $< | $(PAGER)

%.m.i: %.m
	@$(CC) - -E $< | $(PAGER)

%.m.s: %.m
	@$(CC) - -S $< | $(PAGER)

result_files = $(OBJS) $(OBJS:.o=.d)

clean::
	-rm -f quiet.log
	-rm -f $(foreach P,$(PLATFORMS),$(result_files)) .l_init.d l_init.c

nuke: clean
	-rm -f $(EXE)-*

ifneq ($(MAKECMDGOALS),clean)
  ifneq ($(MAKECMDGOALS),nuke)
-include $(OBJS:.o=.d)
-include .l_init.d
  endif
endif
