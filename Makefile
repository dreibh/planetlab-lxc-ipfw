# $Id: Makefile 8654 2011-05-23 08:39:50Z marta $
#
# Top level makefile for building ipfw kernel and userspace.
# You can run it manually or also under the Planetlab build.
# Planetlab wants also the 'install' target.
#
# To build on system with non standard Kernel sources or userland files,
# you should run this with
#
#	make KERNELPATH=/path/to/linux-2.x.y.z USRDIR=/path/to/usr
#
# We assume that $(USRDIR) contains include/ and lib/ used to build userland.

DATE ?= $(shell date +%Y%m%d)
SNAPSHOT_NAME=$(DATE)-ipfw3.tgz
BINDIST=$(DATE)-dummynet-linux.tgz
WINDIST=$(DATE)-dummynet-windows.zip

###########################################
#  windows x86 and x64 specific variables #
###########################################
#  DRIVE must be the hard drive letter where DDK is installed
#  DDKDIR must be the path to the DDK root directory, without drive letter
#  TARGETOS (x64 only) must be one of the following:
#  wnet   -> windows server 2003
#  wlh    -> windows vista and windows server 2008
#  win7   -> windows 7
#  future version must be added here
export DDK
export DRIVE
export DDKDIR
DRIVE = C:
DDKDIR = /WinDDK/7600.16385.1
DDK = $(DRIVE)$(DDKDIR)

TARGETOS=win7

_all: all

clean distclean:
	echo target is $(@)
	(cd ipfw && $(MAKE) $(@) )
	(cd dummynet2 && $(MAKE) $(@) )
	# -- windows x64 only
	- rm -rf dummynet2-64
	- rm -rf ipfw-64
	- rm -rf binary64

all:
	echo target is $(@)
	(cd ipfw && $(MAKE) $(@) )
	(cd dummynet2 && $(MAKE) $(@) )
	# -- windows only
	- [ -f ipfw/ipfw.exe ] && cp ipfw/ipfw.exe binary/ipfw.exe
	- [ -f dummynet2/objchk_wxp_x86/i386/ipfw.sys ] && \
		cp dummynet2/objchk_wxp_x86/i386/ipfw.sys binary/ipfw.sys

snapshot:
	$(MAKE) distclean
	(cd ..; tar cvzhf /tmp/$(SNAPSHOT_NAME) --exclude .svn \
		--exclude README.openwrt --exclude tags --exclude NOTES \
		--exclude tcc-0.9.25-bsd \
		--exclude original_passthru \
		--exclude ipfw3.diff --exclude add_rules \
		--exclude test --exclude test_ \
		ipfw3 )

bindist:
	$(MAKE) clean
	$(MAKE) all
	tar cvzf /tmp/$(BINDIST) ipfw/ipfw ipfw/ipfw.8 dummynet2/ipfw_mod.ko

windist:
	$(MAKE) clean
	-$(MAKE) all
	-rm /tmp/$(WINDIST)
	zip -r /tmp/$(WINDIST) binary -x \*.svn\*

win64:	clean
	(cd dummynet2 && $(MAKE) include_e)
	cp -r ipfw ipfw-64
	echo "EXTRA_CFLAGS += -D_X64EMU" >> ipfw-64/Makefile
	(cd ipfw-64 && $(MAKE) all)
	cp -r dummynet2 dummynet2-64
	rm -f dummynet2-64/Makefile
	cp win64/sources dummynet2-64/sources
	mkdir dummynet2-64/tmpbuild
	mkdir binary64
	win64/mysetenv.sh $(DRIVE) $(DDKDIR) $(TARGETOS)
	cp binary/cygwin1.dll binary64/cygwin1.dll
	cp ipfw-64/ipfw.exe binary64/ipfw.exe
	cp win64/*.inf binary64
	cp binary/testme.bat binary64/testme.bat
	cp binary/wget.exe binary64/wget.exe
	
planetlab_update:
	# clean and create a local working directory
	rm -rf /tmp/pl-tmp
	mkdir -p /tmp/pl-tmp/pl
	mkdir -p /tmp/pl-tmp/ol2
	# get the trunk version of the PlanetLab repository
	# to specify the sshkey use the .ssh/config file
	(cd /tmp/pl-tmp/pl; \
		svn co svn+ssh://svn.planet-lab.org/svn/ipfw/trunk)
	# get an updated copy of the main ipfw repository
	(cd /tmp/pl-tmp/ol2; \
		svn export svn+ssh://onelab2.iet.unipi.it/home/svn/ports-luigi/dummynet-branches/ipfw3)
	# copy the new version over the old one
	(cd /tmp/pl-tmp; cp -rP ol2/ipfw3/* pl/trunk)
	# files cleanup in the old version
	(cd /tmp/pl-tmp; diff -r ol2/ipfw3 pl/trunk | \
		grep -v "svn" | awk '{print $$3 $$4}' | \
		sed 's/:/\//' | xargs rm -rf)
	# local adjustmens here
	rm -rf /tmp/pl-tmp/pl/trunk/planetlab/check_planetlab_sync
	# commit to the remote repo
	@echo "Please, revise the update with the commands:"
	@echo "(cd /tmp/pl-tmp/pl/trunk; svn diff)"
	@echo "(cd /tmp/pl-tmp/pl/trunk; svn status)"
	@echo "and commit with:"
	@echo "(cd /tmp/pl-tmp/pl/trunk; svn ci -m 'Update from the mail ipfw repo.')"

openwrt_release:
	# create a temporary directory
	$(eval TMPDIR := $(shell mktemp -d -p /tmp/ ipfw3_openwrt_XXXXX))
	# create the source destination directory
	$(eval IPFWDIR := ipfw3-$(DATE))
	$(eval DSTDIR := $(TMPDIR)/$(IPFWDIR))
	mkdir $(DSTDIR)
	# copy the package, clean objects and svn info
	cp -r ./ipfw ./dummynet2 glue.h Makefile ./configuration README $(DSTDIR)
	(cd $(DSTDIR); make -s distclean; find . -name .svn | xargs rm -rf)
	(cd $(TMPDIR); tar czf $(IPFWDIR).tar.gz $(IPFWDIR))

	# create the port files in /tmp/ipfw3-port
	$(eval PORTDIR := $(TMPDIR)/ipfw3)
	mkdir -p $(PORTDIR)/patches
	# generate the Makefile, PKG_VERSION and PKG_MD5SUM
	md5sum $(DSTDIR).tar.gz | cut -d ' ' -f 1 > $(TMPDIR)/md5sum
	cat ./OPENWRT/Makefile | \
		sed s/PKG_VERSION:=/PKG_VERSION:=$(DATE)/ | \
		sed s/PKG_MD5SUM:=/PKG_MD5SUM:=`cat $(TMPDIR)/md5sum`/ \
		> $(PORTDIR)/Makefile

	@echo ""
	@echo "The openwrt port is in $(TMPDIR)/ipfw3-port"
	@echo "The source file should be copied to the public server:"
	@echo "scp $(DSTDIR).tar.gz marta@info.iet.unipi.it:~marta/public_html/dummynet"
	@echo "after this the temporary directory $(TMPDIR) can be removed."

install:
