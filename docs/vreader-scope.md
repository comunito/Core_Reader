# VReader scope for Core Reader

## Keep and prioritize

- EPUB import, library, metadata, and local file identity.
- Readium opening, navigation, paginated/scroll layouts, and locator restore.
- One reading-progress boundary shared by visual reading and TTS.
- TTS provider protocol, Google Cloud provider, deterministic chunks, filesystem
  audio cache, background-capable playback, and Settings.
- Existing SwiftData persistence and Keychain storage.

## Temporarily hide or defer

- AI assistant, translation, WebDAV, OPDS/book-source integrations, and other
  experimental reader surfaces. They remain in the repository for now to avoid
  destructive removal while the MVP stabilizes.
- Lock-screen media controls and CloudKit/iCloud synchronization.

## Out of scope for this product

- PDF, Mac, Android, web, and additional cloud providers.
- OpenAI, ElevenLabs, local TTS, and any provider beyond Google in this sprint.

The scope document is a product boundary, not a request to delete VReader
modules. Removal can happen after the iPhone/iPad EPUB MVP is device-verified.
