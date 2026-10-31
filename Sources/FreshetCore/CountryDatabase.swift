import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Country lookup for peer IPs from the bundled DB-IP Lite database (CC BY 4.0, attribution
/// to DB-IP.com required wherever the result is shown).
///
/// File format, big-endian: "FCDB", UInt16 version 1, UInt32 IPv4 count, UInt32 IPv6 count, then
/// IPv4 entries (UInt32 range start, 2-byte country code) and IPv6 entries (UInt64 start of the
/// /64, 2-byte country code). Ranges are contiguous; "--" marks unassigned space.
public final class CountryDatabase: Sendable {
    private let v4Starts: [UInt32]
    private let v4Codes: [UInt16]
    private let v6Starts: [UInt64]
    private let v6Codes: [UInt16]

    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 14, bytes[0] == 0x46, bytes[1] == 0x43, bytes[2] == 0x44, bytes[3] == 0x42 else { return nil }
        func u32(_ at: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[at + $1]) } }
        func u64(_ at: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(bytes[at + $1]) } }
        let version = Int(bytes[4]) << 8 | Int(bytes[5])
        let n4 = Int(u32(6))
        let n6 = Int(u32(10))
        guard version == 1, bytes.count == 14 + n4 * 6 + n6 * 10 else { return nil }
        var starts4 = [UInt32](), codes4 = [UInt16](), starts6 = [UInt64](), codes6 = [UInt16]()
        starts4.reserveCapacity(n4)
        codes4.reserveCapacity(n4)
        starts6.reserveCapacity(n6)
        codes6.reserveCapacity(n6)
        var offset = 14
        for _ in 0..<n4 {
            starts4.append(u32(offset))
            codes4.append(UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5]))
            offset += 6
        }
        for _ in 0..<n6 {
            starts6.append(u64(offset))
            codes6.append(UInt16(bytes[offset + 8]) << 8 | UInt16(bytes[offset + 9]))
            offset += 10
        }
        v4Starts = starts4
        v4Codes = codes4
        v6Starts = starts6
        v6Codes = codes6
    }

    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.init(data: data)
    }

    /// Two-letter ISO country code, or nil for private, unassigned or unparsable addresses.
    public func country(for ip: String) -> String? {
        var v4 = in_addr()
        if inet_pton(AF_INET, ip, &v4) == 1 {
            let value = UInt32(bigEndian: v4.s_addr)
            return code(Self.lastIndex(v4Starts, atMost: value).map { v4Codes[$0] })
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, ip, &v6) == 1 {
            let bytes = withUnsafeBytes(of: &v6) { Array($0) }
            if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {  // IPv4-mapped
                let value = bytes[12...15].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                return code(Self.lastIndex(v4Starts, atMost: value).map { v4Codes[$0] })
            }
            let prefix = bytes[0..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            return code(Self.lastIndex(v6Starts, atMost: prefix).map { v6Codes[$0] })
        }
        return nil
    }

    /// The flag emoji for a two-letter country code.
    public static func flag(for code: String) -> String {
        let base: UInt32 = 0x1F1E6
        let letters = code.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "" }
        var result = ""
        for letter in letters {
            if let scalar = Unicode.Scalar(base + letter.value - 65) { result.unicodeScalars.append(scalar) }
        }
        return result
    }

    private func code(_ raw: UInt16?) -> String? {
        guard let raw else { return nil }
        let first = UInt8(raw >> 8), second = UInt8(raw & 0xff)
        guard (65...90).contains(first), (65...90).contains(second) else { return nil }
        return String(decoding: [first, second], as: UTF8.self)
    }

    private static func lastIndex<T: Comparable>(_ starts: [T], atMost value: T) -> Int? {
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= value { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}
