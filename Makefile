# NOTE: GNU Makefile syntax support may be expected by recipe code below.
# This file aims to automate building the FTY dependencies and components
# in correct order. System packaged dependencies are assumed to be present.
# Also note that the default recipes below make an accent on building and
# checking the project code quickly. Unrequired but time-consuming bits,
# such as generation and verification of docs, are skipped.
#
# It supports several actions on components (assumed to exist in same-named
# subdirectories if the workspace root where this Makefile exists), such as
# build/componentname or check/componentname. See the end of this file for
# a list of catch-all rule names.
#
# In addition to that, the Makefile also aids in source code management by
# providing simple rules to sync the current subcomponent workspace to its
# relevant upstream default branch, and to regenerate zproject-based source.
#
# Copyright (C) 2017 by Eaton
# Authors: Jim Klimov <EvgenyKlimov@eaton.com>
#
# POC1 : manual naming and ordering
# POC2 : parse project.xml's to build an included Makefile

# Details defined below
#.PHONY: all install clean
all: build-fty
install: install-fty
uninstall: install-all
clean: clean-all
check: check-all
dist: dist-all
distclean: distclean-all
distcheck: distcheck-all
valgrind: memcheck
memcheck: memcheck-all

experimental: build-fty-experimental
all-experimental: build-fty-experimental

BUILD_OS ?= $(shell uname -s)
BUILD_ARCH ?= $(shell uname -m)
ARCH=$(BUILD_ARCH)
export ARCH

# $(abs_srcdir) defaults to location of this Makefile (and accompanying sources)
# Can override on command-line if needed for any reason, for example
#   cd /tmp/bld-fty && make -f ~/FTY/Makefile abs_srcdir=~/FTY/ all
abs_srcdir:=$(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))
abs_builddir:=$(shell pwd)

# Subdirectory where builds happen (with a sub-dir per component where
# object files and other products are created)
BUILD_OBJ_DIR ?= $(abs_builddir)/.build/$(BUILD_OS)-$(BUILD_ARCH)

# This is the directory under which components' checked-out sources live.
# Initially this is directly where submodules are checked out into, but
# later this can become e.g. a wipable local git clone of those submodules
# to support the multi-host builds from same source checkout (autoreconf
# changes the source tree and so depends on tools available on the host).
BUILD_SRC_DIR ?= $(abs_srcdir)
# This is where real original sources reside (e.g. where to copy from,
# if it comes to that)
ORIGIN_SRC_DIR ?= $(abs_srcdir)

# Root dir where tools are installed into (using their default paths inside)
# We also do use some of those tools (e.g. GSL) during further builds.
# Note that the value of INSTDIR may get compiled into libraries and other
# such stuff, so if you are building just a prototype area for packaging,
# consider setting an explicit PREFIX (not relative to DESTDIR or INSTDIR).
DESTDIR ?=
INSTDIR ?= $(abs_builddir)/.install/$(BUILD_OS)-$(BUILD_ARCH)
# Note: DESTDIR is a common var that is normally added during "make install"
# but in out case this breaks dependencies written into the built libs if
# the build-products are used in-place. INSTDIR is effectively the expected
# run-time root for the built products (so when packaging, use empty INSTDIR
# and a temporary DESTDIR location to trap up the bins, instead).
PREFIX = $(INSTDIR)/usr
PREFIX_ETCDIR = $(INSTDIR)/etc

PATH:=/usr/lib/ccache:$(DESTDIR)$(PREFIX)/libexec/fty:$(DESTDIR)$(PREFIX)/libexec/bios:$(DESTDIR)$(PREFIX)/share/fty/scripts:$(DESTDIR)$(PREFIX)/share/bios/scripts:$(DESTDIR)$(PREFIX)/local/bin:$(DESTDIR)$(PREFIX)/bin:/usr/libexec/fty:/usr/libexec/bios:/usr/share/fty/scripts:/usr/share/bios/scripts:/usr/local/bin:/usr/bin:${PATH}
export PATH
export DESTDIR

# TOOLS used below
MKDIR=/bin/mkdir -p
RMDIR=/bin/rm -rf
RMFILE=/bin/rm -f
TOUCH=/bin/touch
FIND=find
LN=ln
LN_S=$(GNU_LN) -s -f
# GNU ln with relative support
GNU_LN=$(LN)
LN_S_R=$(GNU_LN) -s -f -r
# GNU Make required (overridable via includes below)
GMAKE=make
CC=gcc
CXX=g++
export CC
export CXX

