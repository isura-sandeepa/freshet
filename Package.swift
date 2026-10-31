// swift-tools-version: 5.10
import Foundation
import PackageDescription

// libtorrent 2.0.15 is vendored in Vendor/libtorrent (BSD licence, see VENDORED.md) and built
// here as a static library. Only two things come from outside the repo: Boost's headers
// (header-only use) and OpenSSL, both from Homebrew. Point FRESHET_BOOST_INCLUDE or
// FRESHET_OPENSSL_PREFIX elsewhere if yours live somewhere else.
let environment = ProcessInfo.processInfo.environment

func firstDirectory(containing file: String, in candidates: [String?]) -> String? {
    candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: "\($0)/\(file)") }
}

let boostInclude = firstDirectory(containing: "boost/version.hpp", in: [
    environment["FRESHET_BOOST_INCLUDE"],
    "/opt/homebrew/opt/boost/include",
    "/opt/homebrew/include",
    "/usr/local/opt/boost/include",
    "/usr/local/include",
]) ?? "/opt/homebrew/include"

let opensslPrefix = firstDirectory(containing: "include/openssl/ssl.h", in: [
    environment["FRESHET_OPENSSL_PREFIX"],
    "/opt/homebrew/opt/openssl@3",
    "/usr/local/opt/openssl@3",
]) ?? "/opt/homebrew/opt/openssl@3"

// Link OpenSSL statically when the archives exist, so the app doesn't depend on Homebrew at run time.
let opensslArchives = ["libssl.a", "libcrypto.a"].map { "\(opensslPrefix)/lib/\($0)" }
let opensslLinking: [LinkerSetting] = opensslArchives.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    ? [.unsafeFlags(opensslArchives.flatMap { ["-Xlinker", $0] })]
    : [.unsafeFlags(["-L\(opensslPrefix)/lib"]), .linkedLibrary("ssl"), .linkedLibrary("crypto")]

// Everything that includes libtorrent headers must see the same configuration as the library itself.
let libtorrentConfiguration: [CXXSetting] = [
    "TORRENT_USE_OPENSSL", "TORRENT_USE_LIBCRYPTO", "TORRENT_SSL_PEERS",
    "OPENSSL_NO_SSL2", "OPENSSL_NO_SSL3", "OPENSSL_NO_TLS1", "OPENSSL_NO_TLS1_1", "OPENSSL_NO_DTLS1",
    "BOOST_ASIO_ENABLE_CANCELIO", "BOOST_ASIO_NO_DEPRECATED",
].map { CXXSetting.define($0) } + [
    .define("NDEBUG", .when(configuration: .release)),
    .unsafeFlags(["-isystem", boostInclude, "-isystem", "\(opensslPrefix)/include"]),
]

let package = Package(
    name: "Freshet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Freshet", targets: ["FreshetApp"]),
        .executable(name: "freshet-smoke", targets: ["FreshetSmoke"]),
    ],
    targets: [
        // Vendored libtorrent-rasterbar 2.0.15 (src/, kademlia, ed25519, try_signal), compiled as-is.
        .target(
            name: "libtorrent",
            path: "Vendor/libtorrent",
            exclude: ["COPYING", "LICENSE", "VENDORED.md", "src/ed25519/LICENSE", "deps/try_signal/LICENSE"],
            sources: ["src", "deps/try_signal"],
            publicHeadersPath: "include",
            cxxSettings: libtorrentConfiguration + [
                .headerSearchPath("deps/try_signal"),
                .define("TORRENT_BUILDING_LIBRARY"),
                .define("BOOST_EXCEPTION_DISABLE"),
                .define("BOOST_ASIO_HAS_STD_CHRONO"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .unsafeFlags(["-w"]),  // third-party code: keep the build log about ours
            ],
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("SystemConfiguration"),
            ] + opensslLinking
        ),
        // Thin C API over libtorrent's C++ API. Nothing above this target sees C++.
        .target(
            name: "LTShim",
            dependencies: ["libtorrent"],
            path: "Sources/LTShim",
            cxxSettings: libtorrentConfiguration
        ),
        // Pure Swift: models, the EngineService protocol, formatting, filtering, sorting.
        .target(name: "FreshetCore", path: "Sources/FreshetCore"),
        // Swift actor that drives libtorrent through the shim.
        .target(name: "FreshetEngine", dependencies: ["FreshetCore", "LTShim"], path: "Sources/FreshetEngine"),
        // Deterministic fake engine for UI work and tests (run the app with --simulate).
        .target(name: "FreshetSim", dependencies: ["FreshetCore"], path: "Sources/FreshetSim"),
        .executableTarget(
            name: "FreshetApp",
            dependencies: ["FreshetCore", "FreshetEngine", "FreshetSim"],
            path: "Sources/FreshetApp",
            // DB-IP Lite country data (CC BY 4.0), converted by Scripts/make-country-db.py.
            resources: [.copy("Resources/countries.fcdb"), .copy("Resources/DBIP-LICENSE.txt"),
                        .copy("Resources/THIRD_PARTY_NOTICES.txt")]
        ),
        // Command-line end-to-end check: download, crash, resume.
        .executableTarget(
            name: "FreshetSmoke",
            dependencies: ["FreshetCore", "FreshetEngine"],
            path: "Sources/FreshetSmoke"
        ),
        // Renders the main window and settings panes to PNGs when .devloop/snapshots-on exists.
        .testTarget(
            name: "FreshetAppTests",
            dependencies: ["FreshetApp", "FreshetCore"],
            path: "Tests/FreshetAppTests"
        ),
        .testTarget(
            name: "FreshetCoreTests",
            dependencies: ["FreshetCore", "FreshetSim"],
            path: "Tests/FreshetCoreTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
