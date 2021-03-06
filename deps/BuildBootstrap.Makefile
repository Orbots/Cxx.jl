JULIA_SRC := $(subst \,/,$(BASE_JULIA_SRC))
JULIA_BIN := $(subst \,/,$(BASE_JULIA_BIN))

# DD: set up correct gcc stuff for cmake
DD_PKG_CXX_CMAKE_ARGS += -DCMAKE_C_COMPILER=$(GCC_PACKAGE_ROOT)/bin/gcc
DD_PKG_CXX_CMAKE_ARGS += -DCMAKE_CXX_COMPILER=$(GCC_PACKAGE_ROOT)/bin/g++
DD_PKG_CXX_CMAKE_ARGS += -DGCC_INSTALL_PREFIX=$(GCC_PACKAGE_ROOT)
DD_PKG_CXX_CMAKE_ARGS += -DCMAKE_CXX_LINK_FLAGS="-L$(GCC_PACKAGE_ROOT)/lib64 -Wl,-rpath,$(GCC_PACKAGE_ROOT)/lib64"

# DD: set up correct gcc stuff for make
CXX = $(GCC_PACKAGE_ROOT)/bin/g++
CC = $(GCC_PACKAGE_ROOT)/bin/gcc
DD_CPPFLAGS = "-L$(GCC_PACKAGE_ROOT)/lib64 -Wl,-rpath,$(GCC_PACKAGE_ROOT)/lib64"

# still not using proper libs for gcc version.  let's throw everything we can at it...
DD_PKG_CXX_CMAKE_ARGS += -DCMAKE_PREFIX_PATH=$(GCC_PACKAGE_ROOT)
DD_BUILD_ENV += LD_LIBRARY_PATH=$(GCC_PACKAGE_ROOT)/lib64:$(GCC_PACKAGE_ROOT)/lib:$(LD_LIBRARY_PATH)


ifeq ($(LLVM_VER),)
BUILDROOT=$(JULIA_BIN)/../..
include $(JULIA_SRC)/deps/Versions.make
include $(BUILDROOT)/Make.user
endif
include Make.inc

LLVM_VER_MAJ:=$(word 1, $(subst ., ,$(LLVM_VER)))
LLVM_VER_MIN:=$(word 2, $(subst ., ,$(LLVM_VER)))
# define a "short" LLVM version for easy comparisons
ifeq ($(LLVM_VER),svn)
LLVM_VER_SHORT:=svn
else
LLVM_VER_SHORT:=$(LLVM_VER_MAJ).$(LLVM_VER_MIN)
endif
LLVM_VER_PATCH:=$(word 3, $(subst ., ,$(LLVM_VER)))
ifeq ($(LLVM_VER_PATCH),)
LLVM_VER_PATCH := 0
endif

ifeq ($(LLVM_VER_SHORT),$(filter $(LLVM_VER_SHORT),3.3 3.4 3.5 3.6 3.7 3.8))
LLVM_USE_CMAKE := 0
else
LLVM_USE_CMAKE := 1
endif

all: usr/lib/libcxxffi.$(SHLIB_EXT) usr/lib/libcxxffi-debug.$(SHLIB_EXT) build/clang_constants.jl

ifeq ($(OLD_CXX_ABI),1)
CXX_ABI_SETTING=-D_GLIBCXX_USE_CXX11_ABI=0
else
CXX_ABI_SETTING=-D_GLIBCXX_USE_CXX11_ABI=1
endif

CXXJL_CPPFLAGS = -I$(JULIA_SRC)/src/support -I$(BASE_JULIA_BIN)/../include

ifeq ($(JULIA_BINARY_BUILD),1)
LIBDIR := $(BASE_JULIA_BIN)/../lib/julia
else
LIBDIR := $(BASE_JULIA_BIN)/../lib
endif

CLANG_LIBS = clangFrontendTool clangBasic clangLex clangDriver clangFrontend clangParse \
	clangAST clangASTMatchers clangSema clangAnalysis clangEdit \
	clangRewriteFrontend clangRewrite clangSerialization clangStaticAnalyzerCheckers \
	clangStaticAnalyzerCore clangStaticAnalyzerFrontend clangTooling clangToolingCore \
	clangCodeGen clangARCMigrate clangFormat

# If clang is not built by base julia, build it ourselves 
ifeq ($(BUILD_LLVM_CLANG),)
ifeq ($(LLVM_VER),svn)
$(error For julia built against llvm-svn, please built clang in tree)
endif

LLVM_TAR_EXT:=$(LLVM_VER).src.tar.xz
LLVM_CLANG_TAR:=src/cfe-$(LLVM_TAR_EXT)
LLVM_SRC_TAR:=src/llvm-$(LLVM_TAR_EXT)
LLVM_COMPILER_RT_TAR:=src/compiler-rt-$(LLVM_TAR_EXT)
LLVM_SRC_URL := http://llvm.org/releases/$(LLVM_VER)

src:
	mkdir $@

# Also build a new copy of LLVM, so we get headers, tools, etc.
ifeq ($(JULIA_BINARY_BUILD),1)
LLVM_SRC_DIR := src/llvm-$(LLVM_VER)
include llvm-patches/apply-llvm-patches.mk
$(LLVM_SRC_TAR): | src
	curl -o $@ $(LLVM_SRC_URL)/$(notdir $@)
src/llvm-$(LLVM_VER): $(LLVM_SRC_TAR)
	mkdir -p $@
	tar -C $@ --strip-components=1 -xf $<
build/llvm-$(LLVM_VER)/Makefile: src/llvm-$(LLVM_VER) $(LLVM_PATCH_LIST)
	mkdir -p $(dir $@)
	cd $(dir $@) && \
		env $(DD_BUILD_ENV) cmake -G "Unix Makefiles" $(DD_PKG_CXX_CMAKE_ARGS) -DLLVM_TARGETS_TO_BUILD="X86" \
		 	-DLLVM_BUILD_LLVM_DYLIB=ON -DCMAKE_BUILD_TYPE=Release \
			-DLLVM_LINK_LLVM_DYLIB=ON -DLLVM_ENABLE_THREADS=OFF \
			-DCMAKE_CXX_COMPILER_ARG1="$(CXX_ABI_SETTING)" \
			../../src/llvm-$(LLVM_VER)
build/llvm-$(LLVM_VER)/bin/llvm-config: build/llvm-$(LLVM_VER)/Makefile
	cd build/llvm-$(LLVM_VER) && $(MAKE)
LLVM_HEADER_DIRS = src/llvm-$(LLVM_VER)/include build/llvm-$(LLVM_VER)/include
CLANG_CMAKE_DEP = build/llvm-$(LLVM_VER)/bin/llvm-config
LLVM_CONFIG = ../llvm-$(LLVM_VER)/bin/llvm-config
else
CLANG_CMAKE_OPTS += -DLLVM_TABLEGEN_EXE=$(BASE_JULIA_BIN)/../tools/llvm-tblgen
endif

JULIA_LDFLAGS = -L$(BASE_JULIA_BIN)/../lib -L$(BASE_JULIA_BIN)/../lib/julia

$(LLVM_CLANG_TAR): | src
	curl -o $@ $(LLVM_SRC_URL)/$(notdir $@)
$(LLVM_COMPILER_RT_TAR): | src
	$(JLDOWNLOAD) $@ $(LLVM_SRC_URL)/$(notdir $@)
src/clang-$(LLVM_VER): $(LLVM_CLANG_TAR)
	mkdir -p $@
	tar -C $@ --strip-components=1 -xf $<
build/clang-$(LLVM_VER)/Makefile: src/clang-$(LLVM_VER) $(CLANG_CMAKE_DEP)
	mkdir -p $(dir $@)
	cd $(dir $@) && \
		env $(DD_BUILD_ENV) cmake -G "Unix Makefiles" $(DD_PKG_CXX_CMAKE_ARGS) \
			-DLLVM_BUILD_LLVM_DYLIB=ON -DCMAKE_BUILD_TYPE=Release \
			-DLLVM_LINK_LLVM_DYLIB=ON -DLLVM_ENABLE_THREADS=OFF \
                        -DCMAKE_CXX_COMPILER_ARG1="$(CXX_ABI_SETTING)" \
			-DLLVM_CONFIG=$(LLVM_CONFIG) $(CLANG_CMAKE_OPTS) ../../src/clang-$(LLVM_VER)
build/clang-$(LLVM_VER)/lib/libclangCodeGen.a: build/clang-$(LLVM_VER)/Makefile
	cd build/clang-$(LLVM_VER) && $(MAKE)
LIB_DEPENDENCY += build/clang-$(LLVM_VER)/lib/libclangCodeGen.a
JULIA_LDFLAGS += -Lbuild/clang-$(LLVM_VER)/lib
CXXJL_CPPFLAGS += -Isrc/clang-$(LLVM_VER)/lib -Ibuild/clang-$(LLVM_VER)/include \
	-Isrc/clang-$(LLVM_VER)/include
else # BUILD_LLVM_CLANG
JULIA_LDFLAGS = -L$(BASE_JULIA_BIN)/../lib -L$(BASE_JULIA_BIN)/../lib/julia
CXXJL_CPPFLAGS += -I$(JULIA_SRC)/deps/srccache/llvm-$(LLVM_VER)/tools/clang/lib \
		-I$(JULIA_SRC)/deps/llvm-$(LLVM_VER)/tools/clang/lib
