# Determine the operating system
OSTYPE ?=

ifeq ($(OS),Windows_NT)
  OSTYPE = windows
else
  UNAME_S := $(shell uname -s)

  ifeq ($(UNAME_S),Linux)
    OSTYPE = linux

    ifndef AR
      ifneq (,$(shell which gcc-ar 2> /dev/null))
        AR = gcc-ar
      endif
    endif

    ALPINE=$(wildcard /etc/alpine-release)
  endif

  ifeq ($(UNAME_S),Darwin)
    OSTYPE = osx
  endif

  ifeq ($(UNAME_S),FreeBSD)
    OSTYPE = bsd
    CXX = c++
  endif

  ifeq ($(UNAME_S),DragonFly)
    OSTYPE = bsd
    CXX = c++
  endif
endif

ifdef LTO_PLUGIN
  lto := yes
endif

# Default settings (silent release build).
config ?= release
arch ?= native
tune ?= generic
bits ?= $(shell getconf LONG_BIT)

ifndef verbose
  SILENT = @
else
  SILENT =
endif

ifneq ($(wildcard .git),)
  tag := $(shell cat VERSION)-$(shell git rev-parse --short HEAD)
else
  tag := $(shell cat VERSION)
endif

version_str = "$(tag) [$(config)]\ncompiled with: llvm $(llvm_version) \
  -- "$(compiler_version)

# package_name, _version, and _iteration can be overridden by Travis or AppVeyor
package_base_version ?= $(tag)
package_iteration ?= "1"
package_name ?= "ponyc"
package_version = $(package_base_version)-$(package_iteration)
archive = $(package_name)-$(package_version).tar
package = build/$(package_name)-$(package_version)

symlink := yes

ifdef destdir
  ifndef prefix
    symlink := no
  endif
endif

ifneq (,$(filter $(OSTYPE), osx bsd))
  symlink.flags = -sf
else
  symlink.flags = -srf
endif

prefix ?= /usr/local
destdir ?= $(prefix)/lib/pony/$(tag)

LIB_EXT ?= a
BUILD_FLAGS = -march=$(arch) -mtune=$(tune) -Werror -Wconversion \
  -Wno-sign-conversion -Wextra -Wall
LINKER_FLAGS = -march=$(arch) -mtune=$(tune)
AR_FLAGS ?= rcs
ALL_CFLAGS = -std=gnu11 -fexceptions \
  -DPONY_VERSION=\"$(tag)\" -DLLVM_VERSION=\"$(llvm_version)\" \
  -DPONY_COMPILER=\"$(CC)\" -DPONY_ARCH=\"$(arch)\" \
  -DBUILD_COMPILER=\"$(compiler_version)\" \
  -DPONY_BUILD_CONFIG=\"$(config)\" \
  -DPONY_VERSION_STR=\"$(version_str)\" \
  -D_FILE_OFFSET_BITS=64
ALL_CXXFLAGS = -std=gnu++11 -fno-rtti

# Determine pointer size in bits.
BITS := $(bits)
UNAME_M := $(shell uname -m)

ifeq ($(BITS),64)
  ifneq ($(UNAME_M),aarch64)
    BUILD_FLAGS += -mcx16
    LINKER_FLAGS += -mcx16
  endif
endif

PONY_BUILD_DIR   ?= build/$(config)
PONY_SOURCE_DIR  ?= src
PONY_TEST_DIR ?= test
PONY_BENCHMARK_DIR ?= benchmark

ifdef use
  ifneq (,$(filter $(use), valgrind))
    ALL_CFLAGS += -DUSE_VALGRIND
    PONY_BUILD_DIR := $(PONY_BUILD_DIR)-valgrind
  endif

  ifneq (,$(filter $(use), coverage))
    ifneq (,$(shell $(CC) -v 2>&1 | grep clang))
      # clang
      COVERAGE_FLAGS = -O0 -fprofile-instr-generate -fcoverage-mapping
      LINKER_FLAGS += -fprofile-instr-generate -fcoverage-mapping
    else
      ifneq (,$(shell $(CC) -v 2>&1 | grep "gcc version"))
        # gcc
        COVERAGE_FLAGS = -O0 -fprofile-arcs -ftest-coverage
        LINKER_FLAGS += -fprofile-arcs
      else
        $(error coverage not supported for this compiler/platform)
      endif
      ALL_CFLAGS += $(COVERAGE_FLAGS)
      ALL_CXXFLAGS += $(COVERAGE_FLAGS)
    endif
    PONY_BUILD_DIR := $(PONY_BUILD_DIR)-coverage
  endif

  ifneq (,$(filter $(use), pooltrack))
    ALL_CFLAGS += -DUSE_POOLTRACK
    PONY_BUILD_DIR := $(PONY_BUILD_DIR)-pooltrack
  endif

  ifneq (,$(filter $(use), dtrace))
    DTRACE ?= $(shell which dtrace)
    ifeq (, $(DTRACE))
      $(error No dtrace compatible user application static probe generation tool found)
    endif

    ALL_CFLAGS += -DUSE_DYNAMIC_TRACE
    PONY_BUILD_DIR := $(PONY_BUILD_DIR)-dtrace
  endif

  ifneq (,$(filter $(use), actor_continuations))
    ALL_CFLAGS += -DUSE_ACTOR_CONTINUATIONS
    PONY_BUILD_DIR := $(PONY_BUILD_DIR)-actor_continuations
  endif
