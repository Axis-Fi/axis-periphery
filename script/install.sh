#!/bin/bash

echo ""
echo "*** Installing soldeer"
cargo install soldeer
echo "    Done"

echo ""
echo "*** Installing forge dependencies"
forge install
echo "    Done"

echo ""
echo "*** Installing soldeer dependencies"
soldeer install
echo "    Done"
