# CloudKit sync design (prepared, not enabled)

CloudKit is intentionally not connected in this sprint. The local boundary is
`ReadingProgressStore`, and the transport value is `ReadingProgressRecord`.

## Record shape

Future `CKRecord` fields:

- `bookID`: the canonical EPUB identity.
- `locatorJSON`: serialized Readium locator or the engine-neutral fallback.
- `href`: spine resource href when available.
- `progression`: reflowable progression when available.
- `updatedAt`: server-independent last-write timestamp.
- `deviceID`: optional diagnostic/source identifier.

## Conflict policy

Progress uses last-write-wins. The record with the greatest `updatedAt` wins;
ties prefer the incoming record so every device converges deterministically.
The local store remains usable offline and writes the winning value back locally
after a future CloudKit merge.

## Stable book identity

`bookID` is `DocumentFingerprint.canonicalKey`, built from the SHA-256 digest and
byte count of the imported EPUB. It does not use the filename or sandbox path,
so the same EPUB copied to iPhone and iPad gets the same identity. If bytes
change, it is a new book and must not overwrite the old progress.

## Sync scope

Sync later: library metadata, reading progress, bookmarks, and user preferences.
Keep local: synthesized audio blobs, temporary extraction files, diagnostics,
Keychain secrets/API keys, and device-specific cache indexes.

No CloudKit entitlements, containers, schemas, or network calls are part of this
design-only step.
