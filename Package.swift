// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WakeFox",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WakeFox", targets: ["WakeFox"])
    ],
    targets: [
        .executableTarget(
            name: "WakeFox",
            path: ".",
            exclude: [
                ".git",
                "Tests",
                "README.md",
                "Info.plist",
                ".gitignore"
            ],
            sources: [
                "main.swift",
                "Interface.swift",
                "InterfacePersistence.swift",
                "WakeOnLanSender.swift",
                "ShortcutMapper.swift",
                "InterfaceTableViewController.swift",
                "SettingsWindow.swift",
                "WakeFoxApp.swift"
            ]
        ),
        .testTarget(
            name: "WakeFoxTests",
            dependencies: ["WakeFox"],
            path: "Tests/WakeFoxTests"
        )
    ]
)