# "ALL" are the components tracked by this makefile, even if not required
# for an FTY build (e.g. gsl and zproject are not an always used codepath)
COMPONENTS_ALL =
# "FTY" are components in "fty-*" submodules and the dependencies they pull
COMPONENTS_FTY =
# "FTY_EXPERIMENTAL" are components in "fty-*" submodules which are not yet
# mainstream (e.g. added recently and builds are expected to fail) and the
# dependencies they pull
COMPONENTS_FTY_EXPERIMENTAL =

# Dependencies on touch-files are calculated by caller
# If the *_sub is called - it must do its work
# Tell GMake to keep any secondary files such as:
# */.prepped */.autogened */.configured */.built */.installed
# NOTE/TODO: Get this to work with explicit list of patterns to filenames
.SECONDARY:
#.PRECIOUS: %/.prep-cloneln-ed %/.prepped %/.autogened %/.configured %/.built %/.installed %/.checked %/.distchecked %/.disted %/.memchecked

# TODO : add a mode to check that a workspace has changed (dev work, git
# checked out another branch, etc.) to trigger rebuilds of a project.
# Otherwise it trusts the .prepped and other state flag-files.
# Maybe find all files newer than exiting .prepped ?

# Note: per http://lists.busybox.net/pipermail/buildroot/2013-May/072556.html
# the autogen, autoreconf and equivalents mangle the source tree
define autogen_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  cd "$(BUILD_SRC_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    ( if [ -x ./autogen.sh ]; then \
	        ./autogen.sh  || exit ; \
	      elif [ -x ./buildconf ]; then \
	        ./buildconf || exit ; \
	      else \
	        autoreconf -fiv || exit ; \
	      fi ) && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)"/.autogened || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)"/.autogen-failed ; exit 1; } \
	)
endef

# Note: this requires that "configure" has already been created in the sources
# If custom "CONFIG_OPTS_$(1)" were defined, they are appended to configuration
define configure_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	    "$(BUILD_SRC_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))/configure" $(CONFIG_OPTS) $(CONFIG_OPTS_$(1)) && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".configured || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".configure-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
define build_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	    $(GMAKE) $(MAKE_COMMON_ARGS_$(1)) $(MAKE_ALL_ARGS_$(1)) all && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".built || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".build-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
define install_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	    $(GMAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) install && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".installed || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".install-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
define check_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	    $(GMAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) check && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".checked || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".check-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
# Unfortunately, one may have to be careful about passing CONFIG_OPTS
# values with spaces; note that values inside CONFIG_OPTS may be quoted.
# Also it seems that both envvar and makefile-arg settings are needed :\
#	    DISTCHECK_CONFIGURE_FLAGS='$(CONFIG_OPTS) $(CONFIG_OPTS_$(1))' 
define distcheck_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	    $(GMAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) \
		DISTCHECK_CONFIGURE_FLAGS='$(CONFIG_OPTS) $(CONFIG_OPTS_$(1))' \
		distcheck && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".distchecked || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".distcheck-failed ; exit 1; } \
	)
endef

define dist_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	    $(GMAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) dist && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".disted || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".dist-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
define memcheck_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	    $(GMAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) memcheck && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".memchecked || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".memcheck-failed ; exit 1; } \
	)
endef

define uninstall_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  $(RM) "$(BUILD_OBJ_DIR)/$(1)/".installed "$(BUILD_OBJ_DIR)/$(1)/".install-failed && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	    CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	    $(GMAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) uninstall \
	)
endef

# This clones directory $1 into $2 recursively, making real new dirs
# and populating with (relative) symlinks to original data.
# For safety, use absolute paths...
define clone_ln
	( $(RMDIR) "$(2)" && $(MKDIR) "$(2)" && \
	  SRC="`cd "$(1)" && pwd`" && DST="`cd "$(2)" && pwd`" && \
	  cd "$$SRC" && \
	    $(FIND) . -type d -exec $(MKDIR) "$$DST"/'{}' \; && \
	    $(FIND) . \! -type d -exec $(LN_S_R) "$$SRC"/'{}' "$$DST"/'{}' \; \
	)