endif

CXX_LLVM_VER := $(LLVM_VER)
ifeq ($(CXX_LLVM_VER),svn)
CXX_LLVM_VER := $(shell $(BASE_JULIA_BIN)/../tools/llvm-config --version)
endif

ifneq ($(LLVM_HEADER_DIRS),)
CXXJL_CPPFLAGS += $(addprefix -I,$(LLVM_HEADER_DIRS))
endif

FLAGS = -std=c++11 $(CPPFLAGS) $(CFLAGS) $(CXXJL_CPPFLAGS)

ifneq ($(USEMSVC), 1)
CPP_STDOUT := $(CPP) -P
else
CPP_STDOUT := $(CPP) -E
endif

ifeq ($(LLVM_USE_CMAKE),1)
LLVM_LIB_NAME := LLVM
else ifeq ($(LLVM_VER),svn)
LLVM_LIB_NAME := LLVM
else
LLVM_LIB_NAME := LLVM-$(CXX_LLVM_VER)
endif
LDFLAGS += -l$(LLVM_LIB_NAME)

LIB_DEPENDENCY += $(LIBDIR)/lib$(LLVM_LIB_NAME).$(SHLIB_EXT)

usr/lib:
	@mkdir -p $(CURDIR)/usr/lib/

build:
	@mkdir -p $(CURDIR)/build

LLVM_EXTRA_CPPFLAGS = 
ifneq ($(LLVM_ASSERTIONS),1)
LLVM_EXTRA_CPPFLAGS += -DLLVM_NDEBUG
endif

build/bootstrap.o: ../src/bootstrap.cpp BuildBootstrap.Makefile $(LIB_DEPENDENCY) | build
	@$(call PRINT_CC, env $(DD_BUILD_ENV) $(CXX) $(CXX_ABI_SETTING) -fno-rtti -DLIBRARY_EXPORTS -fPIC -O0 -g $(FLAGS) $(LLVM_EXTRA_CPPFLAGS) $(DD_CPPFLAGS) -c ../src/bootstrap.cpp -o $@)


LINKED_LIBS = $(addprefix -l,$(CLANG_LIBS))
ifeq ($(BUILD_LLDB),1)
LINKED_LIBS += $(LLDB_LIBS)
endif

ifneq (,$(wildcard $(BASE_JULIA_BIN)/../lib/libjulia.$(SHLIB_EXT)))
usr/lib/libcxxffi.$(SHLIB_EXT): build/bootstrap.o $(LIB_DEPENDENCY) | usr/lib
	@$(call PRINT_LINK, env $(DD_BUILD_ENV) $(CXX) -shared -fPIC $(JULIA_LDFLAGS) -ljulia $(LDFLAGS) $(DD_CPPFLAGS) -o $@ $(WHOLE_ARCHIVE) $(LINKED_LIBS) $(NO_WHOLE_ARCHIVE) $< )
else
usr/lib/libcxxffi.$(SHLIB_EXT):
	@echo "Not building release library because corresponding julia RELEASE library does not exist."
	@echo "To build, simply run the build again once the library at"
	@echo $(build_libdir)/libjulia.$(SHLIB_EXT)
	@echo "has been built."
endif

ifneq (,$(wildcard $(BASE_JULIA_BIN)/../lib/libjulia-debug.$(SHLIB_EXT)))
usr/lib/libcxxffi-debug.$(SHLIB_EXT): build/bootstrap.o $(LIB_DEPENDENCY) | usr/lib
	@$(call PRINT_LINK, env $(DD_BUILD_ENV) $(CXX) -shared -fPIC $(JULIA_LDFLAGS) -ljulia-debug $(LDFLAGS) $(DD_CPPFLAGS) -o $@ $(WHOLE_ARCHIVE) $(LINKED_LIBS) $(NO_WHOLE_ARCHIVE) $< )
else
usr/lib/libcxxffi-debug.$(SHLIB_EXT):
	@echo "Not building debug library because corresponding julia DEBUG library does not exist."
	@echo "To build, simply run the build again once the library at"
	@echo $(build_libdir)/libjulia-debug.$(SHLIB_EXT)
	@echo "has been built."
endif

build/clang_constants.jl: ../src/cenumvals.jl.h usr/lib/libcxxffi.$(SHLIB_EXT)
	@$(call PRINT_PERL, $(CPP_STDOUT) $(CXXJL_CPPFLAGS) -DJULIA ../src/cenumvals.jl.h > $@)
