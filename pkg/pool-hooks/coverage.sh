#!/bin/bash

set -e # exit on error

# reduces the amount of tests in fuzzing, so coverage runs faster
export FOUNDRY_PROFILE=coverage

# generates lcov.info
forge coverage --report lcov

# Initialize variables
current_file=""
lines_found=0
lines_hit=0

sed 's/\.\.\/vault\///g' lcov.info > lcov-clearvault.info
sed 's/\.\.\/pool-weighted\///g' lcov-clearvault.info > lcov-clearfolders.info

# generates coverage/lcov.info
yarn hardhat coverage

# Foundry uses relative paths but Hardhat uses absolute paths.
# Convert absolute paths to relative paths for consistency.
sed -i -e "s/\/.*$(basename "$PWD").//g" coverage/lcov.info

# Merge lcov files
lcov \
    --rc branch_coverage=1 \
    --add-tracefile coverage/lcov.info \
    --add-tracefile lcov-clearfolders.info \
    --output-file lcov-merged.info \
    --no-checksum \
    --ignore-errors unused \
    --ignore-errors format \
    --ignore-errors empty

# Filter out node_modules, test, and mock files
lcov \
    --rc branch_coverage=1 \
    --remove lcov-merged.info \
    "*node_modules*" "*test*" "*mock*" \
    --output-file lcov-filtered.info \
    --ignore-errors unused \
    --ignore-errors format \
    --ignore-errors empty

# Generate summary
lcov \
    --rc branch_coverage=1 \
    --list lcov-filtered.info \
    --ignore-errors unused \
    --ignore-errors format \
    --ignore-errors empty

# Open more granular breakdown in browser
genhtml \
    --rc branch_coverage=1 \
    --output-directory coverage-genhtml \
    --ignore-errors category \
    lcov-filtered.info
open coverage-genhtml/index.html

# Delete temp files
rm lcov-*.info


