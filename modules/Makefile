# Copyright 2004-2014 Cray Inc.
# Other additional copyright holders may be indicated within.
# 
# The entirety of this work is licensed under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# 
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ifndef CHPL_MAKE_HOME
export CHPL_MAKE_HOME=$(shell pwd)/..
endif

CHPL_MAKE_HOST_TARGET = --target
include $(CHPL_MAKE_HOME)/make/Makefile.base

SYS_MODULES_DIR=standard/gen/$(CHPL_MAKE_PLATFORM)-$(CHPL_MAKE_COMPILER)

SYS_CTYPES_MODULE=$(SYS_MODULES_DIR)/SysCTypes.chpl

default: all

all: $(SYS_CTYPES_MODULE)

clean: FORCE

cleanall: FORCE

clobber: FORCE
	rm -rf standard/gen

depend:

MAKE_SYS_BASIC_TYPES=$(CHPL_MAKE_HOME)/util/config/makeSysBasicTypes

$(SYS_CTYPES_MODULE): $(MAKE_SYS_BASIC_TYPES)
	mkdir -p $(@D)
# When makeSysBasicTypes call fails, delete the SysCTypes.chpl file that is
# created, but still make sure the command fails.
	cd $(@D) && ( $(MAKE_SYS_BASIC_TYPES) > $(@F) || { rm -f $(@F) && false ; } )

FORCE:

