#!/bin/bash

REUSING_HARDHAT_ARTIFACTS=true forge test -vvv --no-match-test __Fork__Fuzz $@ &&
REUSING_HARDHAT_ARTIFACTS=true FOUNDRY_PROFILE=forkfuzz forge test -vvv --match-test __Fork__Fuzz $@
