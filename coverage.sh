#!/bin/bash

set -e # exit on error

# generates lcov.info
forge coverage --report lcov

# Initialize variables
current_file=""
lines_found=0
lines_hit=0

sed 's/\.\.\/vault\///g' lcov.info > lcov-clearvault.info

# generates coverage/lcov.info
yarn hardhat coverage

# Foundry uses relative paths but Hardhat uses absolute paths.
# Convert absolute paths to relative paths for consistency.
sed -i -e "s/\/.*$(basename "$PWD").//g" coverage/lcov.info

# Merge lcov files
lcov \
    --rc lcov_branch_coverage=1 \
    --add-tracefile coverage/lcov.info \
    --add-tracefile lcov-clearvault.info \
    --output-file merged-lcov.info \
    --no-checksum \
    --ignore-errors unused \
    --ignore-errors format \
    --ignore-errors empty

# Filter out node_modules, test, and mock files
lcov \
    --rc lcov_branch_coverage=1 \
    --remove merged-lcov.info \
    "*node_modules*" "*test*" "*mock*" \
    --output-file coverage/filtered-lcov.info \
    --ignore-errors unused \
    --ignore-errors format \
    --ignore-errors empty

# Generate summary
lcov \
    --rc lcov_branch_coverage=1 \
    --list coverage/filtered-lcov.info \
    --ignore-errors unused \
    --ignore-errors format \
    --ignore-errors empty

# Open more granular breakdown in browser
# if [ "$HTML" == "true" ]
# then
    genhtml \
        --rc genhtml_branch_coverage=1 \
        --output-directory coverage-genhtml \
        --ignore-errors category \
        coverage/filtered-lcov.info
    open coverage-genhtml/index.html
# fi

# Delete temp files
rm merged-lcov.info coverage/filtered-lcov.info lcov-clear.info lcov-clearvault.info


