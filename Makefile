#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#  to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

export PATH := $(PATH):/usr/local/bin

CPANM = cpanm

SUDO := sudo
SUDO_PIP := sudo -H
SUDO_PERL := sudo

ifdef PERLBREW_PERL
	# can't put this here otherwise gets error - "commands commence before first target.  Stop."
	#@echo "Perlbrew environment detected, not calling sudo"
	SUDO_PERL =
endif

# Travis has custom python install earlier in $PATH even in Perl builds so need to install PyPI modules locally to non-system python otherwise they're not found by programs.
# Perms not set correctly on custom python install in Travis perl build so workaround is done to chown to travis user in .travis.yml
# Better than modifying $PATH to put /usr/bin first which is likely to affect many other things including potentially not finding the perlbrew installation first
# Looks like Perl travis builds are now using system Python - do not use TRAVIS env
ifdef VIRTUAL_ENV
	#@echo "Virtual Env / Conda detected, not calling sudo"
	SUDO_PIP :=
endif
ifdef CONDA_DEFAULT_ENV
	SUDO_PIP :=
endif

# must come after to reset SUDO_PERL/SUDO_PIP to blank if root
# EUID /  UID not exported in Make
# USER not populated in Docker
ifeq '$(shell id -u)' '0'
	#@echo "root UID detected, not calling sudo"
	SUDO :=
	SUDO_PERL :=
	SUDO_PIP :=
endif

# ===================
# bootstrap commands:

# Alpine:
#
#   apk add --no-cache git make && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make

# Debian / Ubuntu:
#
#   apt-get update && apt-get install -y make git && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make

# RHEL / CentOS:
#
#   yum install -y make git && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make

# ===================

.PHONY: build
# space here prevents weird validation warning from check_makefile.sh => Makefile:40: warning: undefined variable `D'
build :
	@echo ====================
	@echo Nagios Plugins Build
	@echo ====================

	$(MAKE) common
	$(MAKE) perl-libs
	$(MAKE) python-libs
	@echo
	#$(MAKE) jar-plugins
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins)"

.PHONY: quick
quick:
	QUICK=1 $(MAKE) build

.PHONY: common
common: system-packages submodules
	:

.PHONY: submodules
submodules:
	git submodule init
	git submodule update --recursive

.PHONY: system-packages
system-packages:
	if [ -x /sbin/apk ];        then $(MAKE) apk-packages; fi
	if [ -x /usr/bin/apt-get ]; then $(MAKE) apt-packages; fi
	if [ -x /usr/bin/yum ];     then $(MAKE) yum-packages; fi
	if [ -x /usr/local/bin/brew -a `uname` = Darwin ]; then $(MAKE) homebrew-packages; fi
	
.PHONY: perl
perl:
	@echo ===========================
	@echo "Nagios Plugins Build (Perl)"
	@echo ===========================

	$(MAKE) common
	$(MAKE) perl-libs

