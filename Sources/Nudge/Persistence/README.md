# Persistence boundary

SwiftData stores cached tasks and lists, reminder delivery records, panel state,
and synchronization metadata behind provider-neutral repository protocols.
Corrective Phase 3 adds selected Google Calendar metadata and bounded upcoming
event snapshots so scheduling can restore before a network refresh and retain the
last successful data on failure. Google transport DTOs do not enter the schema.

OAuth credentials and granted-scope metadata that are sensitive remain in Keychain
through a separate abstraction, never in SwiftData or logs.
