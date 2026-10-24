# Installing on your phone without the paid Apple Developer Program

Free route, with limits: a free Apple ID signs the app for **7 days**; after that it stops opening until you install again (the game save stays if you reinstall over it with the same bundle ID). Needs a **Windows PC or a Mac** once, with the phone's USB cable.

1. GitHub > Actions > "Native iOS unsigned IPA (for sideloading)" > Run workflow. When done, download the artifact `Ledger-unsigned-ipa` (a zip containing `Ledger-unsigned.ipa`).
2. Install **Sideloadly** (sideloadly.io) on the PC or Mac. Plug in the phone and trust the computer. (Alternative: AltStore, which can refresh over wifi.)
3. In Sideloadly: drag the IPA in, enter your Apple ID, press Start. On the phone: Settings > General > VPN & Device Management > your Apple ID > Trust. On iOS 16 and later also turn on Settings > Privacy & Security > Developer Mode (phone restarts).
4. Open Ledger. Repeat step 3 every 7 days (Sideloadly/AltStore can refresh).

Limits: no iCloud or push features (the app uses none). The unsigned build has not been installed by anyone yet; the first attempt may need a fix.
