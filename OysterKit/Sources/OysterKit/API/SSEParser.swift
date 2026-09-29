/// Incremental `text/event-stream` parser (WHATWG HTML §9.2.6), fed one byte
/// at a time so chunk boundaries never matter.
///
/// Lines end in CRLF, LF, or CR. `data` fields accumulate (joined by LF) until
/// a blank line dispatches the event; comments (`:`-prefixed lines) and every
/// other field (`event`, `id`, `retry`, unknown names) are ignored. An event
/// left unterminated when the stream ends is never dispatched.
struct SSEParser {
    private static let lf: UInt8 = 0x0A
    private static let cr: UInt8 = 0x0D
    private static let colon: UInt8 = 0x3A
    private static let space: UInt8 = 0x20
    private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let dataField: [UInt8] = Array("data".utf8)

    private var line: [UInt8] = []
    private var data: [UInt8] = []
    private var hasData = false
    private var lastWasCR = false
    /// Bytes seen at stream start while checking for a leading UTF-8 BOM;
    /// `nil` once that check is over.
    private var prefix: [UInt8]? = []

    /// Consumes one byte; returns the event's data when this byte completes one.
    mutating func consume(_ byte: UInt8) -> String? {
        if var pending = prefix {
            pending.append(byte)
            if Self.bom.starts(with: pending) {
                if pending.count == Self.bom.count { prefix = nil } else { prefix = pending }
                return nil
            }
            prefix = nil
            // Not a BOM: replay what was held back. Only the last byte can end a line.
            for held in pending.dropLast() { line.append(held) }
            return consumeUnprefixed(pending[pending.count - 1])
        }
        return consumeUnprefixed(byte)
    }

    private mutating func consumeUnprefixed(_ byte: UInt8) -> String? {
        switch byte {
        case Self.lf where lastWasCR:
            lastWasCR = false
            return nil
        case Self.lf, Self.cr:
            lastWasCR = byte == Self.cr
            defer { line.removeAll(keepingCapacity: true) }
            return processLine()
        default:
            lastWasCR = false
            line.append(byte)
            return nil
        }
    }

    private mutating func processLine() -> String? {
        if line.isEmpty { return dispatch() }
        if line[0] == Self.colon { return nil }

        let field: ArraySlice<UInt8>
        var value: ArraySlice<UInt8>
        if let colon = line.firstIndex(of: Self.colon) {
            field = line[..<colon]
            value = line[(colon + 1)...]
            if value.first == Self.space { value = value.dropFirst() }
        } else {
            field = line[...]
            value = []
        }
        if field.elementsEqual(Self.dataField) {
            if hasData { data.append(Self.lf) }
            data.append(contentsOf: value)
            hasData = true
        }
        return nil
    }

    private mutating func dispatch() -> String? {
        guard hasData else { return nil }
        defer {
            data.removeAll(keepingCapacity: true)
            hasData = false
        }
        return String(decoding: data, as: UTF8.self)
    }
}