endif

ifdef config
  ifeq (,$(filter $(config),debug release))
    $(error Unknown configuration "$(config)")
  endif
endif

ifeq ($(config),release)
  BUILD_FLAGS += -O3 -DNDEBUG

  ifeq ($(lto),yes)
    BUILD_FLAGS += -flto -DPONY_USE_LTO
    LINKER_FLAGS += -flto

    ifdef LTO_PLUGIN
      AR_FLAGS += --plugin $(LTO_PLUGIN)
    endif

    ifneq (,$(filter $(OSTYPE),linux bsd))
      LINKER_FLAGS += -fuse-linker-plugin -fuse-ld=gold
    endif
  endif
else
  BUILD_FLAGS += -g -DDEBUG
endif

ifeq ($(OSTYPE),osx)
  ALL_CFLAGS += -mmacosx-version-min=10.8
  ALL_CXXFLAGS += -stdlib=libc++ -mmacosx-version-min=10.8
endif

ifndef LLVM_CONFIG
	ifneq (,$(shell which /usr/local/opt/llvm@3.9/bin/llvm-config 2> /dev/null))
    LLVM_CONFIG = /usr/local/opt/llvm@3.9/bin/llvm-config
    LLVM_LINK = /usr/local/opt/llvm@3.9/bin/llvm-link
    LLVM_OPT = /usr/local/opt/llvm@3.9/bin/opt
  else ifneq (,$(shell which llvm-config-3.9 2> /dev/null))
    LLVM_CONFIG = llvm-config-3.9
    LLVM_LINK = llvm-link-3.9
    LLVM_OPT = opt-3.9
  else ifneq (,$(shell which llvm-config-3.8 2> /dev/null))
    LLVM_CONFIG = llvm-config-3.8
    LLVM_LINK = llvm-link-3.8
    LLVM_OPT = opt-3.8
  else ifneq (,$(shell which llvm-config-mp-3.8 2> /dev/null))
    LLVM_CONFIG = llvm-config-mp-3.8
    LLVM_LINK = llvm-link-mp-3.8
    LLVM_OPT = opt-mp-3.8
  else ifneq (,$(shell which llvm-config-3.7 2> /dev/null))
    LLVM_CONFIG = llvm-config-3.7
    LLVM_LINK = llvm-link-3.7
    LLVM_OPT = opt-3.7
  else ifneq (,$(shell which llvm-config-3.6 2> /dev/null))
    LLVM_CONFIG = llvm-config-3.6
    LLVM_LINK = llvm-link-3.6
    LLVM_OPT = opt-3.6
  else ifneq (,$(shell which llvm-config39 2> /dev/null))
    LLVM_CONFIG = llvm-config39
    LLVM_LINK = llvm-link39
    LLVM_OPT = opt39
  else ifneq (,$(shell which llvm-config38 2> /dev/null))
    LLVM_CONFIG = llvm-config38
    LLVM_LINK = llvm-link38
    LLVM_OPT = opt38
  else ifneq (,$(shell which llvm-config37 2> /dev/null))
    LLVM_CONFIG = llvm-config37
    LLVM_LINK = llvm-link37
    LLVM_OPT = opt37
  else ifneq (,$(shell which /usr/local/opt/llvm/bin/llvm-config 2> /dev/null))
    LLVM_CONFIG = /usr/local/opt/llvm/bin/llvm-config
    LLVM_LINK = /usr/local/opt/llvm/bin/llvm-link
    LLVM_OPT = /usr/local/opt/llvm/bin/opt
  else ifneq (,$(shell which llvm-config 2> /dev/null))
    LLVM_CONFIG = llvm-config
    LLVM_LINK = llvm-link
    LLVM_OPT = opt
  endif
endif

ifndef LLVM_CONFIG
  $(error No LLVM installation found!)
endif

llvm_version := $(shell $(LLVM_CONFIG) --version)

ifeq ($(OSTYPE),osx)
	llvm_bindir := $(shell $(LLVM_CONFIG) --bindir)

  ifneq (,$(shell which $(llvm_bindir)/llvm-ar 2> /dev/null))
    AR = $(llvm_bindir)/llvm-ar
    AR_FLAGS := rcs
  else ifneq (,$(shell which llvm-ar-mp-3.8 2> /dev/null))
    AR = llvm-ar-mp-3.8
    AR_FLAGS := rcs
  else ifneq (,$(shell which llvm-ar-3.8 2> /dev/null))
    AR = llvm-ar-3.8
    AR_FLAGS := rcs
  else
    AR = /usr/bin/ar
		AR_FLAGS := -rcs
  endif
endif

ifeq ($(llvm_version),3.7.1)
else ifeq ($(llvm_version),3.8.1)
else ifeq ($(llvm_version),3.9.1)
else
  $(warning WARNING: Unsupported LLVM version: $(llvm_version))
  $(warning Please use LLVM 3.7.1, 3.8.1, or 3.9.1)
endif

compiler_version := "$(shell $(CC) --version | sed -n 1p)"

ifeq ($(runtime-bitcode),yes)
  ifeq (,$(shell $(CC) -v 2>&1 | grep clang))
    $(error Compiling the runtime as a bitcode file requires clang)
  endif
