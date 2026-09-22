// swift-tools-version: 6.1

import PackageDescription

// AzooKeyKanaKanjiConverter is compiled with C++ interoperability when a Zenzai
// trait is enabled, and every module that imports it must enable it as well.
let cxxInterop: [SwiftSetting] = [.interoperabilityMode(.Cxx)]

// libllama and its ggml libraries are built by scripts/build-llama.sh into
// build/lib and installed into a private lib/ directory next to the binaries.
// The converter's module map only links libllama, but ZenzaiCPU also calls
// ggml_backend_dev_by_type() from libggml directly, so link ggml explicitly.
let llamaLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("ggml"),
    .linkedLibrary("ggml-base"),
    .unsafeFlags([
        "-L", Context.packageDirectory + "/build/lib",
        "-Xlinker", "-rpath", "-Xlinker", "$ORIGIN/lib",
    ]),
]

let package = Package(
    name: "ibus-azookey",
    dependencies: [
        // The same revision azooKey-Desktop (b7ec0e4) is built against, so the
        // input logic adapted from it matches the converter API.
        .package(
            url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
            revision: "ad714fea8cb2fe113aea86ba5c42563cdaf77cfb",
            traits: ["ZenzaiCPU"]
        ),
    ],
    targets: [
        .systemLibrary(
            name: "CIBus",
            pkgConfig: "ibus-1.0",
            providers: [.apt(["libibus-1.0-dev"])]
        ),
        // The IBusEngine GObject subclass; forwards everything to Swift.
        .target(
            name: "AzooKeyIBusShim",
            dependencies: ["CIBus"]
        ),
        .executableTarget(
            name: "ibus-engine-azookey",
            dependencies: ["AzooKeyCore", "AzooKeyIBusShim"],
            swiftSettings: cxxInterop,
            linkerSettings: llamaLinkerSettings
        ),
        // Input logic: azooKey-Desktop's state machine (Upstream/) plus the
        // Linux key table, settings and session management. No IBus code.
        .target(
            name: "AzooKeyCore",
            dependencies: [
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
                .product(name: "SwiftUtils", package: "AzooKeyKanaKanjiConverter"),
            ],
            swiftSettings: cxxInterop
        ),
        .executableTarget(
            name: "azookey-cli",
            dependencies: [
                "AzooKeyCore",
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
            ],
            swiftSettings: cxxInterop,
            linkerSettings: llamaLinkerSettings
        ),
        .testTarget(
            name: "AzooKeyCoreTests",
            dependencies: ["AzooKeyCore"],
            swiftSettings: cxxInterop,
            linkerSettings: llamaLinkerSettings
        ),
    ]
)
