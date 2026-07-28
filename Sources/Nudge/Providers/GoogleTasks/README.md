# Google Tasks provider boundary

Phases 4 and 5 implement the Google Tasks provider with Apple frameworks only:

- OAuth 2.0 Authorization Code with PKCE and a system-browser loopback callback.
- Keychain-only access and refresh token persistence.
- Paginated `URLSession` reads plus idempotent task-completion PATCH requests.
- The `tasks` scope required for completion; legacy read-only credentials require
  explicit consent again before mutation.
- Provider-supplied `webViewLink` mapping for supported task opening.
- Explicit transport-to-domain mapping that keeps Google due values date-only.

Corrective Phase 3 introduced Google Calendar and refactored OAuth into a shared
Google foundation. Tasks retains its own client, cache, refresh coordinator, and
errors. Shared credentials must record and validate the union of granted Calendar
and Tasks scopes; adding a scope requires explicit re-consent and must not discard
either provider's cache.

To exercise real sign-in, enable the Google Tasks API, create a Google OAuth
**Desktop app** client, and provide its client ID as the
`GOOGLE_OAUTH_CLIENT_ID` environment variable or Xcode build setting. The legacy
Tasks-named setting remains a compatibility alias. When Google's
token endpoint requires the Desktop client secret, enter it through the masked
Settings field so Nudge stores it separately in Keychain. Do not commit local
client configuration or any token.