endif

makefile_abs_path := $(realpath $(lastword $(MAKEFILE_LIST)))
packages_abs_src := $(shell dirname $(makefile_abs_path))/packages

$(shell mkdir -p $(PONY_BUILD_DIR))

lib   := $(PONY_BUILD_DIR)
bin   := $(PONY_BUILD_DIR)
tests := $(PONY_BUILD_DIR)
benchmarks := $(PONY_BUILD_DIR)
obj   := $(PONY_BUILD_DIR)/obj

# Libraries. Defined as
# (1) a name and output directory
libponyc  := $(lib)
libponycc := $(lib)
libponyrt := $(lib)

ifeq ($(OSTYPE),linux)
  libponyrt-pic := $(lib)
endif

# Define special case rules for a targets source files. By default
# this makefile assumes that a targets source files can be found
# relative to a parent directory of the same name in $(PONY_SOURCE_DIR).
# Note that it is possible to collect files and exceptions with
# arbitrarily complex shell commands, as long as ':=' is used
# for definition, instead of '='.
ifneq ($(OSTYPE),windows)
  libponyc.except += src/libponyc/platform/signed.cc
  libponyc.except += src/libponyc/platform/unsigned.cc
  libponyc.except += src/libponyc/platform/vcvars.c
endif

# Handle platform specific code to avoid "no symbols" warnings.
libponyrt.except =

ifneq ($(OSTYPE),windows)
  libponyrt.except += src/libponyrt/asio/iocp.c
  libponyrt.except += src/libponyrt/lang/win_except.c
endif

ifneq ($(OSTYPE),linux)
  libponyrt.except += src/libponyrt/asio/epoll.c
endif

ifneq ($(OSTYPE),osx)
  ifneq ($(OSTYPE),bsd)
    libponyrt.except += src/libponyrt/asio/kqueue.c
  endif
endif

libponyrt.except += src/libponyrt/asio/sock.c
libponyrt.except += src/libponyrt/dist/dist.c
libponyrt.except += src/libponyrt/dist/proto.c

ifeq ($(OSTYPE),linux)
  libponyrt-pic.dir := src/libponyrt
  libponyrt-pic.except := $(libponyrt.except)
endif

# Third party, but requires compilation. Defined as
# (1) a name and output directory.
# (2) a list of the source files to be compiled.
libgtest := $(lib)
libgtest.dir := lib/gtest
libgtest.files := $(libgtest.dir)/gtest-all.cc
libgbenchmark := $(lib)
libgbenchmark.dir := lib/gbenchmark
libgbenchmark.files := $(libgbenchmark.dir)/gbenchmark_main.cc $(libgbenchmark.dir)/gbenchmark-all.cc
libblake2 := $(lib)
libblake2.dir := lib/blake2
libblake2.files := $(libblake2.dir)/blake2b-ref.c

# We don't add libponyrt here. It's a special case because it can be compiled
# to LLVM bitcode.
ifeq ($(OSTYPE), linux)
  libraries := libponyc libponyrt-pic libgtest libgbenchmark libblake2
else
  libraries := libponyc libgtest libgbenchmark libblake2
endif

# Third party, but prebuilt. Prebuilt libraries are defined as
# (1) a name (stored in prebuilt)
# (2) the linker flags necessary to link against the prebuilt libraries
# (3) a list of include directories for a set of libraries
# (4) a list of the libraries to link against
llvm.ldflags := $(shell $(LLVM_CONFIG) --ldflags)
llvm.include.dir := $(shell $(LLVM_CONFIG) --includedir)
include.paths := $(shell echo | $(CC) -v -E - 2>&1)
ifeq (,$(findstring $(llvm.include.dir),$(include.paths)))
# LLVM include directory is not in the existing paths;
# put it at the top of the system list
llvm.include := -isystem $(llvm.include.dir)
else
# LLVM include directory is already on the existing paths;
# do nothing
llvm.include :=
endif
llvm.libs    := $(shell $(LLVM_CONFIG) --libs) -lz -lncurses

ifeq ($(OSTYPE), bsd)
  llvm.libs += -lpthread -lexecinfo
endif

prebuilt := llvm

# Binaries. Defined as
# (1) a name and output directory.
ponyc := $(bin)

binaries := ponyc

# Tests suites are directly attached to the libraries they test.
libponyc.tests  := $(tests)
libponyrt.tests := $(tests)

tests := libponyc.tests libponyrt.tests

# Benchmark suites are directly attached to the libraries they test.
libponyc.benchmarks  := $(benchmarks)
libponyrt.benchmarks := $(benchmarks)

benchmarks := libponyc.benchmarks libponyrt.benchmarks

# Define include paths for targets if necessary. Note that these include paths
# will automatically apply to the test suite of a target as well.
libponyc.include := -I src/common/ -I src/libponyrt/ $(llvm.include) \
  -isystem lib/blake2
libponycc.include := -I src/common/ $(llvm.include)
libponyrt.include := -I src/common/ -I src/libponyrt/
libponyrt-pic.include := $(libponyrt.include)

libponyc.tests.include := -I src/common/ -I src/libponyc/ -I src/libponyrt \
  $(llvm.include) -isystem lib/gtest/
