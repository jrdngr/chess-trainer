import ChessCore
import Engine
import Foundation
import Game
import Model

/// `playbook`: the app on the command line. Each line of input is one action;
/// after it the game settles and the screen is printed as text.
///
///   swift run playbook [--seed N] [--engine caissa|scripted] [--save DIR] [--book PATH]
///   swift run playbook measure --strategy full|prepOnly|middlegame|endgames --rating N --runs N
///     [--side w|b|either] [--start drill|freeform] [--miss RATE] [--max MOVES] [--seed N] [--out FILE] [--adaptive]
///
/// `--save DIR` keeps the save in DIR across runs; without it every run is a fresh install.

let HELP = """
  Anywhere:  state · help · quit · home · hint (the engine's move here)
  Start:     recommend · choose WHITE E4 D4 (ids, e.g. `choose london caro slav`) · openings · intro
  Home:      select [w|b|either] [drill|freeform] [opening id or moves, "any" for Any Opening]
             play · tree [w|b] · unlock OPENING (id or name) · endgames · middlegame · shop · buy ID · purchase unlock|pawns2000|pawns6000|pawns13000
  Board:     <san> (or move <san> <san>...) · think SECONDS
  Play:      end · continue · takeback · next · undo · done · grow · replay
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
  case "choose":
    // Ids from the list: a White opening, then Black's against 1.e4 and against 1.d4.
    guard rest.count == 3 else { throw HeadlessApp.Failure.notHere("choose WHITE E4 D4, e.g. `choose london caro slav` (`openings` lists the ids)") }
    try await app.chooseOpenings(rest)
  case "openings":
    for opening in OPENING_LIST {
      print("\(opening.id)  \(opening.name)  \(opening.color == .w ? "White" : "Black")  \(opening.roots.map { $0.joined(separator: " ") }.joined(separator: " / "))")
    }
    return true
  case "select": try select(app, rest)
  case "play": await app.openPlay()
  case "tree":
    print(mapText(app.map(rest.first == "b" ? .b : .w)))
    return true
  case "unlock":
    let name = rest.joined(separator: " ")
    let all = (app.map(.w) + app.map(.b)).flatMap(flatten)
    guard let node = all.first(where: { $0.forSale && ($0.family == name || $0.name == name) }) else {
      throw HeadlessApp.Failure.notHere("No opening \"\(name)\" for sale. `tree` lists them")
    }
    try app.buyFamily(node)
  case "grow": await app.growHere()
  case "endgames": try app.openEndgames()
  case "middlegame": try await app.openMiddlegame()
  case "shop": print(app.shopReport())
  case "buy":
    guard let id = rest.first else { throw HeadlessApp.Failure.notHere("Buy what? `shop` lists the items") }
    try app.buy(id)
  case "purchase":
    guard let name = rest.first, let product = CashProduct.allCases.first(where: { $0.rawValue.hasSuffix(".\(name)") }) else {
      throw HeadlessApp.Failure.notHere("purchase unlock|pawns2000|pawns6000|pawns13000")
    }
    app.purchase(product)
  case "home": await app.home()
  case "move": for san in rest { try await app.move(san) }
  case "think": await app.think(rest.first.flatMap(Double.init) ?? 1)
  case "end": await app.endRound()
  case "continue": app.continueToEnd()
  case "takeback": try await app.buyContinue()
  case "next": try await app.next()
  case "undo": await app.undo()
  case "done": await app.doneAdding()
  case "replay":
    app.run?.replayMoves()
    await app.idle()
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

/// `measure`: a bot plays runs and each run's counts go out as one JSON line, to `--out` (appended) or stdout.
@MainActor
func measureMain(_ args: [String]) async {
  var strategy = MeasureStrategy.full, rating = 1200, runs = 20, side = ColorChoice.w, start = RunStart.drill
  var miss = 0.0, maxMoves = 120, seed: UInt32 = 1, out: String?, scripted = false, adaptive = false
  var it = args.makeIterator()
  while let arg = it.next() {
    if arg == "--adaptive" {
      adaptive = true
      continue
    }
    let value = it.next() ?? ""
    switch arg {
    case "--strategy": strategy = MeasureStrategy(rawValue: value) ?? strategy
    case "--rating": rating = Int(value) ?? rating
    case "--runs": runs = Int(value) ?? runs
    case "--side": side = ColorChoice(rawValue: value) ?? side
    case "--start": start = RunStart(rawValue: value) ?? start
    case "--miss": miss = Double(value) ?? miss
    case "--max": maxMoves = Int(value) ?? maxMoves
    case "--seed": seed = UInt32(value) ?? seed
    case "--out": out = value
    case "--engine": scripted = value == "scripted"
    default:
      FileHandle.standardError.write("unknown measure option \(arg)\n".data(using: .utf8)!)
      exit(2)
    }
  }
  let options = MeasureOptions(strategy: strategy, rating: rating, runs: runs, side: side, start: start, missRate: miss, maxMoves: maxMoves, adaptive: adaptive)
  let useScripted = scripted
  let engine: @Sendable () -> ChessEngine = { useScripted ? ScriptedEngine() : makeEngine() }
  let file = out.map { path -> FileHandle in
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    let handle = FileHandle(forWritingAtPath: path)!
    handle.seekToEndOfFile()
    return handle
  }
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  do {
    _ = try await HeadlessApp.run(book: bookURL(Options()), seed: seed, engine: engine) { app in
      try await app.measure(options, seed: seed) { run in
        guard let data = try? encoder.encode(run) else { return }
        if let file { file.write(data + Data([0x0a])) } else { print(String(decoding: data, as: UTF8.self)) }
      }
    }
  } catch {
    FileHandle.standardError.write("! \(error)\n".data(using: .utf8)!)
    exit(1)
  }
}

@MainActor
func main() async {
  if CommandLine.arguments.dropFirst().first == "measure" {
    await measureMain(Array(CommandLine.arguments.dropFirst(2)))
    return
  }
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

/// Every opening on a tree, depth first.
func flatten(_ node: MapNode) -> [MapNode] { [node] + node.children.flatMap(flatten) }

/// A side's tree as indented text: each opening, its form, and what a locked one waits for.
func mapText(_ roots: [MapNode]) -> String {
  var lines: [String] = []
  func visit(_ node: MapNode, _ depth: Int) {
    let pad = String(repeating: "  ", count: depth)
    let state: String
    switch node.state {
    case .owned: state = node.form.map { String(format: "form %.2f", $0) } ?? "no form yet"
    case .next(let runs): state = "NEXT in ~\(max(1, runs)) games"
    case .locked(.inLine): state = "locked"
    case .locked(.games(let games)): state = "locked, game \(games)"
    case .locked(.green(let have, let of)): state = "locked, green \(have)/\(of)"
    case .forSale(let price): state = "for sale, \(price) pawns (unlock \(node.family ?? ""))"
    case .way: state = "openings for sale under it"
    }
    lines.append("\(pad)\(node.move)  \(node.label)  (\(state))")
    for kid in node.children { visit(kid, depth + 1) }
  }
  for root in roots { visit(root, 0) }
  return lines.isEmpty ? "No openings on this side." : lines.joined(separator: "\n")
}
