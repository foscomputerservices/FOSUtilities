#!/bin/sh

# https://github.com/nektos/act/issues/97#issuecomment-1868974264
# act -P windows-latest=-self-hosted
# act -P ubuntu-latest=-self-hosted
# act -P macos-latest=-self-hosted
# act -P freebsd-latest=-self-hosted

cleanup() {
    echo "CTRL-C detected. Running cleanup..."
    echo "Performing final tasks..."
    ./toggle-sudo.sh -r
}

trap cleanup SIGINT

sudo -v -B
./toggle-sudo.sh -a
act -j run_tests --container-architecture linux/amd64 -P macos-latest=-self-hosted # --verbose
cleanup
