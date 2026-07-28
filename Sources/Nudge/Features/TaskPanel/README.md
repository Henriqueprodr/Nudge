# Task panel boundary

`TaskPanelWindowController` owns the persistent AppKit window lifecycle and
visible-frame placement. Tasks settings expose explicit Fixed and Free placement
modes. Fixed snaps to the selected corner and rejects window movement. Free enables
the dedicated header grip, restores the last normalized custom position, and keeps
that position valid across resolution and display changes. Selecting a corner
returns to Fixed without discarding the remembered Free position; the menu-bar
Reset Task Panel Position action deliberately clears it and restores top-right
placement without changing the selected display or size.

Expanded mode exposes a full-width AppKit-backed vertical resize grip opposite the
configured anchor edge. Its tracking view provides the native up/down cursor plus
hover and pressed feedback, keeps the anchor stationary, clamps to the display's
visible frame, and persists the resulting height. Compact remains a fixed quick
preset.

`TaskPanelView` keeps its header and concise one-line sync footer pinned around a
lazy scrolling task region, while `TaskPanelStore` displays every cached incomplete,
non-snoozed task matching the persisted Google task-list selection. The legacy
maximum-visible-task value remains readable only for persistence compatibility and
does not truncate the panel. High, Medium, Low, and None
priorities are local Nudge metadata. They sort before the existing title order,
use configurable background tints, survive Google cache reconciliation, and do
not trigger an unnecessary provider refresh.
Phase 5 adds bounded row actions for completion, provider-supplied task links,
local snooze, and local time overrides without transferring window ownership to
the synchronization layer. Action failures and interrupted-completion recovery use
a ten-second dismissible notice while the independent synchronization freshness
footer remains visible.
