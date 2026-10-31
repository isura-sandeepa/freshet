import AppKit
import Foundation
import UserNotifications

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Freshet", isDirectory: true)
    }

    static var engineState: URL { support.appendingPathComponent("Engine", isDirectory: true) }

    static func labelsFile(simulated: Bool) -> URL {
        support.appendingPathComponent(simulated ? "labels-simulated.json" : "labels.json")
    }

    static var defaultDownloads: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSString(string: "~/Downloads").expandingTildeInPath
    }

    /// True when running from a proper .app bundle (needed for notifications and URL handling).
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    /// The DB-IP country database: in the app bundle's Resources, or in SwiftPM's resource bundle
    /// next to the executable when running with `swift run`.
    static var countryDatabase: URL? { resource("countries", withExtension: "fcdb") }

    /// The licences of the code and data Freshet includes; opened from Help › Third-Party Notices.
    static var thirdPartyNotices: URL? { resource("THIRD_PARTY_NOTICES", withExtension: "txt") }

    private static func resource(_ name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        let bundle = Bundle(url: executable.appendingPathComponent("Freshet_FreshetApp.bundle"))
        return bundle?.url(forResource: name, withExtension: ext)
    }
}

@MainActor
enum Notifier {
    static func requestAuthorizationIfPossible() {
        guard AppPaths.isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postCompletion(name: String) {
        post(title: "Download complete", body: name)
    }

    static func post(title: String, body: String) {
        guard AppPaths.isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
