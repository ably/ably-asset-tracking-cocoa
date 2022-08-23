#!/bin/bash

set -e

# We’re using Mint to make sure that everyone runs the same version of Sourcery.

if ! which mint > /dev/null
then
  echo "You need to install Mint (https://github.com/yonaskolb/Mint)." 2>&1
  exit 1
fi

run_sourcery () {
  mint run krzysztofzablocki/Sourcery@1.8.2 --config ".sourcery-${1}.yml"
}

run_sourcery "InternalMocks"
