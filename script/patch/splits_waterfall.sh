#!/bin/bash

# Move into the right directory
cd dependencies/splits-waterfall-1.0.0/

# Generate the diff
git diff . > ../../script/patch/splits_waterfall.patch

echo "Done!"
