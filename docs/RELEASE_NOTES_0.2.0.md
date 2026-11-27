# Nudge 0.2.0

A new look, a bird, and task nags. Nudge now chases unfinished Google Tasks as well as
upcoming calendar events.

## What's new

- **The Nudge bird.** An optional animated mascot. It flies in and perches on calendar
  alerts, walks along your Dock between them, whistles, and comments at a Mild, Spicy,
  or Unhinged level. Summon or mute it from the menu bar, and add your own lines in
  `~/Library/Application Support/Nudge/MascotLines.json`.
- **Task nags.** Overdue and forgotten Google Tasks get their own on-screen alerts,
  built from the local cache with no extra Google API calls. Mark a task done from the
  alert, snooze it for an hour, or choose **Not today**. Nags respect quiet hours and a
  daily limit.
- **Sessions that stay signed in.** A single failed Google request no longer signs you
  out. If Google does end the session, an on-screen alert explains why and offers a
  one-click **Sign in** button.
- **New hand logo and hand-drawn design.** The menu-bar icon, app icon, alerts, Tasks
  panel, and Settings all use the new ink style. Settings gained a **Bird** tab and a
  **Task nags** section.
- **Launch at login** is turned on once automatically for copies installed in
  Applications. The Settings toggle stays in charge afterwards.

## Before installing

This ZIP is ad-hoc signed and is **not Developer ID signed or notarized**, so macOS
blocks the first launch. Open `Nudge.app` once, click **Done**, then go to
**System Settings → Privacy & Security** and choose **Open Anyway** for Nudge. On
macOS 14 you can instead Control-click `Nudge.app`, choose **Open**, and confirm.
Do not disable Gatekeeper globally.

The public app contains **no Google OAuth client ID or client secret**. Follow the
[Google setup and import instructions](https://github.com/Henriqueprodr/Nudge#connect-your-google-account)
to create a Desktop OAuth client and import its downloaded JSON from Nudge's Account
settings.

Download both `Nudge-v0.2.0.zip` and its checksum, then verify with:

```sh
shasum -a 256 -c Nudge-v0.2.0.zip.sha256
```

Requires macOS 14 or later. The app is universal for Apple silicon and Intel Macs.
