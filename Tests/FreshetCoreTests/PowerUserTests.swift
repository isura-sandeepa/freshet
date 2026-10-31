import Foundation
import Testing
@testable import FreshetCore

struct PowerUserTests {
    @Test func trackerBoxRoundTrips() {
        let text = "udp://a.example:1337/announce\nhttps://b.example/announce\n\n\nudp://c.example:80\nudp://a.example:1337/announce\n"
        let parsed = TrackerEdit.parse(text)
        #expect(parsed == [TrackerEdit(url: "udp://a.example:1337/announce", tier: 0),
                           TrackerEdit(url: "https://b.example/announce", tier: 0),
                           TrackerEdit(url: "udp://c.example:80", tier: 1)])
        #expect(TrackerEdit.format(parsed) == "udp://a.example:1337/announce\nhttps://b.example/announce\n\nudp://c.example:80")
        #expect(TrackerEdit.parse("  \n\n").isEmpty)
    }

    @Test func peerAddresses() {
        #expect(PeerAddress("1.2.3.4:6881") == PeerAddress("1.2.3.4:6881"))
        #expect(PeerAddress("1.2.3.4:6881")?.port == 6881)
        #expect(PeerAddress("[2001:db8::1]:51413")?.ip == "2001:db8::1")
        #expect(PeerAddress("1.2.3.4") == nil)
        #expect(PeerAddress("1.2.3.400:80") == nil)
        #expect(PeerAddress("host.example:80") == nil)
        #expect(PeerAddress("1.2.3.4:0") == nil)
        #expect(PeerAddress("2001:db8::1:80") == nil)
    }

    @Test func seedingGoals() {
        var t = TorrentSnapshot(id: "a")
        t.isSeeding = true
        t.totalWanted = 1_000
        t.allTimeDownload = 1_000
        t.allTimeUpload = 1_400
        #expect(!SeedingGoal(ratioPercent: 150).isReached(by: t))
        t.allTimeUpload = 1_500
        #expect(SeedingGoal(ratioPercent: 150).isReached(by: t))
        // Added complete: nothing downloaded, the size counts instead.
        t.allTimeDownload = 0
        t.allTimeUpload = 100
        #expect(!SeedingGoal(ratioPercent: 150).isReached(by: t))
        t.seedingSeconds = 3_600
        #expect(SeedingGoal(ratioPercent: 150, minutes: 60).isReached(by: t))
        #expect(!SeedingGoal().isReached(by: t))
        t.isSeeding = false
        #expect(!SeedingGoal(minutes: 1).isReached(by: t))
    }

    @Test func bandwidthSplit() {
        let shares = [BandwidthAllocator.Share(id: "h", priority: .high, isActive: true),
                      BandwidthAllocator.Share(id: "n", priority: .normal, isActive: true),
                      BandwidthAllocator.Share(id: "l", priority: .low, isActive: true),
                      BandwidthAllocator.Share(id: "idle", priority: .high, isActive: false)]
        let split = BandwidthAllocator.split(limit: 700_000, among: shares)
        #expect(split["h"] == 400_000 && split["n"] == 200_000 && split["l"] == 100_000 && split["idle"] == nil)
        #expect(BandwidthAllocator.split(limit: 0, among: shares).isEmpty)
        #expect(BandwidthAllocator.split(limit: 100_000, among: [.init(id: "a", priority: .normal, isActive: true)]).isEmpty)
    }

    @Test func scheduleSlots() {
        var schedule = Schedule()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-10-26 was a Monday.
        let monday9 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
        let sunday23 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23))!
        schedule[0, 9] = .off
        schedule[6, 23] = .limited
        #expect(schedule.mode(at: monday9, calendar: calendar) == .full)  // disabled
        schedule.isEnabled = true
        #expect(schedule.mode(at: monday9, calendar: calendar) == .off)
        #expect(schedule.mode(at: sunday23, calendar: calendar) == .limited)
        #expect(ScheduleMode.off.next == .full)
    }

    @Test func usageLedger() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 1))!
        var ledger = UsageLedger()
        ledger.record(download: 100, upload: 10, on: day1, calendar: calendar)
        ledger.record(download: 50, upload: 5, on: day3, calendar: calendar)
        ledger.record(download: 50, upload: 0, on: day3, calendar: calendar)
        #expect(ledger.total(.download, days: 3, endingOn: day3, calendar: calendar) == 200)
        #expect(ledger.total(.both, days: 2, endingOn: day3, calendar: calendar) == 105)
        #expect(ledger.series(days: 3, endingOn: day3, calendar: calendar).map(\.usage.download) == [100, 0, 100])
        ledger.prune(keepDays: 1, now: day3, calendar: calendar)
        #expect(ledger.days.keys.sorted() == ["2026-10-03"])
    }

    @Test func searchProviders() {
        let provider = SearchProvider(name: "Example", template: "https://search.example/?q=%s&cat=1")
        #expect(provider.url(for: "big buck bunny & co")?.absoluteString == "https://search.example/?q=big%20buck%20bunny%20%26%20co&cat=1")
        #expect(provider.url(for: "  ") == nil)
        #expect(!SearchProvider(name: "x", template: "https://no-placeholder.example").isValid)
        #expect(!SearchProvider(name: "x", template: "javascript:%s").isValid)
    }

    @Test func libtorrentMapping() {
        var o = NetworkOptions()
        var s = LibtorrentSettingsMapper.named(o)
        #expect(s["out_enc_policy"] == "1" && s["in_enc_policy"] == "1" && s["proxy_type"] == "0" && s["choking_algorithm"] == "2")
        o.encryption = .forced
        o.proxy.kind = .socks5
        o.proxy.host = "proxy.example"
        o.proxy.port = 9050
        o.proxy.useAuthentication = true
        o.proxy.username = "me"
        o.proxyPassword = "secret"
        o.uploadSlots = 0
        o.extraSlotsWhenSlow = false
        s = LibtorrentSettingsMapper.named(o)
        #expect(s["out_enc_policy"] == "0" && s["allowed_enc_level"] == "2")
        #expect(s["proxy_type"] == "3" && s["proxy_hostname"] == "proxy.example" && s["proxy_port"] == "9050")
        #expect(s["proxy_username"] == "me" && s["proxy_password"] == "secret")
        #expect(s["unchoke_slots_limit"] == "-1" && s["choking_algorithm"] == "0")
        o.encryption = .enabled
        o.allowLegacyIncoming = false
        #expect(LibtorrentSettingsMapper.named(o)["in_enc_policy"] == "0")
    }

    @Test func countryDatabase() throws {
        // Two IPv4 ranges and one IPv6 range, built the same way Scripts/ builds the real file.
        var data = Data("FCDB".utf8)
        func be<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        be(UInt16(1)); be(UInt32(3)); be(UInt32(2))
        be(UInt32(0)); data.append(contentsOf: Array("--".utf8))
        be(UInt32(0x0101_0100)); data.append(contentsOf: Array("AU".utf8))       // 1.1.1.0
        be(UInt32(0x0101_0200)); data.append(contentsOf: Array("LK".utf8))       // 1.1.2.0
        be(UInt64(0)); data.append(contentsOf: Array("--".utf8))
        be(UInt64(0x2001_0db8_0000_0000)); data.append(contentsOf: Array("US".utf8))
        let db = try #require(CountryDatabase(data: data))
        #expect(db.country(for: "1.1.1.1") == "AU")
        #expect(db.country(for: "1.1.200.9") == "LK")
        #expect(db.country(for: "0.1.2.3") == nil)
        #expect(db.country(for: "2001:db8::5") == "US")
        #expect(db.country(for: "::ffff:1.1.1.1") == "AU")
        #expect(db.country(for: "not an ip") == nil)
        #expect(CountryDatabase.flag(for: "lk") == "🇱🇰")
        #expect(CountryDatabase(data: Data("nope".utf8)) == nil)
    }
}
