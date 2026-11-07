#!/bin/sh
# Popup rules that must not come back:
#  1. no system presentation outside the popup kit: every popup goes through PopupHost (.centerSheet, ConfirmPopup, GamePopup);
#  2. the popup frame has no fixed or minimum card height and no screen-share sizing besides the three categories in PopupSystem.swift.
cd "$(dirname "$0")/.." || exit 1
fail=0
hits=$(grep -rnE '\.(sheet|fullScreenCover|alert|confirmationDialog|popover)\(' native/App/Ledger --include=*.swift \
  | grep -vE 'Design/(PopupKit|CenterSheet)\.swift' | grep -vE '^[^:]*:[0-9]+:\s*///')
if [ -n "$hits" ]; then echo "$hits"; echo "popup_lint: system presentation found"; fail=1; fi
old=$(grep -rnE 'PopupSizeClass|toastMaxHeight|compactMaxHeight|fullHeight\(|standardFraction|tallFraction|PopupMetrics' native/App/Ledger --include=*.swift)
if [ -n "$old" ]; then echo "$old"; echo "popup_lint: old popup size rules are back"; fail=1; fi
frame=$(grep -nE 'minHeight:|\.frame\(height: *[0-9]' native/App/Ledger/Design/CenterSheet.swift | grep -vE 'Capsule|PopupCloseButton|grabber|frame\(minHeight: 64\)')
if [ -n "$frame" ]; then echo "$frame"; echo "popup_lint: a fixed or minimum height in the popup frame"; fail=1; fi
[ $fail = 0 ] && echo "popup_lint: ok"
exit $fail
