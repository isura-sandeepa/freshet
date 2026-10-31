import Foundation
import Testing
@testable import FreshetCore

struct Phase3Tests {
    @Test func runCommandPlaceholders() {
        var t = TorrentSnapshot(id: "abcdef0123456789abcdef0123456789abcdef01")
        t.name = "Big Buck Bunny's Cut"
        t.savePath = "/Users/me/Downloads"
        t.currentTracker = "udp://t.example:80"
        t.isSeeding = true
        t.libtorrentState = TorrentSnapshot.stateSeeding
        let single = RunCommand.expand("notify %N %F %D %K %S %L %I 100%%", torrent: t, label: "Films", isMultiFile: false, previousState: 6)
        #expect(single == "notify 'Big Buck Bunny'\\''s Cut' '/Users/me/Downloads/Big Buck Bunny'\\''s Cut' '/Users/me/Downloads' 'single' '5' 'Films' 'ABCDEF0123456789ABCDEF0123456789ABCDEF01' 100%")
        let multi = RunCommand.expand("%D|%F|%K|%P|%Z", torrent: t, label: nil, isMultiFile: true, previousState: 6)
        #expect(multi == "'/Users/me/Downloads/Big Buck Bunny'\\''s Cut'|''|'multi'|'6'|%Z")
        t.isPaused = true
        t.isAutoManaged = false
        #expect(RunCommand.stateCode(t) == 11)
        t.isSeeding = false
        #expect(RunCommand.stateCode(t) == 13)
    }

    @Test func parsesRSSAndAtom() throws {
        let rss = """
        <?xml version="1.0"?><rss version="2.0" xmlns:torrent="http://xmlns.ezrss.it/0.1/"><channel><title>x</title>
        <item><title>Show.S02E05.1080p.WEB</title><link>https://site.example/details/1</link>
          <enclosure url="https://site.example/dl/1.torrent" type="application/x-bittorrent" length="1"/>
          <guid>id-1</guid><pubDate>Thu, 29 Oct 2026 10:00:00 +0000</pubDate></item>
        <item><title><![CDATA[Other & Co 2x03 720p]]></title><torrent:magnetURI>magnet:?xt=urn:btih:abc</torrent:magnetURI></item>
        </channel></rss>
        """
        let items = try #require(RSSFeedParser.parse(Data(rss.utf8)))
        #expect(items.count == 2)
        #expect(items[0].link == "https://site.example/dl/1.torrent" && items[0].guid == "id-1" && items[0].published != nil)
        #expect(items[1].title == "Other & Co 2x03 720p" && items[1].link == "magnet:?xt=urn:btih:abc")
        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Linux ISO</title><id>urn:1</id>
        <link rel="enclosure" type="application/x-bittorrent" href="https://a.example/l.torrent"/><updated>2026-10-29T10:00:00Z</updated></entry></feed>
        """
        let entries = try #require(RSSFeedParser.parse(Data(atom.utf8)))
        #expect(entries.first?.link == "https://a.example/l.torrent" && entries.first?.published != nil)
        #expect(RSSFeedParser.parse(Data("not xml".utf8)) == nil)
    }

    @Test func episodesAndQuality() {
        #expect(EpisodeInfo.parse("Show.S02E05.1080p") == EpisodeInfo(season: 2, episode: 5))
        #expect(EpisodeInfo.parse("Show 2x03 720p") == EpisodeInfo(season: 2, episode: 3))
        #expect(EpisodeInfo.parse("News 2026.10.29") == EpisodeInfo(season: 2026, episode: 1029))
        #expect(EpisodeInfo.parse("Ubuntu 26.04") == nil)
        let filter = EpisodeFilter("1x1-10;2x3-;3")!
        #expect(filter.contains(.init(season: 1, episode: 10)) && !filter.contains(.init(season: 1, episode: 11)))
        #expect(filter.contains(.init(season: 2, episode: 40)) && !filter.contains(.init(season: 2, episode: 2)))
        #expect(filter.contains(.init(season: 3, episode: 99)) && !filter.contains(.init(season: 4, episode: 1)))
        #expect(EpisodeFilter("x") == nil)
        #expect(VideoQuality.detect("A.2160p.HDR") == .uhd && VideoQuality.detect("a 1080i") == .hd1080 && VideoQuality.detect("a") == .sd)
    }

    @Test func filtersMatchOncePerEpisode() {
        let feed = UUID()
        var filter = RSSFilter(name: "Show", include: "*show*", exclude: "*x265*", qualities: [.hd1080], smartEpisodeFilter: true)
        var history = RSSHistory()
        let now = Date()
        let a = RSSItem(title: "The.Show.S01E02.1080p.WEB", link: "https://x/1.torrent", guid: "1", published: nil)
        let b = RSSItem(title: "The.Show.S01E02.1080p.HDTV", link: "https://x/2.torrent", guid: "2", published: nil)
        let c = RSSItem(title: "The.Show.S01E03.720p", link: "https://x/3.torrent", guid: "3", published: nil)
        let d = RSSItem(title: "The.Show.S01E04.1080p.x265", link: "https://x/4.torrent", guid: "4", published: nil)
        #expect(RSSMatcher.filter(for: a, feed: feed, filters: [filter], history: history, now: now) == filter)
        history.record(a, filter: filter, at: now)
        #expect(RSSMatcher.filter(for: a, feed: feed, filters: [filter], history: history, now: now) == nil)  // already taken
        #expect(RSSMatcher.filter(for: b, feed: feed, filters: [filter], history: history, now: now) == nil)  // same episode
        #expect(RSSMatcher.filter(for: c, feed: feed, filters: [filter], history: history, now: now) == nil)  // quality
        #expect(RSSMatcher.filter(for: d, feed: feed, filters: [filter], history: history, now: now) == nil)  // excluded
        filter.smartEpisodeFilter = false
        filter.minimumIntervalHours = 24
        #expect(!RSSMatcher.matches(filter, item: b, feed: feed, history: history, now: now.addingTimeInterval(3_600)))
        #expect(RSSMatcher.matches(filter, item: b, feed: feed, history: history, now: now.addingTimeInterval(90_000)))
        filter.feedID = UUID()
        #expect(!RSSMatcher.matches(filter, item: b, feed: feed, history: history, now: now.addingTimeInterval(90_000)))
        #expect(RSSFilter.wildcard("ubuntu|debian", matches: "Debian 13 netinst"))
        #expect(!RSSFilter.wildcard("show?S01", matches: "showS01"))
        #expect(RSSFilter.wildcard("show?S01*", matches: "show.S01E01"))
        #expect(!RSSFilter.wildcard("", matches: "anything"))
    }
}