endef

# Reports a no-op for certain recipes
define echo_noop
	( echo "  NOOP    Generally recipe for $@ has nothing to do" ; $(TOUCH) $@ )
endef

CFLAGS ?=
CPPFLAGS ?=
CXXFLAGS ?=
LDFLAGS ?=

CFLAGS += -I$(DESTDIR)$(PREFIX)/include
CPPFLAGS += -I$(DESTDIR)$(PREFIX)/include
CXXFLAGS += -I$(DESTDIR)$(PREFIX)/include
LDFLAGS += -L$(DESTDIR)$(PREFIX)/lib

PKG_CONFIG_PATH ?= "$(DESTDIR)$(PREFIX)/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/pkgconfig:/lib/pkgconfig"
export PKG_CONFIG_PATH

CONFIG_OPTS  = --prefix="$(PREFIX)"
CONFIG_OPTS += --sysconfdir="$(DESTDIR)$(PREFIX_ETCDIR)"
CONFIG_OPTS += LDFLAGS="$(LDFLAGS)"
CONFIG_OPTS += CFLAGS="$(CFLAGS)"
CONFIG_OPTS += CXXFLAGS="$(CXXFLAGS)"
CONFIG_OPTS += CPPFLAGS="$(CPPFLAGS)"
CONFIG_OPTS += PKG_CONFIG_PATH="$(PKG_CONFIG_PATH)"
CONFIG_OPTS += --with-pkgconfdir="$(DESTDIR)$(PREFIX)/lib/pkgconfig"
CONFIG_OPTS += --with-docs=no --without-docs
CONFIG_OPTS += --with-systemdtmpfilesdir="$(DESTDIR)$(PREFIX)/lib/tmpfiles.d"
CONFIG_OPTS += --with-systemdsystempresetdir="$(DESTDIR)$(PREFIX)/lib/systemd/system-preset"
CONFIG_OPTS += --with-systemdsystemunitdir="$(DESTDIR)$(PREFIX)/lib/systemd/system"
CONFIG_OPTS += --quiet
# For projects from around the zeromq community, use stable APIs
CONFIG_OPTS += --enable-drafts=no

# optional overrides of config above, etc.
sinclude Makefile-local.mk
sinclude Makefile-local-$(BUILD_OS).mk
sinclude Makefile-local-$(BUILD_OS)-$(BUILD_ARCH).mk

# Catch empty expansions
$(BUILD_OBJ_DIR)//.prep-cloneln-ed $(BUILD_OBJ_DIR)//.prepped $(BUILD_OBJ_DIR)//.autogened $(BUILD_OBJ_DIR)//.configured $(BUILD_OBJ_DIR)//.built $(BUILD_OBJ_DIR)//.installed $(BUILD_OBJ_DIR)//.checked $(BUILD_OBJ_DIR)//.distchecked $(BUILD_OBJ_DIR)//.disted $(BUILD_OBJ_DIR)//.memchecked:
	@echo "Error in recipe expansion, can not build $@ : component part is empty" ; exit 1

########################### GSL and LIBCIDR ###############################
# This is built in-tree, and without autoconf, so is trickier to handle
COMPONENTS_ALL += gsl
BUILD_SUB_DIR_gsl=src/
MAKE_COMMON_ARGS_gsl=DESTDIR="$(DESTDIR)$(PREFIX)/local"

$(BUILD_OBJ_DIR)/%/.prep-cloneln-ed: $(abs_srcdir)/.git/modules/%/HEAD
	@if test ! -s "$@" || ! diff "$@" "$<" > /dev/null 2>&1 ; then \
	 $(call clone_ln,$(ORIGIN_SRC_DIR)/$(notdir $(@D)),$(BUILD_OBJ_DIR)/$(notdir $(@D))) ; \
	 fi
	@cat $< > $@

$(BUILD_OBJ_DIR)/gsl/.prepped: $(BUILD_OBJ_DIR)/gsl/.prep-cloneln-ed
	@$(TOUCH) $@

# These are no-ops for GSL:
$(BUILD_OBJ_DIR)/gsl/.autogened: $(BUILD_OBJ_DIR)/gsl/.prepped
	@$(call echo_noop,$@)

$(BUILD_OBJ_DIR)/gsl/.configured: $(BUILD_OBJ_DIR)/gsl/.autogened
	@$(call echo_noop,$@)