libponyrt.tests.include := -I src/common/ -I src/libponyrt/ -isystem lib/gtest/

libponyc.benchmarks.include := -I src/common/ -I src/libponyc/ \
  $(llvm.include) -isystem lib/gbenchmark/include/
libponyrt.benchmarks.include := -I src/common/ -I src/libponyrt/ -isystem \
  lib/gbenchmark/include/

ponyc.include := -I src/common/ -I src/libponyrt/ $(llvm.include)
libgtest.include := -isystem lib/gtest/
libgbenchmark.include := -isystem lib/gbenchmark/include/
libblake2.include := -isystem lib/blake2/

ifneq (,$(filter $(OSTYPE), osx bsd))
  libponyrt.include += -I /usr/local/include
endif

# target specific build options
libponyrt.buildoptions = -DPONY_NO_ASSERT
libponyrt-pic.buildoptions = -DPONY_NO_ASSERT

libponyrt.tests.linkoptions += -rdynamic

ifneq ($(ALPINE),)
  libponyrt.tests.linkoptions += -lexecinfo
endif

libponyc.buildoptions = -D__STDC_CONSTANT_MACROS
libponyc.buildoptions += -D__STDC_FORMAT_MACROS
libponyc.buildoptions += -D__STDC_LIMIT_MACROS

libponyc.tests.buildoptions = -D__STDC_CONSTANT_MACROS
libponyc.tests.buildoptions += -D__STDC_FORMAT_MACROS
libponyc.tests.buildoptions += -D__STDC_LIMIT_MACROS
libponyc.tests.buildoptions += -DPONY_PACKAGES_DIR=\"$(packages_abs_src)\"

libponyc.tests.linkoptions += -rdynamic

ifneq ($(ALPINE),)
  libponyc.tests.linkoptions += -lexecinfo
endif

libponyc.benchmarks.buildoptions = -D__STDC_CONSTANT_MACROS
libponyc.benchmarks.buildoptions += -D__STDC_FORMAT_MACROS
libponyc.benchmarks.buildoptions += -D__STDC_LIMIT_MACROS

libgbenchmark.buildoptions := -DHAVE_POSIX_REGEX

ifneq ($(ALPINE),)
  libponyc.benchmarks.linkoptions += -lexecinfo
  libponyrt.benchmarks.linkoptions += -lexecinfo
endif

ponyc.buildoptions = $(libponyc.buildoptions)

ponyc.linkoptions += -rdynamic

ifneq ($(ALPINE),)
  ponyc.linkoptions += -lexecinfo
endif

ifeq ($(OSTYPE), linux)
  libponyrt-pic.buildoptions += -fpic
endif

# default enable PIC compiling if requested
ifdef default_pic
  libponyrt.buildoptions += -fpic
  BUILD_FLAGS += -DPONY_DEFAULT_PIC=true
endif

# target specific disabling of build options
libgtest.disable = -Wconversion -Wno-sign-conversion -Wextra
libgbenchmark.disable = -Wconversion -Wno-sign-conversion -Wextra
libblake2.disable = -Wconversion -Wno-sign-conversion -Wextra

# Link relationships.
ponyc.links = libponyc libponyrt llvm libblake2
libponyc.tests.links = libgtest libponyc llvm libblake2
libponyc.tests.links.whole = libponyrt
libponyrt.tests.links = libgtest libponyrt
libponyc.benchmarks.links = libblake2 libgbenchmark libponyc libponyrt llvm
libponyrt.benchmarks.links = libgbenchmark libponyrt

ifeq ($(OSTYPE),linux)
  ponyc.links += libpthread libdl libatomic
  libponyc.tests.links += libpthread libdl libatomic
  libponyrt.tests.links += libpthread libdl libatomic
  libponyc.benchmarks.links += libpthread libdl libatomic
  libponyrt.benchmarks.links += libpthread libdl libatomic
endif

ifeq ($(OSTYPE),bsd)
  libponyc.tests.links += libpthread
  libponyrt.tests.links += libpthread
  libponyc.benchmarks.links += libpthread
  libponyrt.benchmarks.links += libpthread
endif

ifneq (, $(DTRACE))
  $(shell $(DTRACE) -h -s $(PONY_SOURCE_DIR)/common/dtrace_probes.d -o $(PONY_SOURCE_DIR)/common/dtrace_probes.h)
endif

# Overwrite the default linker for a target.
ponyc.linker = $(CXX) #compile as C but link as CPP (llvm)
libponyc.benchmarks.linker = $(CXX)
libponyrt.benchmarks.linker = $(CXX)

# make targets
targets := $(libraries) libponyrt $(binaries) $(tests) $(benchmarks)

.PHONY: all $(targets) install uninstall clean stats deploy prerelease
all: $(targets)
	@:

# Dependencies
libponyc.depends := libponyrt libblake2
libponyc.tests.depends := libponyc libgtest
libponyrt.tests.depends := libponyrt libgtest
libponyc.benchmarks.depends := libponyc libgbenchmark
libponyrt.benchmarks.depends := libponyrt libgbenchmark
ponyc.depends := libponyc libponyrt

