// Purpose: Shared protocol for TTS providers (system and HTTP-based).
// Defines the interface for synthesizing text to audio data.
//
// Key decisions:
// - Async/throws for network-based providers.
// - Chunked synthesis with progress callback for long texts.
// - Sendable for safe use across concurrency contexts.
// - Error type covers network, HTTP, cancellation, and config issues.
//
// @coordinates-with: HTTPTTSProvider.swift, TTSService.swift

import Foundation
import CryptoKit

/// A deterministic, engine-neutral text unit shared by synthesis and cache.
struct TextChunk: Codable, Equatable, Hashable, Sendable {
    let id: String
    let bookID: String
    let href: String
    let startLocator: Locator
    let endLocator: Locator
    let text: String
    let sequence: Int
}

/// Complete identity for a synthesized audio blob. `text` is retained as the
/// stable range fallback when a provider is called before a Readium CFI exists.
struct AudioCacheKey: Codable, Equatable, Hashable, Sendable {
    let bookID: String
    let locatorOrText: String
    let provider: String
    let voice: String
    let language: String
    let speed: Double

    var digest: String {
        let raw = "\(bookID)|\(locatorOrText)|\(provider)|\(voice)|\(language)|\(speed)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Sentence-boundary segmentation for TTS. It never sends a whole chapter by
/// default and derives IDs from stable content/ranges rather than array order.
enum StableTextChunker {
    static func makeChunks(
        text: String,
        bookID: String,
        fingerprint: DocumentFingerprint,
        href: String,
        maxCharacters: Int = HTTPTTSProvider.maxChunkLength
    ) -> [TextChunk] {
        let rawChunks = HTTPTTSProvider.chunkText(text).flatMap {
            split($0, maxCharacters: maxCharacters)
        }
        var searchStart = 0
        return rawChunks.enumerated().map { sequence, chunk in
            let nsText = text as NSString
            let found = nsText.range(
                of: chunk.trimmingCharacters(in: .whitespacesAndNewlines),
                options: [], range: NSRange(location: searchStart, length: nsText.length - searchStart)
            )
            let start = found.location == NSNotFound ? searchStart : found.location
            let length = found.location == NSNotFound ? chunk.utf16.count : found.length
            searchStart = min(nsText.length, start + length)
            let total = max(nsText.length, 1)
            let startLocator = Locator(
                bookFingerprint: fingerprint, href: href,
                progression: Double(start) / Double(total), totalProgression: nil,
                cfi: nil, page: nil, charOffsetUTF16: start,
                charRangeStartUTF16: start, charRangeEndUTF16: start + length,
                textQuote: chunk, textContextBefore: nil, textContextAfter: nil
            )
            let endLocator = Locator(
                bookFingerprint: fingerprint, href: href,
                progression: Double(start + length) / Double(total), totalProgression: nil,
                cfi: nil, page: nil, charOffsetUTF16: start + length,
                charRangeStartUTF16: start, charRangeEndUTF16: start + length,
                textQuote: chunk, textContextBefore: nil, textContextAfter: nil
            )
            let identity = "\(bookID)|\(href)|\(start)|\(start + length)|\(chunk)|\(sequence)"
            let digest = SHA256.hash(data: Data(identity.utf8))
            let id = digest.map { String(format: "%02x", $0) }.joined()
            return TextChunk(
                id: id, bookID: bookID, href: href,
                startLocator: startLocator, endLocator: endLocator,
                text: chunk, sequence: sequence
            )
        }
    }

    private static func split(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: min(maxCharacters, text.distance(from: start, to: text.endIndex)))
            result.append(String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
            start = end
        }
        return result.filter { !$0.isEmpty }
    }
}

// MARK: - TTSProvider Protocol

/// Protocol for text-to-speech providers that return audio data.
/// System TTS (AVSpeechSynthesizer) does not conform — it uses a separate path.
/// HTTP-based TTS providers conform to this protocol.
protocol TTSProvider: Sendable {
    /// Synthesizes a single text segment into audio data.
    func synthesize(text: String, voice: String) async throws -> Data

    /// Synthesizes text in chunks, calling onChunk for each completed chunk.
    /// Parameters: chunkIndex, totalChunks, audioData
    func synthesizeChunked(
        text: String,
        voice: String,
        onChunk: @Sendable (Int, Int, Data) -> Void
    ) async throws

    /// Cancels any in-progress synthesis.
    func cancel()

    /// Whether the provider has been cancelled.
    var isCancelled: Bool { get }
}

// MARK: - TTSProviderError

/// Errors from TTS provider operations.
enum TTSProviderError: Error, Equatable, Sendable {
    /// Network request failed.
    case networkError(String)

    /// HTTP response returned a non-2xx status code.
    case httpError(Int)

    /// Synthesis was cancelled.
    case cancelled

    /// Configuration is invalid.
    case invalidConfig(String)

    /// No audio data in response.
    case emptyResponse
}

// MARK: - URLSessionProtocol

/// Protocol abstracting URLSession for testability.
protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// URLSession conforms to URLSessionProtocol.
extension URLSession: URLSessionProtocol {}
