import AppKit
import SwiftUI

let mainWindowID = "main"

extension Notification.Name {
    static let freshetOpenMainWindow = Notification.Name("FreshetOpenMainWindow")
}

@main
struct FreshetMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Freshet", id: mainWindowID) {
            MainView()
                .environment(appDelegate.model)
                .frame(minWidth: 940, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_200, height: 780)
        .commands { FreshetCommands(model: appDelegate.model) }

        // Every window shares the main window's chrome: no title bar, the sidebar or page
        // running up under the window buttons.
        Window("RSS Downloader", id: "rss") {
            RSSWindow()
                .environment(appDelegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_000, height: 640)

        Window("New Torrent", id: "create") {
            CreateTorrentView()
                .environment(appDelegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 620, height: 760)

        Window("Freshet Help", id: "help") {
            HelpView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 880, height: 620)

        // A window rather than the Settings scene, so it can have the same sidebar and chrome
        // as the others; Freshet › Settings… (⌘,) opens it.
        Window("Settings", id: settingsWindowID) {
            PreferencesView()
                .environment(appDelegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 660)
        .defaultPosition(.center)

        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel

    override init() {
        model = AppModel(simulate: CommandLine.arguments.contains("--simulate"))
        super.init()
        AppFont.register()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched with `swift run` there is no app bundle; make it a regular app anyway.
        if Bundle.main.bundleIdentifier == nil {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        model.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.handleOpen(urls)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let model = self.model
        menu.addItem(ClosureMenuItem("Resume All") { model.resumeAll() })
        menu.addItem(ClosureMenuItem("Pause All") { model.pauseAll() })
        menu.addItem(.separator())
        menu.addItem(SpeedPresets.menu(title: "Download Limit", current: model.settings.downloadLimitKBps) {
            model.setGlobalLimits(downloadKBps: $0)
        })
        menu.addItem(SpeedPresets.menu(title: "Upload Limit", current: model.settings.uploadLimitKBps) {
            model.setGlobalLimits(uploadKBps: $0)
        })
        return menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // keep transferring from the menu bar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .freshetOpenMainWindow, object: nil) }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.isShuttingDown { return .terminateLater }
        Task { @MainActor in
            await model.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
