#!/bin/bash

# Only run this postinstall script if we're developing it.
# (Don't run if we're importing this package as an npm dependency
# inside a different repo)
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Skipping install script because this is not inside a Git work tree."
  exit 0
fi

echo ""
echo "*** Removing submodules"
rm -rf lib/

echo ""
echo "*** Setting up submodules"
git submodule init
git submodule update

echo ""
echo "*** Installing forge dependencies"
forge install
echo "    Done"

echo ""
echo "*** Restoring submodule commits"

echo ""
echo "baseline"
cd lib/baseline-v2/ && git checkout 8950018baec27d6497fba409cb361a596535447d  && cd ../..

echo ""
echo "*** Applying patch to Baseline submodule"
patch -d lib/baseline-v2/ -p1 < script/patch/baseline.patch

echo ""
echo "*** Installing soldeer dependencies"
rm -rf dependencies/* && forge soldeer update
echo "    Done"
