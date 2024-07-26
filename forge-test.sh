#!/bin/bash

forge test -vvv --no-match-test __Fork__Fuzz $@
FOUNDRY_PROFILE=forkfuzz forge test -vvv --match-test __Fork__Fuzz $@