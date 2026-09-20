// Purpose: Protocol for reading position save/load operations.
// Decouples position persistence from SwiftData for testability.
//
// Key decisions:
// - Separate from LibraryPersisting and BookPersisting for single responsibility.
// - Methods are async throws for actor-isolated persistence.
// - Uses Locator as the canonical position type.
//
// @coordinates-with: ReadingPosition.swift, Locator.swift

import Foundation

/// Protocol for reading position persistence, enabling mock injection in tests.
/// Conformers must ensure serialized access (e.g., via actor isolation).
protocol ReadingPositionPersisting: Sendable {
    /// Loads the saved reading position for a book.
    func loadPosition(bookFingerprintKey: String) async throws -> Locator?

    /// Saves the current reading position for a book.
    func savePosition(bookFingerprintKey: String, locator: Locator, deviceId: String) async throws

    /// Updates the lastOpenedAt timestamp for a book.
    func updateLastOpened(bookFingerprintKey: String, date: Date) async throws
}

// MARK: - Engine-agnostic envelope (Feature #42 WI-6)

/// Persistence boundary for the engine-agnostic `VReaderLocator` envelope.
/// Kept SEPARATE from `ReadingPositionPersisting` (Gate-4 round-1 Medium): a
/// default no-op/nil on the broad protocol would let a non-`PersistenceActor`
/// conformer silently drop Readium position writes — a hidden data-loss mode.
/// A dedicated protocol makes envelope persistence a hard requirement, so the
/// only thing that can be injected into `ReadiumEPUBReaderViewModel` is a real
/// envelope store (`PersistenceActor`), and the compiler enforces it.
protocol VReaderLocatorPersisting: Sendable {
    /// Saves the engine-agnostic `VReaderLocator` envelope AND the back-compat
    /// legacy `Locator` in one transaction (dual-write). Used by the Readium
    /// engine so a flag-OFF reopen still finds an approximate legacy position.
    func saveVReaderLocator(
        bookFingerprintKey: String,
        vreaderLocator: VReaderLocator,
        legacyLocator: Locator,
        deviceId: String
    ) async throws

    /// Loads the engine-agnostic `VReaderLocator` envelope for a book, or nil
    /// when none exists / the row predates the column / the blob fails to decode.
    func loadVReaderLocator(bookFingerprintKey: String) async throws -> VReaderLocator?
}

// MARK: - Canonical progress boundary

/// CloudKit-ready transport shape for one book's reading progress. The local
/// SwiftData model remains the durable store; this value is the only shape
/// that readers, TTS, and a future sync adapter need to exchange.
struct ReadingProgressRecord: Codable, Equatable, Sendable {
    let bookID: String
    let locatorJSON: String
    let href: String?
    let progression: Double?
    let updatedAt: Date
    let deviceID: String?
}

/// The one persistence capability required by `ReadingProgressStore`.
protocol ReadingProgressPersisting: ReadingPositionPersisting, VReaderLocatorPersisting {
    func loadProgressUpdatedAt(bookID: String) async throws -> Date?
}

extension ReadingProgressPersisting {
    /// Backward-compatible default for test doubles; the real SwiftData
    /// implementation returns the persisted `ReadingPosition.updatedAt`.
    func loadProgressUpdatedAt(bookID: String) async throws -> Date? { nil }
}

/// Centralizes local progress reads/writes for visual reading and TTS.
/// Callers never need to know whether the backing store is SwiftData, a test
/// double, or a future CloudKit reconciler.
@MainActor
final class ReadingProgressStore {
    private let persistence: any ReadingProgressPersisting
    private let deviceID: String?

    init(persistence: any ReadingProgressPersisting, deviceID: String? = nil) {
        self.persistence = persistence
        self.deviceID = deviceID
    }

    func load(bookID: String) async throws -> ReadingProgressRecord? {
        if let envelope = try await persistence.loadVReaderLocator(bookFingerprintKey: bookID),
           let locator = envelope.legacyLocator {
            return Self.record(
                bookID: bookID, locator: locator, locatorJSON: envelope.readiumLocatorJSON,
                updatedAt: try await persistence.loadProgressUpdatedAt(bookID: bookID)
            )
        }
        guard let locator = try await persistence.loadPosition(bookFingerprintKey: bookID) else {
            return nil
        }
        return Self.record(
            bookID: bookID, locator: locator,
            updatedAt: try await persistence.loadProgressUpdatedAt(bookID: bookID)
        )
    }

    func loadReadiumEnvelope(bookID: String) async throws -> VReaderLocator? {
        try await persistence.loadVReaderLocator(bookFingerprintKey: bookID)
    }

    /// Persists a visual or TTS position represented by the engine-neutral
    /// locator. The same method is intentionally used by both callers.
    func updateFromTTS(bookID: String, locator: Locator, updatedAt: Date = Date()) async throws {
        try await persistence.savePosition(
            bookFingerprintKey: bookID, locator: locator, deviceId: deviceID ?? ""
        )
        _ = updatedAt // SwiftData's position boundary timestamps the write.
    }

    /// Persists a Readium locator and its engine-neutral fallback atomically.
    func updateFromReadium(
        bookID: String,
        locatorJSON: String,
        fallback: Locator,
        updatedAt: Date = Date()
    ) async throws {
        guard fallback.bookFingerprint.canonicalKey == bookID else {
            throw PersistenceError.recordNotFound("Locator fingerprint does not match book ID")
        }
        let envelope = VReaderLocator(
            fingerprintKey: bookID,
            originalFormat: fallback.bookFingerprint.format,
            engine: .readium,
            readiumLocatorJSON: locatorJSON,
            legacyLocator: fallback
        )
        try await persistence.saveVReaderLocator(
            bookFingerprintKey: bookID,
            vreaderLocator: envelope,
            legacyLocator: fallback,
            deviceId: deviceID ?? ""
        )
        _ = updatedAt
    }

    func updateFromReadium(
        bookID: String, envelope: VReaderLocator, fallback: Locator,
        updatedAt: Date = Date()
    ) async throws {
        guard envelope.fingerprintKey == bookID,
              fallback.bookFingerprint.canonicalKey == bookID else {
            throw PersistenceError.recordNotFound("Progress envelope fingerprint does not match book ID")
        }
        try await persistence.saveVReaderLocator(
            bookFingerprintKey: bookID,
            vreaderLocator: envelope,
            legacyLocator: fallback,
            deviceId: deviceID ?? ""
        )
        _ = updatedAt
    }

    /// Last-write-wins resolver used by the future local/CloudKit merge path.
    static func resolveLatest(
        local: ReadingProgressRecord?, incoming: ReadingProgressRecord?
    ) -> ReadingProgressRecord? {
        switch (local, incoming) {
        case (nil, let incoming): return incoming
        case (let local, nil): return local
        case (let local?, let incoming?):
            return incoming.updatedAt >= local.updatedAt ? incoming : local
        }
    }

    private static func record(
        bookID: String, locator: Locator, locatorJSON: String? = nil,
        updatedAt: Date? = nil
    ) -> ReadingProgressRecord {
        let json = locatorJSON ?? ((try? String(
            decoding: JSONEncoder().encode(locator), as: UTF8.self
        )) ?? "{}")
        return ReadingProgressRecord(
            bookID: bookID,
            locatorJSON: json,
            href: locator.href,
            progression: locator.progression,
            updatedAt: updatedAt ?? Date(),
            deviceID: nil
        )
    }
}

extension PersistenceActor: ReadingProgressPersisting {}
