#!/bin/bash
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    v="${1/--/}"
    declare $v="$2"
  fi

  shift
done

# Check if bytecodeFile exists
if [ -z "$bytecodeHash" ]
then
  echo "Bytecode not found. Provide the correct bytecode after the command."
  exit 1
fi

# Check if prefix is set
if [ -z "$prefix" ]
then
  echo "No prefix specified. Provide the prefix after the bytecode file."
  exit 1
fi

output=$(cast create2 --case-sensitive --starts-with $prefix --init-code-hash $bytecodeHash --deployer $deployer)

salt=$(echo "$output" | grep "Salt:" | awk '{print $2}' | tr -d '\n' | sed 's/\r//g')

printf "%s" "$salt"