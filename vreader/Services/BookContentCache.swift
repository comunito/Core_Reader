// Purpose: Shared cache for loaded book text content.
// Ensures each book file is parsed only once and shared across coordinators
// (AI, search, TTS, unified reader).
//
// Key decisions:
// - @MainActor for safe access from SwiftUI views.
// - Caches by file URL path to avoid redundant loads.
// - Supports TXT and MD formats via direct file reading.
//   EPUB and PDF are loaded by their respective coordinators.
// - invalidate() clears cache for a specific file URL.
//
// @coordinates-with: ReaderContainerView.swift, ReaderAICoordinator.swift,
//   ReaderUnifiedCoordinator.swift, ReaderSearchCoordinator.swift

import Foundation

/// Filesystem-backed cache for synthesized audio. Audio bytes never enter
/// SwiftData; metadata is a small JSON sidecar so a book can be purged without
/// scanning opaque blobs.
struct AudioCache {
    private struct Metadata: Codable {
        let bookID: String
        let cacheKey: String
        let byteCount: Int
        let createdAt: Date
    }

    let directory: URL

    init(directory: URL = FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask
    )[0].appendingPathComponent("AudioCache", isDirectory: true)) {
        self.directory = directory
    }

    func lookup(cacheKey: AudioCacheKey) -> Data? {
        let url = audioURL(for: cacheKey)
        guard FileManager.default.fileExists(atPath: metadataURL(for: cacheKey).path) else { return nil }
        return try? Data(contentsOf: url)
    }

    func exists(cacheKey: AudioCacheKey) -> Bool {
        FileManager.default.fileExists(atPath: audioURL(for: cacheKey).path)
    }

    func save(_ audioData: Data, cacheKey: AudioCacheKey) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try audioData.write(to: audioURL(for: cacheKey), options: .atomic)
        let metadata = Metadata(
            bookID: cacheKey.bookID, cacheKey: cacheKey.digest,
            byteCount: audioData.count, createdAt: Date()
        )
        try JSONEncoder().encode(metadata).write(to: metadataURL(for: cacheKey), options: .atomic)
    }

    func clearBook(bookID: String) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
                  metadata.bookID == bookID else { continue }
            try? FileManager.default.removeItem(at: audioURL(forDigest: metadata.cacheKey))
            try FileManager.default.removeItem(at: url)
        }
    }

    func clearAll() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func audioURL(for key: AudioCacheKey) -> URL {
        audioURL(forDigest: key.digest)
    }

    private func audioURL(forDigest digest: String) -> URL {
        directory.appendingPathComponent("\(digest).mp3")
    }

    private func metadataURL(for key: AudioCacheKey) -> URL {
        directory.appendingPathComponent("\(key.digest).json")
    }
}

/// Shared cache that loads book text content once and serves it to all consumers.
@MainActor
final class BookContentCache {

    /// Cached text content keyed by file URL path.
    private var cache: [String: String] = [:]

    /// Returns cached text content for a book file URL, loading it on first access.
    /// Returns nil if the file cannot be read or is empty.
    func getText(for fileURL: URL, format: String) async -> String? {
        let key = fileURL.path

        if let cached = cache[key] {
            return cached
        }

        let url = fileURL
        let text: String? = await Task.detached {
            switch format.lowercased() {
            case "txt", "md":
                // Use sample-based encoding detection to match TXTService decode path (bug #92)
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                    return nil
                }
                let hintName = TXTService.detectEncodingFromSample(data)
                if let enc = TXTService.encodingFromName(hintName),
                   let decoded = String(data: data, encoding: enc) {
                    return decoded
                }
                return try? String(contentsOf: url, encoding: .utf8)
            default:
                return nil
            }
        }.value

        guard let text, !text.isEmpty else {
            return nil
        }

        cache[key] = text
        return text
    }

    /// Clears cached content for a specific file URL.
    func invalidate(for fileURL: URL) {
        cache.removeValue(forKey: fileURL.path)
    }

    /// Clears all cached content.
    func invalidateAll() {
        cache.removeAll()
    }
}