# Generic make section, edit with care.
##########################################################################
#                                                                        #
# DIRECTORY: Determines the source dir of a specific target              #
#                                                                        #
# ENUMERATE: Enumerates input and output files for a specific target     #
#                                                                        #
# CONFIGURE_COMPILER: Chooses a C or C++ compiler depending on the       #
#                     target file.                                       #
#                                                                        #
# CONFIGURE_LIBS: Builds a string of libraries to link for a targets     #
#                 link dependency.                                       #
#                                                                        #
# CONFIGURE_LINKER: Assembles the linker flags required for a target.    #
#                                                                        #
# EXPAND_COMMAND: Macro that expands to a proper make command for each   #
#                 target.                                                #
#                                                                        #
##########################################################################
define DIRECTORY
  $(eval sourcedir := )
  $(eval outdir := $(obj)/$(1))

  ifdef $(1).dir
    sourcedir := $($(1).dir)
  else ifneq ($$(filter $(1),$(tests)),)
    sourcedir := $(PONY_TEST_DIR)/$(subst .tests,,$(1))
    outdir := $(obj)/tests/$(subst .tests,,$(1))
  else ifneq ($$(filter $(1),$(benchmarks)),)
    sourcedir := $(PONY_BENCHMARK_DIR)/$(subst .benchmarks,,$(1))
    outdir := $(obj)/benchmarks/$(subst .benchmarks,,$(1))
  else
    sourcedir := $(PONY_SOURCE_DIR)/$(1)
  endif
endef

define ENUMERATE
  $(eval sourcefiles := )

  ifdef $(1).files
    sourcefiles := $$($(1).files)
  else
    sourcefiles := $$(shell find $$(sourcedir) -type f -name "*.c" -or -name\
      "*.cc" | grep -v '.*/\.')
  endif

  ifdef $(1).except
    sourcefiles := $$(filter-out $($(1).except),$$(sourcefiles))
  endif
endef

define CONFIGURE_COMPILER
  ifeq ($(suffix $(1)),.cc)
    compiler := $(CXX)
    flags := $(ALL_CXXFLAGS) $(CXXFLAGS)
  endif

  ifeq ($(suffix $(1)),.c)
    compiler := $(CC)
    flags := $(ALL_CFLAGS) $(CFLAGS)
  endif

  ifeq ($(suffix $(1)),.bc)
    compiler := $(CC)
    flags := $(ALL_CFLAGS) $(CFLAGS)
  endif
endef

define CONFIGURE_LIBS
  ifneq (,$$(filter $(1),$(prebuilt)))
    linkcmd += $($(1).ldflags)
    libs += $($(1).libs)
  else
    libs += $(subst lib,-l,$(1))
  endif
endef

define CONFIGURE_LIBS_WHOLE
  ifeq ($(OSTYPE),osx)
    wholelibs += -Wl,-force_load,$(PONY_BUILD_DIR)/$(1).a
  else
    wholelibs += $(subst lib,-l,$(1))
  endif
endef

define CONFIGURE_LINKER_WHOLE
  $(eval wholelibs :=)

  ifneq ($($(1).links.whole),)
    $(foreach lk,$($(1).links.whole),$(eval $(call CONFIGURE_LIBS_WHOLE,$(lk))))
    ifeq ($(OSTYPE),osx)
      libs += $(wholelibs)
    else
      libs += -Wl,--whole-archive $(wholelibs) -Wl,--no-whole-archive
    endif
  endif
endef

define CONFIGURE_LINKER
  $(eval linkcmd := $(LINKER_FLAGS) -L $(lib) -L /usr/local/lib )
  $(eval linker := $(CC))
  $(eval libs :=)

  ifdef $(1).linker
    linker := $($(1).linker)
  else ifneq (,$$(filter .cc,$(suffix $(sourcefiles))))
    linker := $(CXX)
  endif

  $(eval $(call CONFIGURE_LINKER_WHOLE,$(1)))
  $(foreach lk,$($(1).links),$(eval $(call CONFIGURE_LIBS,$(lk))))
  linkcmd += $(libs) $($(1).linkoptions)
endef

define PREPARE
  $(eval $(call DIRECTORY,$(1)))
  $(eval $(call ENUMERATE,$(1)))
  $(eval $(call CONFIGURE_LINKER,$(1)))
  $(eval objectfiles  := $(subst $(sourcedir)/,$(outdir)/,$(addsuffix .o,\
    $(sourcefiles))))
  $(eval bitcodefiles := $(subst .o,.bc,$(objectfiles)))
  $(eval dependencies := $(subst .c,,$(subst .cc,,$(subst .o,.d,\
    $(objectfiles)))))
endef

define EXPAND_OBJCMD
$(eval file := $(subst .o,,$(1)))
$(eval $(call CONFIGURE_COMPILER,$(file)))

ifeq ($(3),libponyrtyes)
  ifneq ($(suffix $(file)),.bc)
$(subst .c,,$(subst .cc,,$(1))): $(subst .c,.bc,$(subst .cc,.bc,$(file)))
	@echo '$$(notdir $$<)'
	@mkdir -p $$(dir $$@)
	$(SILENT)$(compiler) $(flags) -c -o $$@ $$<
  else
