# Reminder domain boundary

Reminder identities, lifecycle state, presentation mode, snooze state, source web
links, and deduplication models remain provider-neutral. Google Calendar DTOs,
OAuth details, and transport errors must be mapped before entering this boundary.
Provider-specific calendar types and identifiers do not belong in the reminder domain.
