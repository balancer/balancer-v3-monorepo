#!/bin/bash

set -e # exit on error

# Functions

function forge_coverage() {
  echo 'Running Forge coverage'

  # reduces the amount of tests in fuzzing, so coverage runs faster
  export FOUNDRY_PROFILE=coverage
  export CURRENT_PACKAGE=$(basename "$PWD")

  # generates lcov.info
  forge coverage --report lcov

  # Initialize variables
  current_file=""
  lines_found=0
  lines_hit=0

  sed "s/\/.*$CURRENT_PACKAGE.//g" lcov.info > lcov-forge.info
  sed -i -e "s/\.\.contracts\//contracts\//g" lcov-forge.info
}

function hardhat_coverage() {
  echo 'Running Hardhat coverage'
  # generates coverage/lcov.info
  COVERAGE=true yarn hardhat coverage

  export CURRENT_PACKAGE=$(basename "$PWD")

  # Foundry uses relative paths but Hardhat uses absolute paths.
  # Convert absolute paths to relative paths for consistency.
  sed -i -e "s/\/.*$CURRENT_PACKAGE.//g" coverage/lcov.info
  mv coverage/lcov.info lcov-hardhat.info
}

function merge() {
  echo 'Merging coverage files...'

  if [[ "$1" == 'forge' ]]; then
    # For forge-only, just copy the file instead of merging
    cp lcov-forge.info lcov-merged.info
  elif [[ "$1" == 'hardhat' ]]; then
    lcov \
      --rc branch_coverage=1 \
      --rc derive_function_end_line=0 \
      --add-tracefile lcov-hardhat.info \
      --output-file lcov-merged.info
  elif [[ "$1" == 'all' ]]; then
    lcov \
      --rc branch_coverage=1 \
      --rc derive_function_end_line=0 \
      --ignore-errors format,corrupt \
      --add-tracefile lcov-forge.info \
      --add-tracefile lcov-hardhat.info \
      --output-file lcov-merged.info
  fi
}

function filter_and_display() {
  echo 'Filtering report...'

  if [[ $CURRENT_PACKAGE == "vault" ]]; then
    # Filter out node_modules, test, and mock files
    lcov \
      --rc branch_coverage=1 \
      --ignore-errors unused \
      --rc derive_function_end_line=0 \
      --remove lcov-merged.info \
      "*node_modules*" "*test*" "*Mock*" \
      --output-file lcov-filtered.info
  else
    # Filter out node_modules, test, mock files and vault contracts
    lcov \
      --rc branch_coverage=1 \
      --ignore-errors unused \
      --rc derive_function_end_line=0 \
      --remove lcov-merged.info \
      "*node_modules*" "*test*" "*Mock*" "*/vault/*" \
      --output-file lcov-filtered.info
  fi

  echo 'Generating summary...'

  # Generate summary
  lcov \
    --rc branch_coverage=1 \
    --rc derive_function_end_line=0 \
    --list lcov-filtered.info

  echo 'Generating HTML report...'

  rm -rf coverage-genhtml/
  genhtml \
    --rc branch_coverage=1 \
    --rc derive_function_end_line=0 \
    --output-directory coverage-genhtml \
    lcov-filtered.info

  if [[ "$CI" == "true" ]]; then
    echo 'Coverage HTML generated at coverage-genhtml/index.html'
  else
    # Open more granular breakdown in browser
    echo 'Opening browser...'
    open coverage-genhtml/index.html
  fi
}

# Script

if [[ "$1" == 'forge' ]]; then
  forge_coverage
elif [[ "$1" == 'hardhat' ]]; then
  hardhat_coverage
elif [[ "$1" == 'all' ]]; then
  forge_coverage
  hardhat_coverage
else
  echo 'Usage: ./coverage.sh [forge | hardhat | all]'
  exit 1
fi

merge "$1"

filter_and_display

# Delete temp files
if [[ "$CI" == "true" ]]; then
  # CI: Keep lcov-filtered.info and coverage-genhtml/ for artifacts
  rm -rf lcov-forge.info lcov-hardhat.info lcov-merged.info lcov-*.info-e coverage/ lcov.info coverage.json
else
  # Local: delete all lcov files, keep HTML
  rm -rf lcov-*.info lcov-*.info-e coverage/ lcov.info coverage.json
fi