$(subst .c,,$(subst .cc,,$(1))): $(subst $(outdir)/,$(sourcedir)/,$(subst .bc,,$(file)))
	@echo '$$(notdir $$<)'
	@mkdir -p $$(dir $$@)
	$(SILENT)$(compiler) -MMD -MP $(filter-out $($(2).disable),$(BUILD_FLAGS)) \
    $(flags) $($(2).buildoptions) -emit-llvm -c -o $$@ $$<  $($(2).include)
  endif
else
$(subst .c,,$(subst .cc,,$(1))): $(subst $(outdir)/,$(sourcedir)/,$(file))
	@echo '$$(notdir $$<)'
	@mkdir -p $$(dir $$@)
	$(SILENT)$(compiler) -MMD -MP $(filter-out $($(2).disable),$(BUILD_FLAGS)) \
    $(flags) $($(2).buildoptions) -c -o $$@ $$<  $($(2).include)
endif
endef

define EXPAND_COMMAND
$(eval $(call PREPARE,$(1)))
$(eval ofiles := $(subst .c,,$(subst .cc,,$(objectfiles))))
$(eval bcfiles := $(subst .c,,$(subst .cc,,$(bitcodefiles))))
$(eval depends := )
$(foreach d,$($(1).depends),$(eval depends += $($(d))/$(d).$(LIB_EXT)))

ifeq ($(1),libponyrt)
$($(1))/libponyrt.$(LIB_EXT): $(depends) $(ofiles)
	@echo 'Linking libponyrt'
    ifneq (,$(DTRACE))
    ifeq ($(OSTYPE), linux)
	@echo 'Generating dtrace object file'
	$(SILENT)$(DTRACE) -G -s $(PONY_SOURCE_DIR)/common/dtrace_probes.d -o $(PONY_BUILD_DIR)/dtrace_probes.o
	$(SILENT)$(AR) $(AR_FLAGS) $$@ $(ofiles) $(PONY_BUILD_DIR)/dtrace_probes.o
    else
	$(SILENT)$(AR) $(AR_FLAGS) $$@ $(ofiles)
    endif
    else
	$(SILENT)$(AR) $(AR_FLAGS) $$@ $(ofiles)
    endif
  ifeq ($(runtime-bitcode),yes)
$($(1))/libponyrt.bc: $(depends) $(bcfiles)
	@echo 'Generating bitcode for libponyrt'
	$(SILENT)$(LLVM_LINK) -o $$@ $(bcfiles)
    ifeq ($(config),release)
	$(SILENT)$(LLVM_OPT) -O3 -o $$@ $$@
    endif
libponyrt: $($(1))/libponyrt.bc $($(1))/libponyrt.$(LIB_EXT)
  else
libponyrt: $($(1))/libponyrt.$(LIB_EXT)
  endif
else ifneq ($(filter $(1),$(libraries)),)
$($(1))/$(1).$(LIB_EXT): $(depends) $(ofiles)
	@echo 'Linking $(1)'
	$(SILENT)$(AR) $(AR_FLAGS) $$@ $(ofiles)
$(1): $($(1))/$(1).$(LIB_EXT)
else
$($(1))/$(1): $(depends) $(ofiles)
	@echo 'Linking $(1)'
	$(SILENT)$(linker) -o $$@ $(ofiles) $(linkcmd)
$(1): $($(1))/$(1)
endif

$(foreach bcfile,$(bitcodefiles),$(eval $(call EXPAND_OBJCMD,$(bcfile),$(1),$(addsuffix $(runtime-bitcode),$(1)))))
$(foreach ofile,$(objectfiles),$(eval $(call EXPAND_OBJCMD,$(ofile),$(1),$(addsuffix $(runtime-bitcode),$(1)))))
-include $(dependencies)
endef

$(foreach target,$(targets),$(eval $(call EXPAND_COMMAND,$(target))))


define EXPAND_INSTALL
ifeq ($(OSTYPE),linux)
install: libponyc libponyrt libponyrt-pic ponyc
else
install: libponyc libponyrt ponyc
endif
	@mkdir -p $(destdir)/bin
	@mkdir -p $(destdir)/lib
	@mkdir -p $(destdir)/include/pony/detail
	$(SILENT)cp $(PONY_BUILD_DIR)/libponyrt.a $(destdir)/lib
ifeq ($(OSTYPE),linux)
	$(SILENT)cp $(PONY_BUILD_DIR)/libponyrt-pic.a $(destdir)/lib
endif
ifneq ($(wildcard $(PONY_BUILD_DIR)/libponyrt.bc),)
	$(SILENT)cp $(PONY_BUILD_DIR)/libponyrt.bc $(destdir)/lib
endif
	$(SILENT)cp $(PONY_BUILD_DIR)/libponyc.a $(destdir)/lib
	$(SILENT)cp $(PONY_BUILD_DIR)/ponyc $(destdir)/bin
	$(SILENT)cp src/libponyrt/pony.h $(destdir)/include
	$(SILENT)cp src/common/pony/detail/atomics.h $(destdir)/include/pony/detail
	$(SILENT)cp -r packages $(destdir)/
ifeq ($$(symlink),yes)
	@mkdir -p $(prefix)/bin
	@mkdir -p $(prefix)/lib
	@mkdir -p $(prefix)/include/pony/detail
	$(SILENT)ln $(symlink.flags) $(destdir)/bin/ponyc $(prefix)/bin/ponyc
	$(SILENT)ln $(symlink.flags) $(destdir)/lib/libponyrt.a $(prefix)/lib/libponyrt.a
