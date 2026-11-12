// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ChessPlaybook",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "Shared", targets: ["Shared"]),
    .library(name: "ChessCore", targets: ["ChessCore"]),
    .library(name: "Book", targets: ["Book"]),
    .library(name: "Model", targets: ["Model"]),
    .library(name: "Engine", targets: ["Engine"]),
    .library(name: "Game", targets: ["Game"]),
    .executable(name: "playbook", targets: ["PlaybookCLI"]),
  ],
  targets: [
    .target(name: "Shared"),
    .target(name: "ChessCore", dependencies: ["Shared"]),
    .target(name: "Book", dependencies: ["Shared", "ChessCore"]),
    .target(name: "Model", dependencies: ["Shared", "ChessCore", "Book"]),
    .target(name: "Fathom", exclude: ["tbchess.c", "LICENSE"]),
    // Caissa's search (MIT, see Sources/Caissa/LICENSE), optimized even in Debug: it is unusably slow without.
    .target(
      name: "Caissa", exclude: ["LICENSE", "README.md"],
      cxxSettings: [.headerSearchPath("backend"), .define("CAISSA_DEFAULT_EVALFILE", to: "\"caissa.pnn\""), .define("NDEBUG"), .unsafeFlags(["-O3"])]),
    .target(
      name: "Engine", dependencies: ["ChessCore", "Model", "Fathom", "Caissa"],
      resources: [.copy("Syzygy"), .copy("BookScores.txt"), .copy("CaissaNet")]),
    // The app without its screens: every mode played through code, on Linux too.
    .target(name: "Game", dependencies: ["Shared", "ChessCore", "Book", "Model", "Engine"]),
    .executableTarget(name: "PlaybookCLI", dependencies: ["ChessCore", "Model", "Engine", "Game"]),
    .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"]),
    .testTarget(name: "EngineTests", dependencies: ["ChessCore", "Model", "Engine"]),
    .testTarget(
      name: "SpecTests", dependencies: ["Shared", "ChessCore", "Book", "Model"],
      exclude: ["Golden"]),
    .testTarget(name: "FlowTests", dependencies: ["ChessCore", "Model", "Engine", "Game"]),
  ],
  cxxLanguageStandard: .cxx20
)
