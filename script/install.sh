#!/bin/bash

echo ""
echo "*** Installing forge dependencies"
forge install
echo "    Done"

echo ""
echo "*** Installing soldeer dependencies"
rm -rf dependencies/* && forge soldeer update
echo "    Done"
