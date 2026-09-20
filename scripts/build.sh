#!/bin/sh
set -eu

swift build -c release
codesign --force --sign - --entitlements Resources/Mote.entitlements .build/release/mote
echo "Built and signed .build/release/mote"
