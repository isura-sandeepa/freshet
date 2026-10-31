import Foundation
import FreshetCore
import Observation

/// The RSS downloader: polls feeds, applies filters, adds what matches and remembers
/// what it already took.
@Observable
@MainActor
final class RSSManager {
    struct State: Codable {
        var feeds: [RSSFeed] = []
        var filters: [RSSFilter] = []
        var history = RSSHistory()
        var refreshMinutes = 15
    }

    @ObservationIgnored unowned let model: AppModel
    private(set) var feeds: [RSSFeed] = []
    var filters: [RSSFilter] = [] { didSet { save() } }
    private(set) var history = RSSHistory()
    var refreshMinutes = 15 { didSet { save() } }
    private(set) var items: [UUID: [RSSItem]] = [:]
    private(set) var errors: [UUID: String] = [:]
    private(set) var lastRefresh: [UUID: Date] = [:]
    private(set) var refreshing: Set<UUID> = []

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var loading = true

    init(model: AppModel, simulated: Bool) {
        self.model = model
        url = AppPaths.support.appendingPathComponent(simulated ? "rss-simulated.json" : "rss.json")
        if let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(State.self, from: data) {
            feeds = state.feeds
            filters = state.filters
            history = state.history
            refreshMinutes = state.refreshMinutes
        }
        loading = false
    }

    // MARK: Feeds

    func addFeed(url: String, alias: String, cookies: String) {
        let feed = RSSFeed(url: url.trimmingCharacters(in: .whitespacesAndNewlines), alias: alias, cookies: cookies)
        feeds.append(feed)
        save()
        Task { await refresh(feed) }
    }

    func updateFeed(_ feed: RSSFeed) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[index] = feed
        save()
    }

    func removeFeed(_ id: UUID) {
        feeds.removeAll { $0.id == id }
        items.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        for index in filters.indices where filters[index].feedID == id { filters[index].feedID = nil }
        save()
    }

    func tick(now: Date) {
        let interval = Double(max(5, refreshMinutes)) * 60
        for feed in feeds where feed.isEnabled && !refreshing.contains(feed.id) {
            if let last = lastRefresh[feed.id], now.timeIntervalSince(last) < interval { continue }
            Task { await refresh(feed) }
        }
    }

    func refreshAll() {
        for feed in feeds where feed.isEnabled { Task { await refresh(feed) } }
    }

    func refresh(_ feed: RSSFeed) async {
        guard !refreshing.contains(feed.id), let address = URL(string: feed.url) else {
            if URL(string: feed.url) == nil { errors[feed.id] = "That isn't a valid URL." }
            return
        }
        refreshing.insert(feed.id)
        defer {
            refreshing.remove(feed.id)
            lastRefresh[feed.id] = Date()
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request(address, cookies: feed.cookies))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw EngineError.downloadFailed("The feed answered HTTP \(http.statusCode).")
            }
            guard let parsed = RSSFeedParser.parse(data) else { throw EngineError.downloadFailed("This isn't an RSS or Atom feed.") }
            items[feed.id] = parsed
            errors.removeValue(forKey: feed.id)
            applyFilters(to: feed, items: parsed)
        } catch {
            errors[feed.id] = error.localizedDescription
        }
    }

    // MARK: Filters

    func newFilter() -> RSSFilter {
        let filter = RSSFilter()
        filters.append(filter)
        return filter
    }

    func removeFilter(_ id: UUID) {
        filters.removeAll { $0.id == id }
    }

    /// Items in the current feeds that a filter would take now, for the filter editor.
    func preview(_ filter: RSSFilter) -> [RSSItem] {
        feeds.flatMap { feed in
            (items[feed.id] ?? []).filter { RSSMatcher.matches(filter, item: $0, feed: feed.id, history: history, now: Date()) }
        }
    }

    func matchedFilter(for item: RSSItem) -> String? {
        history.items[item.id].flatMap { entry in entry.filterID.flatMap { id in filters.first { $0.id == id }?.name } ?? "Added by hand" }
    }

    private func applyFilters(to feed: RSSFeed, items: [RSSItem]) {
        // Oldest first, so the smart episode filter keeps the first release of each episode.
        let ordered = items.sorted { ($0.published ?? .distantPast) < ($1.published ?? .distantPast) }
        for item in ordered {
            guard let filter = RSSMatcher.filter(for: item, feed: feed.id, filters: filters, history: history, now: Date()) else { continue }
            history.record(item, filter: filter, at: Date())
            save()
            download(item, from: feed, filter: filter)
        }
    }

    // MARK: Downloading

    /// Adds an item by hand from the feed list.
    func downloadManually(_ item: RSSItem, from feed: RSSFeed) {
        history.record(item, filter: nil, at: Date())
        save()
        download(item, from: feed, filter: nil)
    }

    private func download(_ item: RSSItem, from feed: RSSFeed, filter: RSSFilter?) {
        let folder = filter.map(\.saveFolder).flatMap { $0.isEmpty ? nil : $0 }
        let label = filter.map(\.label).flatMap { $0.isEmpty ? nil : $0 }
        let start: Bool? = filter.map { !$0.addStopped }
        Task {
            let source: AddSource
            if item.link.lowercased().hasPrefix("magnet:") {
                source = .magnet(item.link)
            } else {
                guard let address = URL(string: item.link) else { return }
                do {
                    let (data, response) = try await URLSession.shared.data(for: request(address, cookies: feed.cookies))
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw EngineError.downloadFailed("HTTP \(http.statusCode)")
                    }
                    source = .data(data, suggestedName: address.lastPathComponent)
                } catch {
                    model.log(LogEntry(torrentID: nil, level: .error, message: "RSS: couldn't fetch “\(item.title)”: \(error.localizedDescription)"))
                    return
                }
            }
            if let id = await model.addAutomatically(source, savePath: folder, label: label, start: start) {
                model.log(LogEntry(torrentID: id, level: .info, message: "RSS: added “\(item.title)”\(filter.map { " (filter \($0.name))" } ?? "")"))
            }
        }
    }

    private func request(_ url: URL, cookies: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Freshet/0.1", forHTTPHeaderField: "User-Agent")
        let cookie = cookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.httpShouldHandleCookies = false
        }
        return request
    }

    private func save() {
        guard !loading else { return }
        history.prune(olderThan: Date().addingTimeInterval(-180 * 86_400))
        let state = State(feeds: feeds, filters: filters, history: history, refreshMinutes: refreshMinutes)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {}
    }
}
