ifndef CHPL_MAKE_HOME
export CHPL_MAKE_HOME=$(shell pwd)/../..
endif

CHPL_MAKE_HOST_TARGET = --target
include $(CHPL_MAKE_HOME)/make/Makefile.base

#
# set up the directories
#
GMP_ABS_DIR = $(shell pwd)
GMP_INSTALL_DIR = $(GMP_ABS_DIR)/$(GMP_INSTALL_SUBDIR)
GMP_BUILD_DIR = $(GMP_ABS_DIR)/$(GMP_BUILD_SUBDIR)
GMP_DIR = $(GMP_ABS_DIR)
GMP_UNPACKED_DIR = gmp-$(GMP_VERSION)
GMP_TARBALL = $(GMP_UNPACKED_DIR)a.tar.bz2

ifeq ($(CHPL_MAKE_TARGET_ARCH),knc)
CHPL_GMP_CFG_OPTIONS=--host=x86_64 --disable-assembly
ifeq ($(CHPL_MAKE_TARGET_COMPILER),intel)
CHPL_GMP_CFLAGS=-mmic
CHPL_GMP_CXXFLAGS=-mmic
endif
endif

#
# On Cray systems, building the shared libraries causes issues.
# On Macs, not building the shared libraries causes warnings.
#
ifneq (, $(filter cray-x%,$(CHPL_MAKE_TARGET_PLATFORM)))
CHPL_GMP_CFG_OPTIONS += --enable-static --disable-shared
endif

CHPL_GMP_ABI_ARG =
ifeq (linux32, $(CHPL_MAKE_TARGET_PLATFORM))
CHPL_GMP_ABI_ARG = ABI=32
endif

GMP_MAKEFILE = $(GMP_BUILD_SUBDIR)/Makefile

default: all

all: gmp

clean: FORCE
	rm -rf $(GMP_BUILD_SUBDIR)

cleanall: FORCE
	rm -rf build

clobber: FORCE
	rm -rf build install $(GMP_SUBDIR)

$(GMP_UNPACKED_DIR):
	cd $(GMP_DIR) && tar --bzip2 -xf $(GMP_TARBALL)

$(GMP_BUILD_SUBDIR):
	mkdir -p $@

gmp-config:
	$(MAKE) $(GMP_MAKEFILE)

$(GMP_MAKEFILE): $(GMP_BUILD_SUBDIR) $(GMP_UNPACKED_DIR)
	cd $(GMP_BUILD_DIR) && $(GMP_SUBDIR)/configure CC='$(CC)' CFLAGS='$(CFLAGS) $(CHPL_GMP_CFLAGS)' CXX='$(CXX)' CXXFLAGS='$(CXXFLAGS) $(CHPL_GMP_CXXFLAGS)' $(CHPL_GMP_ABI_ARG) --prefix=$(GMP_INSTALL_DIR) $(CHPL_GMP_CFG_OPTIONS)

gmp-build:
	$(MAKE) $(GMP_H_FILE)

$(GMP_H_FILE): $(GMP_MAKEFILE)
	cd $(GMP_BUILD_DIR) && $(MAKE)
ifneq ($(CHPL_MAKE_TARGET_ARCH),knc)
	cd $(GMP_BUILD_DIR) && $(MAKE) check
endif
	cd $(GMP_BUILD_DIR) && $(MAKE) install

gmp: $(GMP_H_FILE)

FORCE:

.NOTPARALLEL:
