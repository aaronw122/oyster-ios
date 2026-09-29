import Foundation

/// JSON coders configured for the Oyster wire format.
///
/// Server timestamps are whole-second UTC with a `Z` suffix
/// (`2026-09-29T12:42:10Z`); dates encode the same way, dropping any
/// fractional seconds.
public enum ContractCoding {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