.PHONY: perl-libs
perl-libs:
	cd lib && make

	# XXX: there is a bug in the Readonly module that MongoDB::MongoClient uses. It tries to call Readonly::XS but there is some kind of MAGIC_COOKIE mismatch and Readonly::XS errors out with:
	#
	# Readonly::XS is not a standalone module. You should not use it directly. at /usr/local/lib64/perl5/Readonly/XS.pm line 34.
	#
	# Workaround is to edit Readonly.pm and comment out line 33 which does the eval 'use Readonly::XS';
	# On Linux this is located at:
	#
	# /usr/local/share/perl5/Readonly.pm
	#
	# On my Mac OS X Mavericks:
	#
	# /Library/Perl/5.16/Readonly.pm

	# Required to successfully build the MongoDB module for For RHEL 5
	#sudo cpan Attribute::Handlers
	#sudo cpan Params::Validate
	#sudo cpan DateTime::Locale DateTime::TimeZone
	#sudo cpan DateTime

	# You may need to set this to get the DBD::mysql module to install if you have mysql installed locally to /usr/local/mysql
	#export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:/usr/local/mysql/lib/"

	@#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	
	# add -E to sudo to preserve http proxy env vars or run this manually if needed (only works on Mac)
	
	which cpanm || { yes "" | $(SUDO_PERL) cpan App::cpanminus; }

	# Workaround for Mac OS X not finding the OpenSSL libraries when building
	if [ -d /usr/local/opt/openssl/include -a \
	     -d /usr/local/opt/openssl/lib     -a \
	     `uname` = Darwin ]; then \
	     yes "" | $(SUDO_PERL) sudo OPENSSL_INCLUDE=/usr/local/opt/openssl/include OPENSSL_LIB=/usr/local/opt/openssl/lib $(CPANM) --notest Crypt::SSLeay; \
	fi

	# on Perl 5.10 List::MoreUtils::XS has starte failing to install first time, workaround is too run this twice
	for x in 1 2; do yes "" | $(SUDO_PERL) $(CPANM) --notest `sed 's/#.*//; /^[[:space:]]*$$/d;' < setup/cpan-requirements.txt` && break; done
	
	# newer versions of the Redis module require Perl >= 5.10, this will install the older compatible version for RHEL5/CentOS5 servers still running Perl 5.8 if the latest module fails
	# the backdated version might not be the perfect version, found by digging around in the git repo
	$(SUDO_PERL) $(CPANM) --notest Redis || $(SUDO_PERL) $(CPANM) --notest DAMS/Redis-1.976.tar.gz

	# Fix for Kafka dependency bug in NetAddr::IP::InetBase
	#
	# This now fails with permission denied even with sudo to root on Mac OSX Sierra due to System Integrity Protection:
	#
	# csrutil status
	#
	# would need to disable to edit system InetBase as documented here:
	#
	# https://developer.apple.com/library/content/documentation/Security/Conceptual/System_Integrity_Protection_Guide/ConfiguringSystemIntegrityProtection/ConfiguringSystemIntegrityProtection.html
	#
	libfilepath=`perl -MNetAddr::IP::InetBase -e 'print $$INC{"NetAddr/IP/InetBase.pm"}'`; grep -q 'use Socket' "$$libfilepath" || $(SUDO_PERL) sed -i.bak "s/use strict;/use strict; use Socket;/" "$$libfilepath" || : # doesn't work on Mac right now
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins perl)"
	@echo
	@echo


.PHONY: python
python:
	@echo =============================
	@echo "Nagios Plugins Build (Python)"
	@echo =============================

	$(MAKE) common
	$(MAKE) python-libs

.PHONY: python-libs
python-libs:
	cd pylib && make

	# newer version of setuptools (>=0.9.6) is needed to install cassandra-driver
	# might need to specify /usr/bin/easy_install or make /usr/bin first in path as sometimes there are version conflicts with Python's easy_install
	$(SUDO) easy_install -U setuptools || $(SUDO_PIP) easy_install -U setuptools || :
	$(SUDO) easy_install pip || :
	# cassandra-driver is needed for check_cassandra_write.py + check_cassandra_query.py
	# upgrade required to get install to work properly on Debian
	#$(SUDO) pip install --upgrade pip
	$(SUDO_PIP) pip install --upgrade -r requirements.txt
	# in requirements.txt now
	#$(SUDO_PIP) pip install cassandra-driver scales blist lz4 python-snappy
	# prevents https://urllib3.readthedocs.io/en/latest/security.html#insecureplatformwarning
	$(SUDO_PIP) pip install --upgrade ndg-httpsclient
	#. tests/utils.sh; $(SUDO) $$perl couchbase-csdk-setup
	#$(SUDO_PIP) pip install couchbase
	
	# install MySQLdb python module for check_logserver.py / check_syslog_mysql.py
	# fails if MySQL isn't installed locally
	# Mac fails to import module, one workaround is:
	# sudo install_name_tool -change libmysqlclient.18.dylib /usr/local/mysql/lib/libmysqlclient.18.dylib /Library/Python/2.7/site-packages/_mysql.so
	$(SUDO_PIP) pip install MySQL-python
	
	# must downgrade happybase library to work on Python 2.6
	if [ "$$(python -c 'import sys; sys.path.append("pylib"); import harisekhon; print(harisekhon.utils.getPythonVersion())')" = "2.6" ]; then $(SUDO_PIP) pip install --upgrade "happybase==0.9"; fi

	@echo
	unalias mv 2>/dev/null; \
	for x in \
		find_active_server.py \
		find_active_hadoop_namenode.py \
		find_active_hadoop_yarn_resource_manager.py \
		find_active_hbase_master.py \
		find_active_solrcloud.py \
		find_active_elasticsearch.py \
		; do \
		wget -O $$x.tmp https://raw.githubusercontent.com/HariSekhon/devops-python-tools/master/$$x && \
		mv -vf $$x.tmp $$x; \
		chmod +x $$x; \
	done
	@echo
	bash-tools/python_compile.sh
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins python)"
	@echo
	@echo

