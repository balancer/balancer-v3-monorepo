#!/bin/bash

set -e # exit on error

# generates lcov.info
forge coverage --report lcov

# Name of the file containing the list of file names
file_list=".forge-cover"

# Read file names from the file and generate a glob pattern
pattern=""
while IFS= read -r file_name
do
    pattern+="*${file_name}* "
done < "$file_list"

# Invoke lcov command with the generated pattern
lcov --extract lcov.info $pattern --output-file lcov.info

# generates coverage/lcov.info
yarn hardhat coverage

# Foundry uses relative paths but Hardhat uses absolute paths.
# Convert absolute paths to relative paths for consistency.
sed -i -e "s/\/.*$(basename "$PWD").//g" coverage/lcov.info

# Merge lcov files
lcov \
    --rc lcov_branch_coverage=1 \
    --add-tracefile coverage/lcov.info \
    --add-tracefile lcov.info \
    --output-file merged-lcov.info \
    --no-checksum

# Filter out node_modules, test, and mock files
lcov \
    --rc lcov_branch_coverage=1 \
    --remove merged-lcov.info \
    --output-file coverage/filtered-lcov.info \
    "*node_modules*" "*test*" "*mock*"

# Generate summary
lcov \
    --rc lcov_branch_coverage=1 \
    --list coverage/filtered-lcov.info

# Open more granular breakdown in browser
if [ "$CI" != "true" ]
then
    genhtml \
        --rc genhtml_branch_coverage=1 \
        --output-directory coverage \
        coverage/filtered-lcov.info
    open coverage/index.html
fi

# Delete temp files
rm lcov.info merged-lcov.info
