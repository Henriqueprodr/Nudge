# Nudge 0.1.0

The first open-source release of Nudge, a native macOS menu-bar app for direct
on-screen Google Calendar reminders and a persistent Google Tasks corner panel.

## Before installing

This ZIP is ad-hoc signed and is **not Developer ID signed or notarized**. macOS
will require manual approval: Control-click `Nudge.app`, choose **Open**, and confirm
**Open**. If necessary, use **System Settings → Privacy & Security → Open Anyway**.
Do not disable Gatekeeper globally.

The public app contains **no Google OAuth client ID or client secret**. Follow the
[Google setup and import instructions](https://github.com/Henriqueprodr/Nudge#connect-your-google-account)
to create a Desktop OAuth client and import its downloaded JSON from Nudge's Account
settings.

Download both `Nudge-v0.1.0.zip` and its checksum, then verify with:

```sh
shasum -a 256 -c Nudge-v0.1.0.zip.sha256
```

Requires macOS 14 or later. The app is universal for Apple silicon and Intel Macs.