.PHONY: elasticsearch2
elasticsearch2:
	$(SUDO_PIP) pip install --upgrade 'elasticsearch>=2.0.0,<3.0.0'
	$(SUDO_PIP) pip install --upgrade 'elasticsearch-dsl>=2.0.0,<3.0.0'

.PHONY: apk-packages
apk-packages:
	$(SUDO) apk update
	$(SUDO) apk add `sed 's/#.*//; /^[[:space:]]*$$/d' setup/apk-packages.txt setup/apk-packages-dev.txt`

.PHONY: apk-packages-remove
apk-packages-remove:
	cd lib && $(MAKE) apk-packages-remove
	$(SUDO) apk del `sed 's/#.*//; /^[[:space:]]*$$/d' < setup/apk-packages-dev.txt` || :
	$(SUDO) rm -fr /var/cache/apk/*

.PHONY: apt-packages
apt-packages:
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y `sed 's/#.*//; /^[[:space:]]*$$/d' setup/deb-packages.txt setup/deb-packages-dev.txt`
	$(SUDO) apt-get install -y python-mysqldb || :
	$(SUDO) apt-get install -y python3-mysqldb || :
	$(SUDO) apt-get install -y libmysqlclient-dev || :
	$(SUDO) apt-get install -y libmariadbd-dev || :
	# for Ubuntu builds otherwise autoremove in docker removes this so mysql python library doesn't work
	$(SUDO) apt-get install -y libmariadbclient18 || :
	# for check_whois.pl - looks like this has been removed from repos :-/
	$(SUDO) apt-get install -y jwhois || :

.PHONY: apt-packages-remove
apt-packages-remove:
	cd lib && $(MAKE) apt-packages-remove
	$(SUDO) apt-get purge -y `sed 's/#.*//; /^[[:space:]]*$$/d' < setup/deb-packages-dev.txt`
	$(SUDO) apt-get purge -y libmariadbd-dev || :
	$(SUDO) apt-get purge -y libmysqlclient-dev || :

.PHONY: homebrew-packages
homebrew-packages:
	# Sudo is not required as running Homebrew as root is extremely dangerous and no longer supported as Homebrew does not drop privileges on installation you would be giving all build scripts full access to your system
	# Fails if any of the packages are already installed, ignore and continue - if it's a problem the latest build steps will fail with missing headers
	brew install `sed 's/#.*//; /^[[:space:]]*$$/d' setup/brew-packages.txt` || :

