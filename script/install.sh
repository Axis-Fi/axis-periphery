#!/bin/bash

echo ""
echo "*** Removing submodules"
rm -rf lib/

echo ""
echo "*** Setting up submodules"
git submodule init
git submodule update

echo ""
echo "*** Restoring submodule commits"

echo ""
echo "baseline"
cd lib/baseline-v2/ && git checkout 60bed78b7bee28016321ddd8c590df6c61bae6e9  && cd ../..

echo ""
echo "*** Installing forge dependencies"
rm -rf lib && forge install
echo "    Done"

echo ""
echo "*** Applying patch to Baseline submodule"
patch -d lib/baseline-v2/ -p1 < script/baseline.patch

echo ""
echo "*** Installing soldeer dependencies"
rm -rf dependencies/* && forge soldeer update
echo "    Done"
