//
//  ZipArchive.swift
//  manather
//
//  A tiny, dependency-free ZIP reader. The app is sandboxed, so we can't shell
//  out to `unzip`/`ditto`; instead we parse the archive ourselves and inflate
//  entries with Apple's Compression framework. This is enough to read the ZIPs
//  produced on export (via NSFileCoordinator) and round-trip a shared library.
//
//  Supported: stored (method 0) and deflate (method 8) entries. Not supported:
//  ZIP64, encryption — neither occurs for the small libraries we export.
//

import Foundation
import Compression

enum ZipArchiveError: Error, LocalizedError {
    case notAZip
    case corrupt
    case inflateFailed

    var errorDescription: String? {
        switch self {
        case .notAZip:       return "The file isn't a valid ZIP archive."
        case .corrupt:       return "The ZIP archive is damaged or incomplete."
        case .inflateFailed: return "A file inside the archive couldn't be decompressed."
        }
    }
}

enum ZipArchive {

    /// Extracts every file in `data` into `destination`, recreating the folder
    /// structure stored in the archive.
    static func unzip(_ data: Data, to destination: URL) throws {
        let bytes = [UInt8](data)
        let total = bytes.count

        guard let eocd = findEOCD(bytes) else { throw ZipArchiveError.notAZip }
        let entryCount = readU16(bytes, eocd + 10)
        var cd = Int(readU32(bytes, eocd + 16))

        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for _ in 0..<entryCount {
            guard cd + 46 <= total, readU32(bytes, cd) == 0x02014b50 else {
                throw ZipArchiveError.corrupt
            }
            let method      = readU16(bytes, cd + 10)
            let compSize    = Int(readU32(bytes, cd + 20))
            let uncompSize  = Int(readU32(bytes, cd + 24))
            let nameLen     = readU16(bytes, cd + 28)
            let extraLen    = readU16(bytes, cd + 30)
            let commentLen  = readU16(bytes, cd + 32)
            let localOffset = Int(readU32(bytes, cd + 42))

            let nameStart = cd + 46
            guard nameStart + nameLen <= total else { throw ZipArchiveError.corrupt }
            let name = String(decoding: bytes[nameStart ..< nameStart + nameLen], as: UTF8.self)
            cd = nameStart + nameLen + extraLen + commentLen

            // Skip directory markers and anything trying to escape the dest dir.
            if name.hasSuffix("/") { continue }
            if name.contains("..") || name.hasPrefix("/") { continue }

            // Use the LOCAL header to find where the data starts (its extra-field
            // length can differ from the central directory's), but trust the
            // central directory for the byte counts — robust against data
            // descriptors (which leave the local sizes as 0).
            guard localOffset + 30 <= total, readU32(bytes, localOffset) == 0x04034b50 else {
                throw ZipArchiveError.corrupt
            }
            let lNameLen  = readU16(bytes, localOffset + 26)
            let lExtraLen = readU16(bytes, localOffset + 28)
            let dataStart = localOffset + 30 + lNameLen + lExtraLen
            guard dataStart + compSize <= total else { throw ZipArchiveError.corrupt }

            let compressed = Array(bytes[dataStart ..< dataStart + compSize])
            let output: [UInt8]
            switch method {
            case 0: output = compressed
            case 8: output = try inflate(compressed, expectedSize: uncompSize)
            default: throw ZipArchiveError.corrupt
            }

            let outURL = destination.appendingPathComponent(name)
            try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(output).write(to: outURL)
        }
    }

    // MARK: - Deflate

    private static func inflate(_ input: [UInt8], expectedSize: Int) throws -> [UInt8] {
        if expectedSize == 0 { return [] }
        var dst = [UInt8](repeating: 0, count: expectedSize)
        let written = input.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { out in
                // COMPRESSION_ZLIB == raw DEFLATE (RFC 1951), which is exactly
                // what ZIP method 8 stores.
                compression_decode_buffer(out.baseAddress!, expectedSize,
                                          src.baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipArchiveError.inflateFailed }
        return dst
    }

    // MARK: - Byte helpers

    /// Scan backwards for the End Of Central Directory signature.
    private static func findEOCD(_ b: [UInt8]) -> Int? {
        let n = b.count
        guard n >= 22 else { return nil }
        let lowest = max(0, n - 22 - 0xFFFF) // 0xFFFF = max comment length
        var i = n - 22
        while i >= lowest {
            if readU32(b, i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func readU16(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) | (Int(b[o + 1]) << 8)
    }

    private static func readU32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
}
