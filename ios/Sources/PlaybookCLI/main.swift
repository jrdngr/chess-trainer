import ChessCore
import Engine
import Foundation
import Game
import Model

/// `playbook`: the app on the command line. Each line of input is one action;
/// after it the game settles and the screen is printed as text.
///
///   swift run playbook [--seed N] [--engine caissa|scripted] [--save DIR] [--book PATH]
///
/// `--save DIR` keeps the save in DIR across runs; without it every run is a fresh install.

let HELP = """
  Anywhere:  state · help · quit · home · hint (the engine's move here)
  Start:     intro · recommend · skip [classical|system|solid|aggressive] · end-tutorial
  Home:      select [w|b|either] [drill|freeform] [opening id or moves, "any" for Any Opening]
             play · recs · grow N · endgames · middlegame
  Board:     <san> (or move <san> <san>...) · think SECONDS
  Play:      end · continue · next · undo · done · grow · replay
  Growth:    save · more · play-on · back
  Endgames:  practice · ending ID · resign · next
  """

struct Options {
  var seed: UInt32 = 1
  var engine = "caissa"
  var save: String?
  var book: String?
}

func parseOptions() -> Options {
  var options = Options()
  var args = CommandLine.arguments.dropFirst().makeIterator()
  while let arg = args.next() {
    switch arg {
    case "--seed": options.seed = args.next().flatMap { UInt32($0) } ?? 1
    case "--engine": options.engine = args.next() ?? "caissa"
    case "--save": options.save = args.next()
    case "--book": options.book = args.next()
    case "--help", "-h":
      print("swift run playbook [--seed N] [--engine caissa|scripted] [--save DIR] [--book PATH]\n\n" + HELP)
      exit(0)
    default:
      FileHandle.standardError.write("unknown option \(arg)\n".data(using: .utf8)!)
      exit(2)
    }
  }
  return options
}

/// The book: `--book`, else the checkout's `ios/Resources/book.json`.
func bookURL(_ options: Options) -> URL {
  if let book = options.book { return URL(fileURLWithPath: book) }
  return URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/book.json")
}

@MainActor
func perform(_ app: HeadlessApp, _ words: [String]) async throws -> Bool {
  let command = words[0].lowercased()
  let rest = Array(words.dropFirst())
  switch command {
  case "quit", "exit": return false
  case "help": print(HELP); return true
  case "state", "show": break
  case "intro": app.seeIntro()
  case "recommend": await app.recommendOpenings()
  case "skip": try app.skipTutorial(starter: rest.first)
  case "end-tutorial": app.endTutorial()
  case "select": try select(app, rest)
  case "play": await app.openPlay()
  case "recs": break
  case "grow":
    if let n = rest.first.flatMap(Int.init) {
      let recs = app.recommendations
      guard n >= 1, n <= recs.count else { throw HeadlessApp.Failure.notHere("No recommendation \(n)") }
      try await app.grow(recs[n - 1])
    } else {
      await app.growHere()
    }
  case "endgames": app.openEndgames()
  case "middlegame": await app.openMiddlegame()
  case "home": await app.home()
  case "move": for san in rest { try await app.move(san) }
  case "think": await app.think(rest.first.flatMap(Double.init) ?? 1)
  case "end": await app.endRound()
  case "continue": app.continueToEnd()
  case "next": try await app.next()
  case "undo": await app.undo()
  case "done": await app.doneAdding()
  case "replay":
    app.run?.replayMoves()
    await app.idle()
  case "save": app.saveGrowth()
  case "more": await app.addMore()
  case "play-on": try await app.playOnFromGrowth()
  case "back": app.backToTheLine()
  case "practice": try await app.practice()
  case "ending": try await app.playEnding(rest.first ?? "")
  case "resign": await app.resign()
  case "hint":
    guard let fen = app.fen else { throw HeadlessApp.Failure.notHere("No board") }
    let snap = await app.services.hints.analyse(fen, EngineLimits(depth: 12, movetime: 500, multiPv: 1))
    let best = snap.lines.first?.pv.first.flatMap { applyUci(fen, $0)?.san } ?? "none"
    print("Hint: \(best)")
    return true
  default:
    // A bare move.
    guard words.count == 1, let fen = app.fen, applySan(fen, words[0]) != nil else {
      throw HeadlessApp.Failure.notHere("Unknown command \"\(words[0])\". `help` lists them.")
    }
    try await app.move(words[0])
  }
  print(app.report())
  return true
}

@MainActor
func select(_ app: HeadlessApp, _ words: [String]) throws {
  var side: ColorChoice?
  var start: RunStart?
  var opening: [String] = []
  for word in words {
    if let choice = ColorChoice(rawValue: word.lowercased()) {
      side = choice
    } else if let mode = RunStart(rawValue: word.lowercased()) {
      start = mode
    } else {
      opening.append(word)
    }
  }
  let named = opening.joined(separator: " ")
  try app.select(side: side, start: start, opening: named.isEmpty ? nil : named.lowercased() == "any" ? "" : named)
}

/// Read commands until the input ends or `quit`.
@MainActor
func session(_ app: HeadlessApp) async {
  print(app.report())
  while let line = readLine() {
    let words = line.split(separator: " ").map(String.init)
    guard !words.isEmpty else { continue }
    do {
      if try await !perform(app, words) { break }
    } catch {
      print("! \(error)")
    }
  }
}

@MainActor
func main() async {
  let options = parseOptions()
  let storage: SaveStorage = options.save.map { FileStorage(folder: URL(fileURLWithPath: $0)) } ?? MemoryStorage()
  let scripted = options.engine == "scripted"
  let engine: @Sendable () -> ChessEngine = { scripted ? ScriptedEngine() : makeEngine() }
  do {
    try await HeadlessApp.run(book: bookURL(options), seed: options.seed, storage: storage, engine: engine, session)
  } catch {
    print("! \(error)")
    exit(1)
  }
}

await main()
