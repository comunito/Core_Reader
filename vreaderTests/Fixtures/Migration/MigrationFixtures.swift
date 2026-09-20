// Purpose: Test fixtures for schema migration testing.
// Each schema version should have corresponding fixture data
// that exercises all model fields and relationships.
//
// Layout:
// - vreaderTests/Fixtures/Migration/MigrationFixtures.swift — fixture factory
// - Future: vreaderTests/Fixtures/Migration/V1toV2/ — migration test data

import Foundation
@testable import vreader

/// Factory for creating test fixture data for migration testing.
enum MigrationFixtures {

    /// Builds a tiny copyright-free EPUB in a temp directory for locator,
    /// extraction, hashing, and chunking tests. It is deliberately generated
    /// from source strings so the fixture remains reviewable in git.
    static func makeReadingPositionEPUB() throws -> URL {
        let container = """
        <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">core-reader-fixture</dc:identifier><dc:title>Core Reader Fixture</dc:title><dc:language>es</dc:language></metadata><manifest><item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>
        """
        let chapter1 = """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Primero</title></head><body><h1>Capítulo uno</h1><p>Hola, ¿qué tal? Esta prueba contiene acentos, ñ y signos ¡importantes!</p><p>Diálogo: —Sí, gracias —respondió Ana.</p></body></html>
        """
        let chapter2 = """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Segundo</title></head><body><h1>Capítulo dos</h1><p>Segundo capítulo para comprobar navegación y progreso.</p></body></html>
        """
        let nav = """
        <html xmlns="http://www.w3.org/1999/xhtml"><body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="chapter1.xhtml">Uno</a></li><li><a href="chapter2.xhtml">Dos</a></li></ol></nav></body></html>
        """
        let entries = [
            ZIPWriter.Entry(name: "mimetype", data: Data("application/epub+zip".utf8)),
            ZIPWriter.Entry(name: "META-INF/container.xml", data: Data(container.utf8)),
            ZIPWriter.Entry(name: "OEBPS/content.opf", data: Data(opf.utf8)),
            ZIPWriter.Entry(name: "OEBPS/nav.xhtml", data: Data(nav.utf8)),
            ZIPWriter.Entry(name: "OEBPS/chapter1.xhtml", data: Data(chapter1.utf8)),
            ZIPWriter.Entry(name: "OEBPS/chapter2.xhtml", data: Data(chapter2.utf8)),
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-reader-fixture-\(UUID().uuidString).epub")
        try ZIPWriter.createArchive(entries: entries).write(to: url, options: .atomic)
        return url
    }

    // MARK: - DocumentFingerprint Fixtures

    static func sampleEpubFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "abc123def456789012345678901234567890123456789012345678901234abcd",
            fileByteCount: 1_048_576,
            format: .epub
        )
    }

    static func samplePdfFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "def456abc789012345678901234567890123456789012345678901234567ef01",
            fileByteCount: 2_097_152,
            format: .pdf
        )
    }

    static func sampleTxtFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "789012345678901234567890123456789012345678901234567890123456abcd",
            fileByteCount: 32_768,
            format: .txt
        )
    }

    // MARK: - Locator Fixtures

    static func sampleEpubLocator() -> Locator {
        Locator(
            bookFingerprint: sampleEpubFingerprint(),
            href: "chapter1.xhtml",
            progression: 0.42,
            totalProgression: 0.15,
            cfi: "/6/4[chap01]!/4/2/1:0",
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: "It was a dark and stormy night",
            textContextBefore: "Chapter 1. ",
            textContextAfter: ", the wind howled."
        )
    }

    static func samplePdfLocator() -> Locator {
        Locator(
            bookFingerprint: samplePdfFingerprint(),
            href: nil,
            progression: nil,
            totalProgression: 0.05,
            cfi: nil,
            page: 7,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: "Introduction to algorithms",
            textContextBefore: nil,
            textContextAfter: nil
        )
    }

    static func sampleTxtLocator() -> Locator {
        Locator(
            bookFingerprint: sampleTxtFingerprint(),
            href: nil,
            progression: nil,
            totalProgression: 0.5,
            cfi: nil,
            page: nil,
            charOffsetUTF16: 1024,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: "Call me Ishmael",
            textContextBefore: nil,
            textContextAfter: ". Some years ago"
        )
    }

    static func sampleTxtRangeLocator() -> Locator {
        Locator(
            bookFingerprint: sampleTxtFingerprint(),
            href: nil,
            progression: nil,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: 100,
            charRangeEndUTF16: 200,
            textQuote: "selected text",
            textContextBefore: "some ",
            textContextAfter: " more"
        )
    }

    // MARK: - ImportProvenance Fixtures

    static func sampleProvenance() -> ImportProvenance {
        ImportProvenance(
            source: .filesApp,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalURLBookmarkData: nil
        )
    }

    // MARK: - Book Fixtures

    static func sampleEpubBook() -> Book {
        Book(
            fingerprint: sampleEpubFingerprint(),
            title: "Sample EPUB Book",
            author: "Test Author",
            provenance: sampleProvenance()
        )
    }

    static func samplePdfBook() -> Book {
        Book(
            fingerprint: samplePdfFingerprint(),
            title: "Sample PDF Book",
            provenance: ImportProvenance(
                source: .icloudDrive,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000),
                originalURLBookmarkData: Data([0x01, 0x02, 0x03])
            )
        )
    }

    // MARK: - ReadingSession Fixtures

    static func sampleSession(
        fingerprint: DocumentFingerprint? = nil,
        durationSeconds: Int = 1800,
        pagesRead: Int? = 10,
        wordsRead: Int? = 3000
    ) -> ReadingSession {
        let fp = fingerprint ?? sampleEpubFingerprint()
        return ReadingSession(
            bookFingerprint: fp,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            durationSeconds: durationSeconds,
            pagesRead: pagesRead,
            wordsRead: wordsRead,
            deviceId: "test-device-001"
        )
    }
}
