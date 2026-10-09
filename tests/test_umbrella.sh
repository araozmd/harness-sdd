#!/bin/sh
# Compatibility entrypoint: ordered serial execution of every umbrella group.
set -eu
umbrella_tests="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
for umbrella_group in "$umbrella_tests"/test_umbrella_[0-9][0-9]_*.sh; do
  sh "$umbrella_group"
done
echo "All umbrella tests passed."