.PHONY: yum-packages
yum-packages:
	# to fetch and untar ZooKeeper, plus wget epel rpm
	rpm -q wget || yum install -y wget
	
	# epel-release is in the list of rpms to install via yum in setup/rpm-packages.txt but this is a more backwards compatible method of installing that will work on older versions of RHEL / CentOS as well so is left here for compatibility purposes
	#
	# python-pip requires EPEL, so try to get the correct EPEL rpm
	# this doesn't work for some reason CentOS 5 gives 'error: skipping https://dl.fedoraproject.org/pub/epel/epel-release-latest-5.noarch.rpm - transfer failed - Unknown or unexpected error'
	# must instead do wget 
	rpm -q epel-release      || yum install -y epel-release || { wget -t 5 --retry-connrefused -O /tmp/epel.rpm "https://dl.fedoraproject.org/pub/epel/epel-release-latest-`grep -o '[[:digit:]]' /etc/*release | head -n1`.noarch.rpm" && $(SUDO) rpm -ivh /tmp/epel.rpm && rm -f /tmp/epel.rpm; }

	# installing packages individually to catch package install failure, otherwise yum succeeds even if it misses a package
	for x in `sed 's/#.*//; /^[[:space:]]*$$/d' setup/rpm-packages.txt setup/rpm-packages-dev.txt`; do rpm -q $$x || $(SUDO) yum install -y $$x; done

	# breaks on CentOS 7.0 on Docker, fakesystemd conflicts with systemd, 7.2 works though
	rpm -q cyrus-sasl-devel || $(SUDO) yum install -y cyrus-sasl-devel || :

	# for check_yum.pl / check_yum.py:
	# can't do this in setup/yum-packages.txt as one of these two packages will be missing depending on the RHEL version
	rpm -q yum-security yum-plugin-security || yum install -y yum-security yum-plugin-security

.PHONY: yum-packages-remove
yum-packages-remove:
	cd lib && $(MAKE) yum-packages-remove
	for x in `sed 's/#.*//; /^[[:space:]]*$$/d' < setup/rpm-packages-dev.txt`; do if rpm -q $$x; then $(SUDO) yum remove -y $$x; fi; done

# Net::ZooKeeper must be done separately due to the C library dependency it fails when attempting to install directly from CPAN. You will also need Net::ZooKeeper for check_zookeeper_znode.pl to be, see README.md or instructions at https://github.com/harisekhon/nagios-plugins
# doesn't build on Mac < 3.4.7 / 3.5.1 / 3.6.0 but the others are in the public mirrors yet
# https://issues.apache.org/jira/browse/ZOOKEEPER-2049
ZOOKEEPER_VERSION = 3.4.12
.PHONY: zookeeper
zookeeper:
	[ -x /sbin/apk ]        && $(MAKE) apk-packages || :
	[ -x /usr/bin/apt-get ] && $(MAKE) apt-packages || :
	[ -x /usr/bin/yum ]     && $(MAKE) yum-packages || :
	[ -f zookeeper-$(ZOOKEEPER_VERSION).tar.gz ] || wget -O zookeeper-$(ZOOKEEPER_VERSION).tar.gz "http://www.apache.org/dyn/closer.lua?filename=zookeeper/zookeeper-${ZOOKEEPER_VERSION}/zookeeper-${ZOOKEEPER_VERSION}.tar.gz&action=download" || wget -t 2 --retry-connrefused -O zookeeper-$(ZOOKEEPER_VERSION).tar.gz "https://archive.apache.org/dist/zookeeper/zookeeper-$(ZOOKEEPER_VERSION)/zookeeper-$(ZOOKEEPER_VERSION).tar.gz"
	[ -d zookeeper-$(ZOOKEEPER_VERSION) ] || tar zxf zookeeper-$(ZOOKEEPER_VERSION).tar.gz
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				./configure
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				$(SUDO) $(MAKE) install
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	perl Makefile.PL --zookeeper-include=/usr/local/include --zookeeper-lib=/usr/local/lib
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	LD_RUN_PATH=/usr/local/lib $(SUDO) make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	$(SUDO) $(MAKE) install
	perl -e "use Net::ZooKeeper"
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins perl zookeeper)"
	@echo
	@echo

.PHONY: jar-plugins
jar-plugins:
	@echo Fetching pre-compiled Java / Scala plugins
	@echo
	@echo Fetching Kafka Scala Nagios Plugin
	@echo fetching jar wrapper shell script
	# if removing and re-uploading latest this would get 404 and exit immediately without the rest of the retries
	#wget -c -t 5 --retry-connrefused https://github.com/HariSekhon/nagios-plugin-kafka/blob/latest/check_kafka
	for x in {1..6}; do wget -c https://github.com/HariSekhon/nagios-plugin-kafka/blob/latest/check_kafka && break; sleep 10; done
	@echo fetching jar
	#wget -c -t 5 --retry-connrefused https://github.com/HariSekhon/nagios-plugin-kafka/releases/download/latest/check_kafka.jar
	for x in {1..6}; do wget -c https://github.com/HariSekhon/nagios-plugin-kafka/releases/download/latest/check_kafka.jar && break; sleep 10; done

