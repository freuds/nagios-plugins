#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-08-22 16:17:31 +0100 (Mon, 22 Aug 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

section "T r a v i s   C I"

# this repo should always be working
run ./check_travis_ci_last_build.py -r HariSekhon/bash-tools

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/nagios-plugins

echo "check warning threshold to induce failure as builds should always take longer than 10 secs:"
run_fail "1 2" ./check_travis_ci_last_build.py -r HariSekhon/nagios-plugins -v -w 10

echo "check critical threshold to induce failure as builds should always take longer than 10 secs:"
run_fail 2 ./check_travis_ci_last_build.py -r HariSekhon/nagios-plugins -v -c 10

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/devops-perl-tools

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/spotify-tools

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/devops-python-tools

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/pylib

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/lib

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/lib-java

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/nagios-plugin-kafka

run_fail "0 2" ./check_travis_ci_last_build.py -r HariSekhon/spark-apps

echo "checking no builds returned:"
run_fail 3 ./check_travis_ci_last_build.py -r harisekhon/nagios-plugins -v

echo "checking wrong repo name/format:"
run_usage ./check_travis_ci_last_build.py -r test -v

run_usage ./check_travis_ci_last_build.py -r harisekhon/ -v

run_usage ./check_travis_ci_last_build.py -r /nagios-plugins -v

run_usage ./check_travis_ci_last_build.py -r tools -v

echo "checking nonexistent repo:"
run_fail 3 ./check_travis_ci_last_build.py -r nonexistent/repo -v

echo "Completed $run_count Travis CI tests"
echo
echo "All Travis CI tests passed successfully"
echo
echo
