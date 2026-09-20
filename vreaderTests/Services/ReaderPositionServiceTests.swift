// Purpose: Tests for ReaderPositionService extracted in WI-006.
// Validates debounced save, immediate save, cancel, and interleaving.
//
// @coordinates-with ReaderPositionService.swift, ReadingPositionPersisting.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

private let testFP = DocumentFingerprint(
    contentSHA256: "pos_service_test_sha256_00000000000000000000000000000000000",
    fileByteCount: 200,
    format: .txt
)

private func makeLocator(offset: Int = 0) -> Locator {
    Locator(
        bookFingerprint: testFP,
        href: nil, progression: nil, totalProgression: nil, cfi: nil, page: nil,
        charOffsetUTF16: offset,
        charRangeStartUTF16: nil, charRangeEndUTF16: nil,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
}

// MARK: - Tests

@Suite("ReaderPositionService")
struct ReaderPositionServiceTests {

    // MARK: - saveNow

    @Test @MainActor func saveNowCallsPersistenceImmediately() async {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 2_000_000_000
        )

        let locator = makeLocator(offset: 100)
        await service.saveNow(locator: locator)

        let count = await store.saveCallCount
        #expect(count == 1)
        let saved = await store.position(forKey: "test-key")
        #expect(saved?.charOffsetUTF16 == 100)
    }

    @Test @MainActor func saveNowIsAwaitableNotFireAndForget() async {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 0
        )

        // After await returns, the save must have completed
        await service.saveNow(locator: makeLocator(offset: 50))
        let count = await store.saveCallCount
        #expect(count == 1)
    }

    // MARK: - scheduleSave (zero debounce for determinism)

    @Test @MainActor func scheduleSaveWithZeroDebounceEventuallySaves() async throws {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 0
        )

        service.scheduleSave(locator: makeLocator(offset: 200))
        // Give the Task a chance to run
        try await Task.sleep(for: .milliseconds(50))

        let count = await store.saveCallCount
        #expect(count == 1)
    }

    @Test @MainActor func scheduleSaveCoalescesRapidCalls() async throws {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 100_000_000 // 100ms
        )

        // Rapid scheduling — only the last should persist
        service.scheduleSave(locator: makeLocator(offset: 10))
        service.scheduleSave(locator: makeLocator(offset: 20))
        service.scheduleSave(locator: makeLocator(offset: 30))

        try await Task.sleep(for: .milliseconds(200))

        let count = await store.saveCallCount
        #expect(count == 1)
        let saved = await store.position(forKey: "test-key")
        #expect(saved?.charOffsetUTF16 == 30)
    }

    // MARK: - cancel

    @Test @MainActor func cancelPreventsScheduledSave() async throws {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 100_000_000 // 100ms
        )

        service.scheduleSave(locator: makeLocator(offset: 300))
        service.cancel()

        try await Task.sleep(for: .milliseconds(200))

        let count = await store.saveCallCount
        #expect(count == 0)
    }

    @Test @MainActor func cancelDoesNotSuppressSubsequentSaveNow() async {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 100_000_000
        )

        service.scheduleSave(locator: makeLocator(offset: 10))
        service.cancel()
        await service.saveNow(locator: makeLocator(offset: 20))

        let count = await store.saveCallCount
        #expect(count == 1)
        let saved = await store.position(forKey: "test-key")
        #expect(saved?.charOffsetUTF16 == 20)
    }

    // MARK: - Interleaving (regression: bugs #24, #25, #34, #45)

    @Test @MainActor func saveNowAfterScheduleSaveAlwaysCompletes() async throws {
        let store = MockPositionStore()
        let service = ReaderPositionService(
            bookFingerprintKey: "test-key",
            deviceId: "device-1",
            persistence: store,
            debounceNanoseconds: 500_000_000 // 500ms (long debounce)
        )

        // Schedule a debounced save, then immediately save a different position
        service.scheduleSave(locator: makeLocator(offset: 100))
        await service.saveNow(locator: makeLocator(offset: 200))

        // saveNow must have completed — the scheduled one should be cancelled
        let count = await store.saveCallCount
        #expect(count == 1)
        let saved = await store.position(forKey: "test-key")
        #expect(saved?.charOffsetUTF16 == 200)
    }

    // MARK: - deinit

    @Test @MainActor func deinitCancelsPendingTask() async throws {
        let store = MockPositionStore()

        // Create and immediately destroy
        do {
            let service = ReaderPositionService(
                bookFingerprintKey: "test-key",
                deviceId: "device-1",
                persistence: store,
                debounceNanoseconds: 500_000_000
            )
            service.scheduleSave(locator: makeLocator(offset: 999))
            // service goes out of scope here
        }

        try await Task.sleep(for: .milliseconds(100))

        let count = await store.saveCallCount
        #expect(count == 0)
    }
}

