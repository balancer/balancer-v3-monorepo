#!/bin/bash

set -e # exit on error

# reduces the amount of tests in fuzzing, so coverage runs faster
export FOUNDRY_PROFILE=coverage
export CURRENT_PACKAGE=$(basename "$PWD")

# generates lcov.info
forge coverage --report lcov

# Initialize variables
current_file=""
lines_found=0
lines_hit=0

sed "s/\/.*$CURRENT_PACKAGE.//g" lcov.info > lcov-clearfolders.info
sed -i -e "s/\.\.contracts\//contracts\//g" lcov-clearfolders.info

# generates coverage/lcov.info
COVERAGE=true yarn hardhat coverage

# Foundry uses relative paths but Hardhat uses absolute paths.
# Convert absolute paths to relative paths for consistency.
sed -i -e "s/\/.*$CURRENT_PACKAGE.//g" coverage/lcov.info

# Merge lcov files
lcov \
  --rc lcov_branch_coverage=1 \
  --rc derive_function_end_line=0 \
  --add-tracefile lcov-clearfolders.info \
  --add-tracefile coverage/lcov.info \
  --output-file lcov-merged.info \
  --no-checksum

if [$CURRENT_PACKAGE = 'vault']; then
  # Filter out node_modules, test, and mock files
  lcov \
    --rc lcov_branch_coverage=1 \
    --rc derive_function_end_line=0 \
    --remove lcov-merged.info \
    "*node_modules*" "*test*" "*mock*" \
    --output-file lcov-filtered.info
else
  # Filter out node_modules, test, mock files and vault contracts
  lcov \
    --rc lcov_branch_coverage=1 \
    --rc derive_function_end_line=0 \
    --remove lcov-merged.info \
    "*node_modules*" "*test*" "*mock*" "*/vault/*"\
    --output-file lcov-filtered.info
fi

# Generate summary
lcov \
  --rc lcov_branch_coverage=1 \
  --rc derive_function_end_line=0 \
  --list lcov-filtered.info

# Open more granular breakdown in browser
rm -rf coverage-genhtml/
genhtml \
  --rc genhtml_branch_coverage=1 \
  --rc derive_function_end_line=0 \
  --output-directory coverage-genhtml \
  lcov-filtered.info
open coverage-genhtml/index.html

# Delete temp files
rm -rf lcov-*.info lcov-*.info-e coverage/ lcov.info coverage.json
