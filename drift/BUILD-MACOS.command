#!/bin/bash
# DRIFT — build a macOS app. Double-click this file.
cd "$(dirname "$0")" || exit 1
echo
echo "  DRIFT — building a macOS app"
echo "  ----------------------------"
echo
if ! command -v node >/dev/null 2>&1; then
  echo "  Node.js is not installed."
  echo
  echo "  Get the LTS installer from https://nodejs.org"
  echo "  Then double-click this file again."
  echo
  read -r -p "  Press return to close."
  exit 1
fi
node build.mjs --mac
echo
echo "  Your app is in the dist folder."
read -r -p "  Press return to close."
