#!/bin/bash

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
echo "*** Installing soldeer dependencies"
rm -rf dependencies/* && forge soldeer update
echo "    Done"

echo ""
echo "*** Applying patch to splits-waterfall"
patch -d dependencies/splits-waterfall-1.0.0/ -p1 < script/patch/splits_waterfall.patch
