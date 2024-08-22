#!/bin/bash

# Usage:
# ./allowlist_salts.sh --deployFile <path> --envFile <.env>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Iterate through named arguments
# Source: https://unix.stackexchange.com/a/388038
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    v="${1/--/}"
    declare $v="$2"
  fi

  shift
done

DEPLOY_FILE=$deployFile

# Get the name of the .env file or use the default
ENV_FILE=${envFile:-".env"}
echo "Sourcing environment variables from $ENV_FILE"

# Load environment file
set -a  # Automatically export all variables
source $ENV_FILE
set +a  # Disable automatic export

# Check that the CHAIN environment variable is set
if [ -z "$CHAIN" ]
then
  echo "CHAIN environment variable is not set. Please set it in the .env file or provide it as an environment variable."
  exit 1
fi

# Check if DEPLOY_FILE is set
if [ -z "$DEPLOY_FILE" ]
then
  echo "No deploy file specified. Provide the relative path after the --deployFile flag."
  exit 1
fi

echo "Using chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"
echo "Using deploy file: $DEPLOY_FILE"

forge script ./script/salts/allowlist/AllowListSalts.s.sol:AllowlistSalts --sig "generate(string,string)()" $CHAIN $DEPLOY_FILE
