// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ChessPlaybook",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "ChessCore", targets: ["ChessCore"]),
    .library(name: "Book", targets: ["Book"]),
    .library(name: "Model", targets: ["Model"]),
    .library(name: "Engine", targets: ["Engine"]),
  ],
  targets: [
    .target(name: "Shared"),
    .target(name: "ChessCore", dependencies: ["Shared"]),
    .target(name: "Book", dependencies: ["Shared", "ChessCore"]),
    .target(name: "Model", dependencies: ["Shared", "ChessCore", "Book"]),
    .target(name: "Engine", dependencies: ["ChessCore", "Model"]),
    .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"]),
    .testTarget(name: "EngineTests", dependencies: ["ChessCore", "Model", "Engine"]),
    .testTarget(name: "SpecTests", dependencies: ["Shared", "ChessCore", "Book", "Model"]),
  ]
)
