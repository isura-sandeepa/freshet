import Testing
@testable import FreshetCore

struct FormatTests {
    @Test func bytesUseBinaryUnits() {
        #expect(Format.bytes(0) == "0 B")
        #expect(Format.bytes(1_023) == "1023 B")
        #expect(Format.bytes(1_024) == "1.00 KB")
        #expect(Format.bytes(1_536) == "1.50 KB")
        #expect(Format.bytes(10 * 1_024 * 1_024) == "10.0 MB")
        #expect(Format.bytes(250 * 1_024 * 1_024 * 1_024) == "250 GB")
    }

    @Test func ratesAreBlankWhenIdle() {
        #expect(Format.rate(0) == "")
        #expect(Format.rate(2_048) == "2.00 KB/s")
        #expect(Format.rateOrZero(0) == "0 B/s")
        #expect(Format.compactRate(1_572_864) == "1.5M")
    }

    @Test func durations() {
        #expect(Format.duration(nil) == "∞")
        #expect(Format.duration(59) == "59s")
        #expect(Format.duration(61) == "1m 1s")
        #expect(Format.duration(3_600 * 26) == "1d 2h")
        #expect(Format.duration(86_400 * 8) == "1w 1d")
    }

    @Test func ratiosAndCounts() {
        #expect(Format.ratio(.infinity) == "∞")
        #expect(Format.ratio(1.23456) == "1.235")
        #expect(Format.count(12, of: 340) == "12 (340)")
        #expect(Format.count(3, of: -1) == "3")
    }
}
