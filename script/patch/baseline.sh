#!/bin/bash

# Move into the right directory
cd lib/baseline-v2

# Generate the diff
git diff . > ../../script/patch/baseline.patch

echo "Done!"
