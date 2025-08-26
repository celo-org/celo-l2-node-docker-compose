#!/bin/sh
set -e

if [ "$NETWORK_NAME" != "alfajores" ] || [ "$NETWORK_NAME" != "baklava" ] || [ "$NETWORK_NAME" != "mainnet" ]; then
  echo "Not starting challenger for a chain without Succinct support"
  exit
fi

if [ -n "${CHALLENGER_ENABLE}" ]; then
  echo "Not starting challenger, because \`${CHALLENGER_ENABLE}\` is not set"
  exit
fi

# Start challenger.
exec challenger $@