$(BUILD_OBJ_DIR)/gsl/.checked $(BUILD_OBJ_DIR)/gsl/.distchecked $(BUILD_OBJ_DIR)/gsl/.memchecked $(BUILD_OBJ_DIR)/gsl/.disted: $(BUILD_OBJ_DIR)/gsl/.built
	@$(call echo_noop,$@)

$(BUILD_OBJ_DIR)/gsl/.built: BUILD_SRC_DIR=$(BUILD_OBJ_DIR)
$(BUILD_OBJ_DIR)/gsl/.installed: BUILD_SRC_DIR=$(BUILD_OBJ_DIR)

### Rinse and repeat for libcidr, but there's less to customize
COMPONENTS_FTY += libcidr
# With the weird build system that libcidr uses, we'd better hide from it
# that it is in a sub-make - or it goes crazy trying to communicate back
MAKE_COMMON_ARGS_libcidr = MAKELEVEL="" MAKEFLAGS="" -j1

$(BUILD_OBJ_DIR)/libcidr/.prepped: $(BUILD_OBJ_DIR)/libcidr/.prep-cloneln-ed
	@$(TOUCH) $@

$(BUILD_OBJ_DIR)/libcidr/.autogened: $(BUILD_OBJ_DIR)/libcidr/.prepped
	@$(call echo_noop,$@)

$(BUILD_OBJ_DIR)/libcidr/.built: BUILD_SRC_DIR=$(BUILD_OBJ_DIR)
$(BUILD_OBJ_DIR)/libcidr/.installed: BUILD_SRC_DIR=$(BUILD_OBJ_DIR)

$(BUILD_OBJ_DIR)/libcidr/.checked $(BUILD_OBJ_DIR)/libcidr/.distchecked $(BUILD_OBJ_DIR)/libcidr/.memchecked $(BUILD_OBJ_DIR)/libcidr/.disted: $(BUILD_OBJ_DIR)/libcidr/.built
	@$(call echo_noop,$@)

######################## Other components ##################################
# Note: for rebuilds with a ccache in place, the biggest time-consumers are
# recreation of configure script (autogen or autoreconf) and running it.
# Documentation processing can also take a while, but it is off by default.
# So to take advantage of parallelization we define dependencies from the
# earliest stage a build pipeline might have.

COMPONENTS_ALL += zproject
$(BUILD_OBJ_DIR)/zproject/.autogened: $(BUILD_OBJ_DIR)/gsl/.installed

$(BUILD_OBJ_DIR)/zproject/.checked $(BUILD_OBJ_DIR)/zproject/.distchecked $(BUILD_OBJ_DIR)/zproject/.memchecked: $(BUILD_OBJ_DIR)/zproject/.built
	@$(call echo_noop,$@)

COMPONENTS_FTY += cxxtools
MAKE_COMMON_ARGS_cxxtools=-j1

$(BUILD_OBJ_DIR)/cxxtools/.prepped: $(BUILD_OBJ_DIR)/cxxtools/.prep-cloneln-ed
	@$(TOUCH) $@

$(BUILD_OBJ_DIR)/cxxtools/.memchecked: $(BUILD_OBJ_DIR)/cxxtools/.built
	@$(call echo_noop,$@)

# This requires dev packages (or equivalent) of mysql/mariadb
# Make sure the workspace is (based on) branch "1.3"
COMPONENTS_FTY += tntdb
MAKE_COMMON_ARGS_tntdb=-j1
BUILD_SUB_DIR_tntdb=tntdb/
CONFIG_OPTS_tntdb ?= --without-postgresql
CONFIG_OPTS_tntdb += --without-sqlite
$(BUILD_OBJ_DIR)/tntdb/.configured: $(BUILD_OBJ_DIR)/cxxtools/.installed
$(BUILD_OBJ_DIR)/tntdb/.memchecked: $(BUILD_OBJ_DIR)/tntdb/.built
	@$(call echo_noop,$@)

### We do not link to this(???) - just use at runtime
# Make sure the workspace is (based on) branch "2.2"
COMPONENTS_FTY += tntnet
CONFIG_OPTS_tntnet ?= --with-sdk
CONFIG_OPTS_tntnet += --without-demos
$(BUILD_OBJ_DIR)/tntnet/.configured: $(BUILD_OBJ_DIR)/cxxtools/.installed
$(BUILD_OBJ_DIR)/tntnet/.memchecked: $(BUILD_OBJ_DIR)/tntnet/.built
	@$(call echo_noop,$@)

