#!/usr/bin/env bash
#
# Test --fast configuration on full suite with compiler performance enabled on
# linux64.

CWD=$(cd $(dirname $0) ; pwd)
source $CWD/common.bash
source $CWD/common-fast.bash

nightly_args="${nightly_args} -compperformance (--fast)"
$CWD/nightly -cron ${nightly_args}