.PHONY: sonar
sonar:
	sonar-scanner

.PHONY: lib-test
lib-test:
	cd lib && $(MAKE) test
	rm -fr lib/cover_db || :
	cd pylib && $(MAKE) test

.PHONY: test
test: lib-test
	tests/all.sh

.PHONY: basic-test
basic-test: lib-test
	. tests/excluded.sh; bash-tools/all.sh
	tests/help.sh

.PHONY: install
install:
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH and Nagios commands.cfg"

.PHONY: update
update: update2 build
	:

.PHONY: update2
update2: update-no-recompile
	:

.PHONY: update-no-recompile
update-no-recompile:
	git pull
	git submodule update --init --recursive

.PHONY: update-submodules
update-submodules:
	git submodule update --init --remote
.PHONY: updatem
updatem: update-submodules
	:

.PHONY: clean
clean:
	cd lib && $(MAKE) clean
	cd pylib && $(MAKE) clean
	@find . -maxdepth 3 -iname '*.py[co]' -o -iname '*.jy[co]' | xargs rm -f || :
	@$(MAKE) clean-zookeeper
	rm -fr tests/spark-*-bin-hadoop*

.PHONY: clean-zookeeper
clean-zookeeper:
	rm -fr zookeeper-$(ZOOKEEPER_VERSION).tar.gz zookeeper-$(ZOOKEEPER_VERSION)

.PHONY: deep-clean
deep-clean: clean clean-zookeeper
	cd lib && $(MAKE) deep-clean
	cd pylib && $(MAKE) deep-clean

.PHONY: docker-run
docker-run:
	docker run -ti --rm harisekhon/nagios-plugins ${ARGS}

.PHONY: run
run: docker-run
	:

.PHONY: docker-mount
docker-mount:
	# --privileged=true is needed to be able to:
	# mount -t tmpfs -o size=1m tmpfs /mnt/ramdisk
	docker run -ti --rm --privileged=true -v $$PWD:/pl harisekhon/nagios-plugins bash -c "cd /pl; exec bash"

.PHONY: docker-mount-alpine
docker-mount-alpine:
	# --privileged=true is needed to be able to:
	# mount -t tmpfs -o size=1m tmpfs /mnt/ramdisk
	docker run -ti --rm --privileged=true -v $$PWD:/pl harisekhon/nagios-plugins:alpine bash -c "cd /pl; exec bash"

.PHONY: docker-mount-debian
docker-mount-debian:
	# --privileged=true is needed to be able to:
	# mount -t tmpfs -o size=1m tmpfs /mnt/ramdisk
	docker run -ti --rm --privileged=true -v $$PWD:/pl harisekhon/nagios-plugins:debian bash -c "cd /pl; exec bash"

.PHONY: docker-mount-centos
docker-mount-centos:
	# --privileged=true is needed to be able to:
	# mount -t tmpfs -o size=1m tmpfs /mnt/ramdisk
	docker run -ti --rm --privileged=true -v $$PWD:/pl harisekhon/nagios-plugins:centos bash -c "cd /pl; exec bash"

.PHONY: docker-mount-ubuntu
docker-mount-ubuntu:
	# --privileged=true is needed to be able to:
	# mount -t tmpfs -o size=1m tmpfs /mnt/ramdisk
	docker run -ti --rm --privileged=true -v $$PWD:/pl harisekhon/nagios-plugins:ubuntu bash -c "cd /pl; exec bash"

.PHONY: mount
mount: docker-mount
	:

.PHONY: mount-alpine
mount-alpine: docker-mount-alpine
	:

.PHONY: mount-debian
mount-debian: docker-mount-debian
	:

.PHONY: mount-centos
mount-centos: docker-mount-centos
	:

.PHONY: mount-ubuntu
mount-ubuntu: docker-mount-ubuntu
	:

.PHONY: push
push:
	git push