COMPONENTS_FTY += libmagic
$(BUILD_OBJ_DIR)/libmagic/.memchecked: $(BUILD_OBJ_DIR)/libmagic/.built
	@$(call echo_noop,$@)

COMPONENTS_FTY += libsodium
$(BUILD_OBJ_DIR)/libsodium/.memchecked: $(BUILD_OBJ_DIR)/libsodium/.built
	@$(call echo_noop,$@)

COMPONENTS_FTY += libzmq
$(BUILD_OBJ_DIR)/libzmq/.configured: $(BUILD_OBJ_DIR)/libsodium/.installed
# TODO: It was called "make check-valgrind-memcheck" back then
$(BUILD_OBJ_DIR)/libzmq/.memchecked: $(BUILD_OBJ_DIR)/libzmq/.built
	@$(call echo_noop,$@)

COMPONENTS_FTY += czmq
CONFIG_OPTS_czmq ?= CFLAGS="$(CFLAGS) -Wno-deprecated-declarations"
CONFIG_OPTS_czmq += CXXFLAGS="$(CXXFLAGS) -Wno-deprecated-declarations"
CONFIG_OPTS_czmq += CPPFLAGS="$(CPPFLAGS) -Wno-deprecated-declarations"
# Make sure the workspace is (based on) branch "v3.0.2" at this time
# That version of autogen.sh requires a "libtool" while debian has only "libtoolize", so fall back
$(BUILD_OBJ_DIR)/czmq/.autogened: $(BUILD_OBJ_DIR)/czmq/.prepped
	$(call autogen_sub,$(notdir $(@D))) || \
	 ( cd "$(BUILD_SRC_DIR)/$(notdir $(@D))/$(BUILD_SUB_DIR_$(notdir $(@D)))" && autoreconf -fiv )
	$(TOUCH) $@

$(BUILD_OBJ_DIR)/czmq/.configured: $(BUILD_OBJ_DIR)/libzmq/.installed

COMPONENTS_FTY += malamute
$(BUILD_OBJ_DIR)/malamute/.configured: $(BUILD_OBJ_DIR)/czmq/.installed $(BUILD_OBJ_DIR)/libsodium/.installed

COMPONENTS_FTY += nut
CONFIG_OPTS_nut ?= --with-doc=skip
CONFIG_OPTS_nut += --with-dev
CONFIG_OPTS_nut += --with-dmf
CONFIG_OPTS_nut += --with-libltdl
CONFIG_OPTS_nut += --with-augeas-lenses-dir="$(DESTDIR)$(PREFIX)/share/augeas/lenses/dist"
#CONFIG_OPTS_nut += --sysconfdir="$(DESTDIR)$(PREFIX_ETCDIR)/nut"
CONFIG_OPTS_nut += --with-udev-dir="$(DESTDIR)$(PREFIX_ETCDIR)/udev"
CONFIG_OPTS_nut += --with-devd-dir="$(DESTDIR)$(PREFIX_ETCDIR)/devd"
CONFIG_OPTS_nut += --with-hotplug-dir="$(DESTDIR)$(PREFIX_ETCDIR)/hotplug"

COMPONENTS_FTY += fty-proto
$(BUILD_OBJ_DIR)/fty-proto/.configured: $(BUILD_OBJ_DIR)/malamute/.installed $(BUILD_OBJ_DIR)/libsodium/.installed
# $(BUILD_OBJ_DIR)/cxxtools/.installed

# Note: more and more core is a collection of scripts, so should need less deps
COMPONENTS_FTY += fty-core
$(BUILD_OBJ_DIR)/fty-core/.configured: $(BUILD_OBJ_DIR)/malamute/.installed $(BUILD_OBJ_DIR)/tntdb/.installed $(BUILD_OBJ_DIR)/tntnet/.installed $(BUILD_OBJ_DIR)/libcidr/.installed
$(BUILD_OBJ_DIR)/fty-core/.memchecked: $(BUILD_OBJ_DIR)/fty-core/.built
	@$(call echo_noop,$@)