ifeq ($(OSTYPE),linux)
	$(SILENT)ln $(symlink.flags) $(destdir)/lib/libponyrt-pic.a $(prefix)/lib/libponyrt-pic.a
endif
ifneq ($(wildcard $(destdir)/lib/libponyrt.bc),)
	$(SILENT)ln $(symlink.flags) $(destdir)/lib/libponyrt.bc $(prefix)/lib/libponyrt.bc
endif
	$(SILENT)ln $(symlink.flags) $(destdir)/lib/libponyc.a $(prefix)/lib/libponyc.a
	$(SILENT)ln $(symlink.flags) $(destdir)/include/pony.h $(prefix)/include/pony.h
	$(SILENT)ln $(symlink.flags) $(destdir)/include/pony/detail/atomics.h $(prefix)/include/pony/detail/atomics.h
endif
endef

$(eval $(call EXPAND_INSTALL))

define EXPAND_UNINSTALL
uninstall:
	-$(SILENT)rm -rf $(destdir) 2>/dev/null ||:
	-$(SILENT)rm $(prefix)/bin/ponyc 2>/dev/null ||:
	-$(SILENT)rm $(prefix)/lib/libponyrt.a 2>/dev/null ||:
ifeq ($(OSTYPE),linux)
	-$(SILENT)rm $(prefix)/lib/libponyrt-pic.a 2>/dev/null ||:
endif
ifneq ($(wildcard $(prefix)/lib/libponyrt.bc),)
	-$(SILENT)rm $(prefix)/lib/libponyrt.bc 2>/dev/null ||:
endif
	-$(SILENT)rm $(prefix)/lib/libponyc.a 2>/dev/null ||:
	-$(SILENT)rm $(prefix)/include/pony.h 2>/dev/null ||:
	-$(SILENT)rm -r $(prefix)/include/pony/ 2>/dev/null ||:
endef

$(eval $(call EXPAND_UNINSTALL))

ifdef verbose
  bench_verbose = -DCMAKE_VERBOSE_MAKEFILE=true
endif

ifeq ($(lto),yes)
  bench_lto = -DBENCHMARK_ENABLE_LTO=true
endif

benchmark: all
	@echo "Running libponyc benchmarks..."
	@$(PONY_BUILD_DIR)/libponyc.benchmarks
	@echo "Running libponyrt benchmarks..."
	@$(PONY_BUILD_DIR)/libponyrt.benchmarks

test: all
	@$(PONY_BUILD_DIR)/libponyc.tests
	@$(PONY_BUILD_DIR)/libponyrt.tests
	@$(PONY_BUILD_DIR)/ponyc -d -s --checktree --verify packages/stdlib
	@./stdlib --sequential
	@rm stdlib

test-examples: all
	@PONYPATH=. $(PONY_BUILD_DIR)/ponyc -d -s --checktree --verify examples
	@./examples1
	@rm examples1

test-ci: all
	@$(PONY_BUILD_DIR)/ponyc --version
	@$(PONY_BUILD_DIR)/libponyc.tests
	@$(PONY_BUILD_DIR)/libponyrt.tests
	@$(PONY_BUILD_DIR)/ponyc -d -s --checktree --verify packages/stdlib
	@./stdlib --sequential
	@rm stdlib
	@$(PONY_BUILD_DIR)/ponyc --checktree --verify packages/stdlib
	@./stdlib --sequential
	@rm stdlib
	@PONYPATH=. $(PONY_BUILD_DIR)/ponyc -d -s --checktree --verify examples
	@./examples1
	@rm examples1
	@$(PONY_BUILD_DIR)/ponyc --antlr > pony.g.new
	@diff pony.g pony.g.new
	@rm pony.g.new

docs: all
	$(SILENT)$(PONY_BUILD_DIR)/ponyc packages/stdlib --docs --pass expr
	$(SILENT)cp .docs/extra.js stdlib-docs/docs/
	$(SILENT)sed -i 's/site_name:\ stdlib/site_name:\ Pony Standard Library/' stdlib-docs/mkdocs.yml

# Note: linux only
define EXPAND_DEPLOY
deploy: test docs
	$(SILENT)bash .bintray.bash debian "$(package_version)" "$(package_name)"
	$(SILENT)bash .bintray.bash rpm    "$(package_version)" "$(package_name)"
	$(SILENT)bash .bintray.bash source "$(package_version)" "$(package_name)"
	$(SILENT)rm -rf build/bin
	@mkdir -p build/bin
	@mkdir -p $(package)/usr/bin
	@mkdir -p $(package)/usr/include/pony/detail
	@mkdir -p $(package)/usr/lib
	@mkdir -p $(package)/usr/lib/pony/$(package_version)/bin
	@mkdir -p $(package)/usr/lib/pony/$(package_version)/include/pony/detail
	@mkdir -p $(package)/usr/lib/pony/$(package_version)/lib
	$(SILENT)cp $(PONY_BUILD_DIR)/libponyc.a $(package)/usr/lib/pony/$(package_version)/lib
	$(SILENT)cp $(PONY_BUILD_DIR)/libponyrt.a $(package)/usr/lib/pony/$(package_version)/lib
