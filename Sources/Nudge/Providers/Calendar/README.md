# Calendar provider boundary

Google Calendar REST API is the only supported calendar source. Calendar access,
selection, event retrieval, recurrence expansion, reminder resolution, and links all
come from Google's documented APIs and provider-supplied data. There is no alternate
calendar provider or fallback.

The replacement boundary owns typed Google Calendar calendar-list/event requests,
pagination, bounded event windows, recurrence expansion, selected-calendar settings,
cache/sync metadata, and transport-to-domain mapping. Calendar DTOs and OAuth details
must not escape into reminder scheduling or presentation.

Google event identity, recurrence instance identity, revision data, start/all-day/time-
zone semantics, reminder metadata, and the provider-supplied `htmlLink` map into
provider-neutral values. Open uses only the validated `htmlLink` in the browser; it
never constructs an undocumented event URL.