COMPONENTS_FTY += fty-rest
$(BUILD_OBJ_DIR)/fty-rest/.configured: $(BUILD_OBJ_DIR)/malamute/.installed $(BUILD_OBJ_DIR)/tntdb/.installed $(BUILD_OBJ_DIR)/tntnet/.installed $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/fty-core/.installed $(BUILD_OBJ_DIR)/libcidr/.installed $(BUILD_OBJ_DIR)/libmagic/.installed

COMPONENTS_FTY += fty-nut
$(BUILD_OBJ_DIR)/fty-nut/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/libcidr/.installed $(BUILD_OBJ_DIR)/cxxtools/.installed $(BUILD_OBJ_DIR)/nut/.installed

COMPONENTS_FTY += fty-asset
$(BUILD_OBJ_DIR)/fty-asset/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/tntdb/.installed $(BUILD_OBJ_DIR)/cxxtools/.installed $(BUILD_OBJ_DIR)/libmagic/.installed

COMPONENTS_FTY += fty-metric-tpower
$(BUILD_OBJ_DIR)/fty-metric-tpower/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/tntdb/.installed $(BUILD_OBJ_DIR)/cxxtools/.installed

COMPONENTS_FTY += fty-metric-store
$(BUILD_OBJ_DIR)/fty-metric-store/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/tntdb/.installed $(BUILD_OBJ_DIR)/cxxtools/.installed

COMPONENTS_FTY += fty-metric-composite
$(BUILD_OBJ_DIR)/fty-metric-composite/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/cxxtools/.installed

COMPONENTS_FTY += fty-email
$(BUILD_OBJ_DIR)/fty-email/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/cxxtools/.installed $(BUILD_OBJ_DIR)/libmagic/.installed

COMPONENTS_FTY += fty-alert-engine
$(BUILD_OBJ_DIR)/fty-alert-engine/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/cxxtools/.installed

COMPONENTS_FTY += fty-alert-list
$(BUILD_OBJ_DIR)/fty-alert-list/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

COMPONENTS_FTY += fty-kpi-power-uptime
$(BUILD_OBJ_DIR)/fty-kpi-power-uptime/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

COMPONENTS_FTY += fty-metric-cache
$(BUILD_OBJ_DIR)/fty-metric-cache/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

COMPONENTS_FTY += fty-metric-compute
$(BUILD_OBJ_DIR)/fty-metric-compute/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

COMPONENTS_FTY += fty-outage
$(BUILD_OBJ_DIR)/fty-outage/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

COMPONENTS_FTY += fty-sensor-env
$(BUILD_OBJ_DIR)/fty-sensor-env/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

COMPONENTS_FTY += fty-example
$(BUILD_OBJ_DIR)/fty-example/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

### Note: The following components are experimental recent additions,
### and in their current state they break FTY builds (and they do not
### yet do anything useful). So while this Makefile supports a basic
### config for them, it does not count them as part of the team yet.
### Not built by default... but if we do - it's covered
COMPONENTS_FTY_EXPERIMENTAL += fty-metric-snmp
$(BUILD_OBJ_DIR)/fty-metric-snmp/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

COMPONENTS_FTY_EXPERIMENTAL += fty-alert-flexible
$(BUILD_OBJ_DIR)/fty-alert-flexible/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed

COMPONENTS_FTY_EXPERIMENTAL += fty-info
$(BUILD_OBJ_DIR)/fty-info/.configured: $(BUILD_OBJ_DIR)/fty-proto/.installed $(BUILD_OBJ_DIR)/cxxtools/.installed $(BUILD_OBJ_DIR)/tntdb/.installed

COMPONENTS_ALL += $(COMPONENTS_FTY)

############################# Common route ##################################
# The prep step handles preparation of source directory (unpack, patch etc.)
# At a later stage this cound "git clone" a workspace for host-arch build

# This is no-op for most of our components
# TODO1: replicate the source directory via symlinks to mangle with autogen etc
# TODO2: somehow depend on timestamps of ALL source files and/or git metadata

$(BUILD_OBJ_DIR)/%/.prepped: $(abs_srcdir)/.git/modules/%/HEAD
	@$(MKDIR) $(@D)
	@if test ! -s "$@" || ! diff "$@" "$<" > /dev/null 2>&1 ; then \
	  if [ -f "$(@D)/.installed" ] || [ -f "$(@D)/.install-failed" ] ; then \
	    $(call uninstall_sub,$(notdir $(@D))) ; else true ; \
	  fi; \
	 fi
	@cat $< > $@

