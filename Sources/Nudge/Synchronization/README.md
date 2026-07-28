# Synchronization boundary

`GoogleTasksSyncCoordinator` owns refresh policy, overlap prevention,
one queued follow-up, capped exponential backoff with jitter, cache
reconciliation, and stale/offline metadata. The default periodic interval is
fifteen minutes. Launch, authentication, wake, manual, and periodic events trigger
refreshes. `GoogleTasksActionCoordinator` owns durable pending completion,
optimistic cache updates, idempotent rollback/recovery, temporary dismissible
action notices, double-submit prevention, local snooze/time overrides, and one
coalesced post-action refresh request. Completed or rolled-back journal records are
removed so historical failures cannot reappear after relaunch.

Corrective Phase 3 adds a distinct `GoogleCalendarSyncCoordinator` with its own
in-flight/coalescing state, bounded Calendar cache reconciliation, retry policy,
and stale/offline metadata. Launch, authentication, wake, manual, settings-change,
and five-minute periodic events trigger Calendar refresh. Calendar and Tasks may
share OAuth/token refresh infrastructure, but one provider's refresh, cache, or
failure state must never masquerade as the other's.
