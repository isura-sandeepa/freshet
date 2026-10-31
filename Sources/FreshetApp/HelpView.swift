import SwiftUI

/// Freshet Help: short task-based topics, opened from the Help menu.
struct HelpView: View {
    @State private var topic: HelpTopic? = .gettingStarted
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(matches, selection: $topic) { topic in
                Label(topic.title, systemImage: topic.systemImage).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 250)
            .searchable(text: $query, placement: .sidebar, prompt: "Search Help")
        } detail: {
            if let topic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(topic.title).font(.title2.bold())
                        ForEach(topic.sections, id: \.heading) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.heading).font(.headline)
                                Text(section.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
        .frame(minWidth: 700, minHeight: 460)
    }

    private var matches: [HelpTopic] {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return HelpTopic.allCases }
        return HelpTopic.allCases.filter { $0.searchText.contains(words) }
    }
}

struct HelpSection {
    let heading: String
    let body: String
}

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, adding, organizing, speed, scheduler, rss, creating, troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .adding: return "Adding Torrents"
        case .organizing: return "Labels and Queue"
        case .speed: return "Speed Limits"
        case .scheduler: return "Scheduling"
        case .rss: return "RSS Downloader"
        case .creating: return "Creating Torrents"
        case .troubleshooting: return "Connection Problems"
        }
    }

    var systemImage: String {
        switch self {
        case .gettingStarted: return "star"
        case .adding: return "plus.circle"
        case .organizing: return "tag"
        case .speed: return "speedometer"
        case .scheduler: return "calendar"
        case .rss: return "dot.radiowaves.up.forward"
        case .creating: return "doc.badge.plus"
        case .troubleshooting: return "network"
        }
    }

    var searchText: String {
        ([title] + sections.flatMap { [$0.heading, $0.body] }).joined(separator: " ").lowercased()
    }

    var sections: [HelpSection] {
        switch self {
        case .gettingStarted:
            return [
                HelpSection(heading: "Run the Setup Guide",
                            body: "Choose Help > Setup Guide to pick a download folder, tell Freshet your upload speed so browsing stays fast while you share, and check that other computers can connect to yours."),
                HelpSection(heading: "Make Freshet the default app",
                            body: "In Freshet > Settings > General, click Open with Freshet so magnet links in your browser and .torrent files in Finder open here."),
                HelpSection(heading: "Keep transferring in the background",
                            body: "Closing the main window doesn't stop transfers. Freshet stays in the menu bar, where you can see speeds, pause everything or change limits. Choose Open Freshet to bring the window back."),
            ]
        case .adding:
            return [
                HelpSection(heading: "From a file or link",
                            body: "Choose File > Add Torrent (Command-O) for .torrent files, or File > Add from URL or Magnet Link (Command-U) and paste one or more links. You can also drag .torrent files onto the window or the Dock icon."),
                HelpSection(heading: "Choose what to download",
                            body: "When Show options when adding a torrent is on, Freshet asks where to save each torrent and lets you skip files you don't want."),
                HelpSection(heading: "Search the web",
                            body: "Add the search sites you use in Settings > Search, then choose File > Search the Web for Torrents (Option-Command-F) or click the globe in the toolbar. Results open in your browser."),
            ]
        case .organizing:
            return [
                HelpSection(heading: "Labels",
                            body: "Select torrents, Control-click, and choose Label to file them. Labels appear in the sidebar so you can show one group at a time."),
                HelpSection(heading: "The queue",
                            body: "Freshet runs a limited number of torrents at once and queues the rest. Change the numbers in Settings > BitTorrent, and use Torrent > Move Up in Queue (Option-Command-Up Arrow) to change the order. Force Start runs a torrent regardless of the queue."),
            ]
        case .speed:
            return [
                HelpSection(heading: "Global limits",
                            body: "Set download and upload limits in Settings > Bandwidth, or pick a preset from the menu bar menu or the Dock menu. 0 means unlimited."),
                HelpSection(heading: "Per-torrent limits",
                            body: "Select a torrent and choose Torrent > Properties (Command-I) to give it its own limits, or use Bandwidth Allocation to share the global limit unevenly."),
            ]
        case .scheduler:
            return [
                HelpSection(heading: "Weekly schedule",
                            body: "In Settings > Scheduler, pick a mode and click or drag over the hours: Full speed, Limited (uses the limits below the grid), Seeding only, or Turn off. With the grid selected you can use the arrow keys, Space, and 1–4 instead of the pointer."),
                HelpSection(heading: "Transfer cap",
                            body: "In Settings > Transfer Cap, set how much data Freshet may use over a period. When the cap is reached, all transfers stop and a banner explains why until usage falls below the cap."),
            ]
        case .rss:
            return [
                HelpSection(heading: "Feeds",
                            body: "Choose File > RSS Downloader, then click + to add a feed's address. Double-click an item to download it."),
                HelpSection(heading: "Filters",
                            body: "On the Filters tab, add a filter to download new items automatically. * matches any text and | separates alternatives. Turn on the smart episode filter to get each episode only once."),
            ]
        case .creating:
            return [
                HelpSection(heading: "Make a torrent",
                            body: "Choose File > New Torrent (Command-N), add a file or folder, list trackers one per line, and click Create and Save As. Leave Start seeding on to share it right away."),
            ]
        case .troubleshooting:
            return [
                HelpSection(heading: "Peers can't connect to this Mac",
                            body: "If a banner says peers can't connect, open Settings > Connection. Try Random Port, turn on UPnP and NAT-PMP so your router forwards the port, and allow Freshet in System Settings > Network > Firewall."),
                HelpSection(heading: "Downloads are slow",
                            body: "Torrents with few seeds download slowly whatever you do. Check the Peers tab to see who you're connected to, and set an upload limit a little below your line's speed, which keeps downloads fast."),
                HelpSection(heading: "Transfers stopped by themselves",
                            body: "The transfer cap or the scheduler may have stopped them. A banner at the top of the main window says which, with a button to the setting."),
            ]
        }
    }
}