$(BUILD_OBJ_DIR)/%/.autogened: $(BUILD_OBJ_DIR)/%/.prepped
	$(call autogen_sub,$(notdir $(@D)))

$(BUILD_OBJ_DIR)/%/.configured: $(BUILD_OBJ_DIR)/%/.autogened
	$(call configure_sub,$(notdir $(@D)))

$(BUILD_OBJ_DIR)/%/.built: $(BUILD_OBJ_DIR)/%/.configured
	$(call build_sub,$(notdir $(@D)))

$(BUILD_OBJ_DIR)/%/.disted: $(BUILD_OBJ_DIR)/%/.configured
	$(call dist_sub,$(notdir $(@D)))

# Technically, build and install may pursue different targets
# so maybe this should depend on just .configured
$(BUILD_OBJ_DIR)/%/.installed: $(BUILD_OBJ_DIR)/%/.built
	$(call install_sub,$(notdir $(@D)))

$(BUILD_OBJ_DIR)/%/.checked: $(BUILD_OBJ_DIR)/%/.built
	$(call check_sub,$(notdir $(@D)))

$(BUILD_OBJ_DIR)/%/.distchecked: $(BUILD_OBJ_DIR)/%/.built
	$(call distcheck_sub,$(notdir $(@D)))

$(BUILD_OBJ_DIR)/%/.memchecked: $(BUILD_OBJ_DIR)/%/.built
	$(call memcheck_sub,$(notdir $(@D)))

# Phony targets to make or clean up a build of components
# Also note rules must be not empty to actually run something
# NOTE: The use of $(@F) in the rules assumes submodules are not nested
#       otherwise text conversions are needed to chomp until first slash
clean-obj/%:
	if [ "$(BUILD_OBJ_DIR)" != "$(ORIGIN_SRC_DIR)" ]; then\
	    chmod -R u+w $(BUILD_OBJ_DIR)/$(@F) || true; \
	    $(RMDIR) $(BUILD_OBJ_DIR)/$(@F); \
	fi

clean-src/gsl clean-src/libcidr clean-src/cxxtools:
	if [ "$(BUILD_OBJ_DIR)" != "$(ORIGIN_SRC_DIR)" ]; then\
	    chmod -R u+w $(BUILD_OBJ_DIR)/$(@F) || true; \
	    $(RMDIR) $(BUILD_OBJ_DIR)/$(@F); \
	fi

clean-src/%:
	@if [ "$(BUILD_SRC_DIR)" != "$(ORIGIN_SRC_DIR)" ]; then \
	    chmod -R u+w $(BUILD_SRC_DIR)/$(@F) || true; \
	    $(RMDIR) $(BUILD_SRC_DIR)/$(@F); \
	else \
	    echo "  NOOP    Generally $@ has nothing to do for now"; \
	fi

distclean/% clean/%:
	$(GMAKE) clean-obj/$(@F)
	$(GMAKE) clean-src/$(@F)

prep/%: $(BUILD_OBJ_DIR)/%/.prepped
	@true

autogen/%: $(BUILD_OBJ_DIR)/%/.autogened
	@true

configure/%: $(BUILD_OBJ_DIR)/%/.configured
	@true

build/%: $(BUILD_OBJ_DIR)/%/.built
	@true

install/%: $(BUILD_OBJ_DIR)/%/.installed
	@true

check/%: $(BUILD_OBJ_DIR)/%/.checked
	@true

distcheck/%: $(BUILD_OBJ_DIR)/%/.distchecked
	@true

dist/%: $(BUILD_OBJ_DIR)/%/.disted
	@true

valgrind/% memcheck/%: $(BUILD_OBJ_DIR)/%/.memchecked
	@true

assume/%:
	@echo "ASSUMING that $(@F) is available through means other than building from sources"
	@$(MKDIR) $(BUILD_OBJ_DIR)/$(@F)
	@$(TOUCH) $(BUILD_OBJ_DIR)/$(@F)/.installed

nowarn/%:
	$(GMAKE) clean/$(@F)
	$(GMAKE) CFLAGS="$(CFLAGS) -Wall -Werror" CPPFLAGS="$(CPPFLAGS) -Wall -Werror" CXXFLAGS="$(CXXFLAGS) -Wall -Werror" $(BUILD_OBJ_DIR)/$(@F)/.built