ifeq ($(OSTYPE),linux)
	$(SILENT)cp $(PONY_BUILD_DIR)/libponyrt-pic.a $(package)/usr/lib/pony/$(package_version)/lib
endif
ifneq ($(wildcard $(PONY_BUILD_DIR)/libponyrt.bc),)
	$(SILENT)cp $(PONY_BUILD_DIR)/libponyrt.bc $(package)/usr/lib/pony/$(package_version)/lib
endif
	$(SILENT)cp $(PONY_BUILD_DIR)/ponyc $(package)/usr/lib/pony/$(package_version)/bin
	$(SILENT)cp src/libponyrt/pony.h $(package)/usr/lib/pony/$(package_version)/include
	$(SILENT)cp src/common/pony/detail/atomics.h $(package)/usr/lib/pony/$(package_version)/include/pony/detail
	$(SILENT)ln -f -s /usr/lib/pony/$(package_version)/lib/libponyrt.a $(package)/usr/lib/libponyrt.a
ifeq ($(OSTYPE),linux)
	$(SILENT)ln -f -s /usr/lib/pony/$(package_version)/lib/libponyrt-pic.a $(package)/usr/lib/libponyrt-pic.a
endif
ifneq ($(wildcard /usr/lib/pony/$(package_version)/lib/libponyrt.bc),)
	$(SILENT)ln -f -s /usr/lib/pony/$(package_version)/lib/libponyrt.bc $(package)/usr/lib/libponyrt.bc
endif
	$(SILENT)ln -f -s /usr/lib/pony/$(package_version)/lib/libponyc.a $(package)/usr/lib/libponyc.a
	$(SILENT)ln -f -s /usr/lib/pony/$(package_version)/bin/ponyc $(package)/usr/bin/ponyc
	$(SILENT)ln -f -s /usr/lib/pony/$(package_version)/include/pony.h $(package)/usr/include/pony.h
	$(SILENT)ln -f -s /usr/lib/pony/$(package_version)/include/pony/detail/atomics.h $(package)/usr/include/pony/detail/atomics.h
	$(SILENT)cp -r packages $(package)/usr/lib/pony/$(package_version)/
	$(SILENT)fpm -s dir -t deb -C $(package) -p build/bin --name $(package_name) --conflicts "ponyc-master" --conflicts "ponyc-release" --version $(package_base_version) --iteration "$(package_iteration)" --description "The Pony Compiler" --provides "ponyc" --provides "ponyc-release"
	$(SILENT)fpm -s dir -t rpm -C $(package) -p build/bin --name $(package_name) --conflicts "ponyc-master" --conflicts "ponyc-release" --version $(package_base_version) --iteration "$(package_iteration)" --description "The Pony Compiler" --provides "ponyc" --provides "ponyc-release" --depends "ponydep-ncurses"
	$(SILENT)git archive HEAD > build/bin/$(archive)
	$(SILENT)tar rvf build/bin/$(archive) stdlib-docs
	$(SILENT)bzip2 build/bin/$(archive)
	$(SILENT)rm -rf $(package) build/bin/$(archive)
endef

$(eval $(call EXPAND_DEPLOY))

stats:
	@echo
	@echo '------------------------------'
	@echo 'Compiler and standard library '
	@echo '------------------------------'
	@echo
	@cloc --read-lang-def=pony.cloc src packages
	@echo
	@echo '------------------------------'
	@echo 'Test suite:'
	@echo '------------------------------'
	@echo
	@cloc --read-lang-def=pony.cloc test

clean:
	@rm -rf $(PONY_BUILD_DIR)
	@rm -rf $(package)
	@rm -rf build/bin
	@rm -rf stdlib-docs
	@rm -f src/common/dtrace_probes.h
	-@rmdir build 2>/dev/null ||:
	@echo 'Repository cleaned ($(PONY_BUILD_DIR)).'

help:
	@echo 'Usage: make [config=name] [arch=name] [use=opt,...] [target]'
	@echo
	@echo 'CONFIGURATIONS:'
	@echo '  debug (default)'
	@echo '  release'
	@echo
	@echo 'ARCHITECTURE:'
	@echo '  native (default)'
	@echo '  [any compiler supported architecture]'
	@echo
	@echo 'USE OPTIONS:'
	@echo '   valgrind'
	@echo '   pooltrack'
	@echo '   dtrace'
	@echo '   actor_continuations'
	@echo '   coverage'
	@echo
	@echo 'TARGETS:'
	@echo '  libponyc               Pony compiler library'
	@echo '  libponyrt              Pony runtime'
	@echo '  libponyrt-pic          Pony runtime -fpic'
	@echo '  libponyc.tests         Test suite for libponyc'
	@echo '  libponyrt.tests        Test suite for libponyrt'
	@echo '  libponyc.benchmarks    Benchmark suite for libponyc'
	@echo '  libponyrt.benchmarks   Benchmark suite for libponyrt'
	@echo '  ponyc                  Pony compiler executable'
	@echo
	@echo '  all                    Build all of the above (default)'
	@echo '  test                   Run test suite'
	@echo '  benchmark              Build and run benchmark suite'
	@echo '  install                Install ponyc'
	@echo '  uninstall              Remove all versions of ponyc'
	@echo '  stats                  Print Pony cloc statistics'
	@echo '  clean                  Delete all build files'
	@echo
