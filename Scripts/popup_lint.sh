#!/bin/sh
# Fails if a system presentation is used outside the popup kit; every popup must go through PopupHost (.centerSheet, ConfirmPopup).
cd "$(dirname "$0")/.." || exit 1
hits=$(grep -rnE '\.(sheet|fullScreenCover|alert|confirmationDialog|popover)\(' native/App/Ledger --include=*.swift \
  | grep -vE 'Design/(PopupKit|CenterSheet)\.swift' | grep -vE '^[^:]*:[0-9]+:\s*///')
if [ -n "$hits" ]; then echo "$hits"; echo "popup_lint: system presentation found"; exit 1; fi
echo "popup_lint: ok"