rebuild/%:
	$(GMAKE) clean/$(@F)
	$(GMAKE) $(BUILD_OBJ_DIR)/$(@F)/.built

recheck/%:
	$(GMAKE) clean/$(@F)
	$(GMAKE) $(BUILD_OBJ_DIR)/$(@F)/.checked

redistcheck/%:
	$(GMAKE) clean/$(@F)
	$(GMAKE) $(BUILD_OBJ_DIR)/$(@F)/.distchecked

reinstall/%:
	$(GMAKE) uninstall/$(@F)
	$(GMAKE) clean/$(@F)
	$(GMAKE) $(BUILD_OBJ_DIR)/$(@F)/.installed

### Use currently developed zproject to regenerate a project
regenerate/%: $(BUILD_OBJ_DIR)/zproject/.installed
	( cd "$(abs_srcdir)/$(@F)" && gsl project.xml && ./autogen.sh && git difftool -y )

### Resync current checkout to upstream/master
### The "auto" mode is intended for rebuilds, so it quietly
### follows the configured default branch. Simple "git-resync"
### stays in developer's current branch and merges it with
### changes trickling down from upstream default branch.
git-resync/% git-resync-auto/%:
	@( BASEBRANCH="`git config -f $(abs_srcdir)/.gitmodules submodule.$(@F).branch`" || BASEBRANCH="" ; \
	  test -n "$$BASEBRANCH" || BASEBRANCH=master ; \
	  cd "$(abs_srcdir)/$(@F)" && \
	    { git remote -v | grep upstream && BASEREPO="upstream" || BASEREPO="origin" ; } && \
	    case "$@" in \
	      *git-resync-auto/*) git checkout -f "$$BASEBRANCH" ;; \
	      *) true ;; \
	    esac && \
	    git pull --all && \
	    git merge "$$BASEREPO/$$BASEBRANCH" && \
	    case "$@" in \
	      *git-resync-auto/*) true ;; \
	      *) git rebase -i "$$BASEREPO/$$BASEBRANCH" ;; \
	    esac; \
	)

# Note this one would trigger a (re)build run
uninstall/%: $(BUILD_OBJ_DIR)/%/.configured
	$(call uninstall_sub,$(@F))

# Rule-them-all rules! e.g. build-all install-all uninstall-all clean-all
rebuild-all:
	$(GMAKE) $(addprefix clean/,$(COMPONENTS_ALL))
	$(GMAKE) $(addprefix build/,$(COMPONENTS_ALL))

rebuild-fty:
	$(GMAKE) $(addprefix clean/,$(COMPONENTS_FTY))
	$(GMAKE) $(addprefix build/,$(COMPONENTS_FTY))

rebuild-fty-experimental:
	$(GMAKE) $(addprefix clean/,$(COMPONENTS_FTY_EXPERIMENTAL))
	$(GMAKE) $(addprefix build/,$(COMPONENTS_FTY_EXPERIMENTAL))

reinstall-all:
	$(GMAKE) $(addprefix clean/,$(COMPONENTS_ALL))
	$(GMAKE) $(addprefix install/,$(COMPONENTS_ALL))

reinstall-fty:
	$(GMAKE) $(addprefix clean/,$(COMPONENTS_FTY))
	$(GMAKE) $(addprefix install/,$(COMPONENTS_FTY))

reinstall-fty-experimental:
	$(GMAKE) $(addprefix clean/,$(COMPONENTS_FTY_EXPERIMENTAL))
	$(GMAKE) $(addprefix install/,$(COMPONENTS_FTY_EXPERIMENTAL))

%-all: $(addprefix %/,$(COMPONENTS_ALL))
	@echo "COMPLETED $@ : made '$^'"

%-fty: $(addprefix %/,$(COMPONENTS_FTY))
	@echo "COMPLETED $@ : made '$^'"

%-fty-experimental: $(addprefix %/,$(COMPONENTS_FTY_EXPERIMENTAL))
	@echo "COMPLETED $@ : made '$^'"

# Speak BSDisch?
emerge: git-resync-auto-all
	@echo "COMPLETED $@ : made '$^'"

world:
	$(GMAKE) emerge
	$(GMAKE) install-all install-fty-experimental
