# Linux contracts

The macOS app is the source of truth for the v1 payload shapes. Linux does not
need byte-for-byte compatibility with every macOS field, but it uses the same
envelope so the two implementations can be compared and the fixtures shared.

## Snapshot envelope

`schema_version: 1`, `source`, `written_at` (RFC 3339), `payload`.

The daemon writes one `<source>.json` per widget under
`$XDG_DATA_HOME/deck/`, and one `fetch-<source>.json` with the last outcome.
Tokens never appear in either file.

## Fixtures

Payload fixtures copied from the macOS tests live in `fixtures/` as the Linux
parsers are ported. L1 has no payload parser yet; the first fixtures arrive
with LiveBox/LogBox in L3/L5.

## Status values

`ok`, `notConfigured`, `authOrTarget`, `unreachable`, `badResponse`,
`credentialsUnavailable`, `queryRejected` — matching the macOS `FetchOutcome`
copy, so the faces can use the same wording.