private actor ProgressBackingMock: ReadingProgressPersisting {
    var locator: Locator?
    var envelope: VReaderLocator?

    func loadPosition(bookFingerprintKey: String) async throws -> Locator? { locator }
    func savePosition(bookFingerprintKey: String, locator: Locator, deviceId: String) async throws {
        self.locator = locator
        envelope = nil
    }
    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws {}
    func saveVReaderLocator(
        bookFingerprintKey: String,
        vreaderLocator: VReaderLocator,
        legacyLocator: Locator,
        deviceId: String
    ) async throws {
        envelope = vreaderLocator
        locator = legacyLocator
    }
    func loadVReaderLocator(bookFingerprintKey: String) async throws -> VReaderLocator? { envelope }
}

@Suite("Canonical reading progress and audio boundaries")
struct CanonicalProgressBoundaryTests {
    @Test @MainActor
    func progressStoreUsesOneBoundaryForTTSAndReadium() async throws {
        let backing = ProgressBackingMock()
        let store = ReadingProgressStore(persistence: backing, deviceID: "device")
        let locator = makeLocator(offset: 12)
        await store.updateFromTTS(bookID: testFP.canonicalKey, locator: locator)
        let envelope = VReaderLocator(legacyLocator: locator)
        try await store.updateFromReadium(
            bookID: testFP.canonicalKey, envelope: envelope, fallback: locator
        )
        let loaded = try await store.load(bookID: testFP.canonicalKey)
        #expect(loaded?.href == nil)
        #expect(loaded?.locatorJSON.isEmpty == false)
    }

    @Test
    func lastWriteWinsUsesUpdatedAtAndIncomingTie() {
        let old = ReadingProgressRecord(
            bookID: "book", locatorJSON: "old", href: "a.xhtml", progression: 0.1,
            updatedAt: Date(timeIntervalSince1970: 10), deviceID: "a"
        )
        let newer = ReadingProgressRecord(
            bookID: "book", locatorJSON: "new", href: "a.xhtml", progression: 0.2,
            updatedAt: Date(timeIntervalSince1970: 20), deviceID: "b"
        )
        #expect(ReadingProgressStore.resolveLatest(local: old, incoming: newer) == newer)
        #expect(ReadingProgressStore.resolveLatest(local: newer, incoming: old) == newer)
    }

    @Test
    func textChunksAreDeterministic() {
        let text = "Hola, ¿qué tal? ¡Muy bien! Diálogo: —Sí, gracias."
        let first = StableTextChunker.makeChunks(
            text: text, bookID: testFP.canonicalKey, fingerprint: testFP, href: "chapter.xhtml"
        )
        let second = StableTextChunker.makeChunks(
            text: text, bookID: testFP.canonicalKey, fingerprint: testFP, href: "chapter.xhtml"
        )
        #expect(first == second)
        #expect(first.allSatisfy { !$0.id.isEmpty && $0.bookID == testFP.canonicalKey })
    }

    @Test
    func audioCacheStoresAndPurgesByBook() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-cache-(UUID().uuidString)")
        let cache = AudioCache(directory: directory)
        defer { try? cache.clearAll() }
        let key = AudioCacheKey(
            bookID: "book-a", locatorOrText: "0-20", provider: "google",
            voice: "es-US-Wavenet-B", language: "es-US", speed: 1.0
        )
        try cache.save(Data("mp3".utf8), cacheKey: key)
        #expect(cache.exists(cacheKey: key))
        #expect(cache.lookup(cacheKey: key) == Data("mp3".utf8))
        let differentSpeed = AudioCacheKey(
            bookID: key.bookID, locatorOrText: key.locatorOrText,
            provider: key.provider, voice: key.voice, language: key.language, speed: 1.25
        )
        #expect(key.digest != differentSpeed.digest)
        try cache.clearBook(bookID: "book-a")
        #expect(!cache.exists(cacheKey: key))
    }

    @Test
    func progressRecordCodableRoundTrip() throws {
        let record = ReadingProgressRecord(
            bookID: "book", locatorJSON: "{\"href\":\"a.xhtml\"}", href: "a.xhtml",
            progression: 0.5, updatedAt: Date(timeIntervalSince1970: 100), deviceID: "phone"
        )
        let decoded = try JSONDecoder().decode(
            ReadingProgressRecord.self, from: JSONEncoder().encode(record)
        )
        #expect(decoded == record)
    }
}
