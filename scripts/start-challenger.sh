#!/bin/sh
set -e

if [ "$CHALLENGER_ENABLED" != "true" ]; then
	echo "CHALLENGER_ENABLED is not set to 'true'"
	echo "Not starting challenger"
	exit
fi

if [ -z "$PRIVATE_KEY" ]; then
	echo "PRIVATE_KEY is not set or empty"
	echo "Not starting challenger"
	exit
fi

if ! echo "$PRIVATE_KEY" | grep -qE '^(0x)?[0-9a-fA-F]+$'; then
	echo "PRIVATE_KEY is not a valid hex string"
	echo "Not starting challenger"
	exit
fi

exec challenger "$@"
