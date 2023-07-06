#!/bin/bash

set -e # exit on error

# generates lcov.info
forge coverage --report lcov

# Initialize variables
current_file=""
lines_found=0
lines_hit=0

# Clear files_with_lines_coverage.txt before usage
> files_with_lines_coverage.txt

# Process each line of the LCOV report
while IFS= read -r line
do
  if [[ $line == LF:* ]]; then
    # Get the line count
    lines_found=${line#LF:}
  elif [[ $line == LH:* ]]; then
    # Get the line hit count
    lines_hit=${line#LH:}
    
    # Check if lines_found is equal to lines_hit
    if [[ $lines_found -eq $lines_hit ]]; then
      # Remember the current file as having 100% coverage
      echo "$current_file" >> files_with_lines_coverage.txt
    fi
  elif [[ $line == SF:* ]]; then
    # If the line contains "SF:", it's the start of a new file. Save the filename.
    current_file=${line#SF:}
  fi
done < lcov.info

# Create a space-separated string of all file patterns
patterns=$(cat files_with_lines_coverage.txt | tr '\n' ' ')

# Now use single lcov --extract command with all file patterns
lcov --extract lcov.info $patterns --output-file lcov.info

# generates coverage/lcov.info
yarn hardhat coverage

# Foundry uses relative paths but Hardhat uses absolute paths.
# Convert absolute paths to relative paths for consistency.
sed -i -e "s/\/.*$(basename "$PWD").//g" coverage/lcov.info

# Now use single lcov --remove command with all file patterns
lcov --remove coverage/lcov.info $patterns --output-file coverage/lcov.info

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
    "*node_modules*" "*test*" "*mock*" \
    --output-file coverage/filtered-lcov.info

# Generate summary
lcov \
    --rc lcov_branch_coverage=1 \
    --list coverage/filtered-lcov.info

# Open more granular breakdown in browser
if [ "$HTML" == "true" ]
then
    genhtml \
        --rc genhtml_branch_coverage=1 \
        --output-directory coverage \
        coverage/filtered-lcov.info
    open coverage/index.html
fi

# Delete temp files
rm lcov.info merged-lcov.info files_with_lines_coverage.txt


