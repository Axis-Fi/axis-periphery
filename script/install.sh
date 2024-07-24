#!/bin/bash

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
cd lib/baseline-v2/ && git checkout 60bed78b7bee28016321ddd8c590df6c61bae6e9  && cd ../..

echo ""
echo "*** Installing soldeer dependencies"
rm -rf dependencies/* && forge soldeer update
echo "    Done"
