# Scheduling boundary

The injected-clock scheduler owns deterministic delivery deduplication, snooze,
dismiss, expiry, and missed-window policy. The presentation coordinator uses one
cancellable one-shot deadline to feed due reminders into the independent overlay;
it does not poll.

Source opening is routed by provider-neutral source metadata. Google Calendar
reminders use only a validated provider-supplied `htmlLink` through the workspace
browser opener. A missing or rejected link is reported to the overlay and is not
replaced with a constructed URL.

Corrective Phase 3 supplies cached Google Calendar candidates and a separate, coalesced
Calendar refresh coordinator. Refresh completion rebuilds this scheduler; neither
Calendar network state nor Calendar DTOs belong in the overlay lifecycle.
