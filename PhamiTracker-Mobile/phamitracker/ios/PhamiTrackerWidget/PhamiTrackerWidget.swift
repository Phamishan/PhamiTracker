import AppIntents
import Charts
import SwiftUI
import WidgetKit

// Widgets: "RP Today", "Rank Goal", "Climb" (chart) and "Map Rotation", each on the home screen
// and the lock screen.
//
// The app writes the worker URL, linked accounts and goals into the App Group (see
// widget_bridge.dart / AppDelegate.swift). Each timeline refresh fetches fresh numbers straight
// from the worker, which polls the game APIs every minute, so the widgets stay current even
// when the app hasn't been opened all day.

let appGroup = "group.phamishan.phamitracker"

// MARK: - Palette (matches lib/theme/app_theme.dart)

private let background = Color(hex: 0x15151E)
private let gain = Color(hex: 0x6CCF9C)
private let loss = Color(hex: 0xEE7C88)
private let orange = Color(hex: 0xF08C45)
private let purple = Color(hex: 0x8B78F2)
private let dim = Color.white.opacity(0.6)

private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }
private func deltaColor(_ n: Int) -> Color { n > 0 ? gain : n < 0 ? loss : dim }

/// Dark card with a soft tint of the game's colour in the corner.
private func cardBackground(_ accent: Color) -> some View {
  ZStack {
    background
    LinearGradient(colors: [accent.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .center)
  }
}

// MARK: - Configuration

enum TrackedGame: String, AppEnum {
  case apex, valorant

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Game"
  static var caseDisplayRepresentations: [TrackedGame: DisplayRepresentation] = [
    .apex: "Apex Legends",
    .valorant: "VALORANT",
  ]

  var title: String { self == .apex ? "APEX" : "VALORANT" }
  var unit: String { self == .apex ? "RP" : "RR" }
  var symbol: String { self == .apex ? "flame.fill" : "triangle.fill" }
  var accent: Color { self == .apex ? orange : purple }
  var gradient: [Color] {
    self == .apex ? [Color(hex: 0xF5A35C), Color(hex: 0xD9772F)] : [Color(hex: 0x9E8CFF), Color(hex: 0x6B55D9)]
  }
}

struct GameIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Game"
  static var description = IntentDescription("Choose which game this widget tracks.")

  @Parameter(title: "Game", default: .apex)
  var game: TrackedGame

  init() {}
  init(game: TrackedGame) { self.game = game }
}

enum RotationMode: String, AppEnum {
  case ranked, battleRoyale

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mode"
  static var caseDisplayRepresentations: [RotationMode: DisplayRepresentation] = [
    .ranked: "Ranked",
    .battleRoyale: "Battle Royale",
  ]

  var title: String { self == .ranked ? "RANKED" : "PUBS" }
}

struct RotationIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Map Rotation"
  static var description = IntentDescription("Choose which Apex playlist to show.")

  @Parameter(title: "Mode", default: .ranked)
  var mode: RotationMode

  init() {}
  init(mode: RotationMode) { self.mode = mode }
}

// MARK: - Data

struct SharedConfig: Decodable {
  let apiUrl: String
  let appKey: String
  let games: [String: GameConfig]
}

struct GameConfig: Decodable {
  let playerId: String
  let name: String
  let goal: Goal?
  let snapshot: Snapshot?
}

struct Goal: Codable {
  let label: String
  let targetScore: Int
  let startScore: Int

  func progress(_ score: Int) -> Double {
    if score >= targetScore { return 1 }
    let span = Double(targetScore - startScore)
    guard span > 0 else { return 0 }
    return min(1, max(0, Double(score - startScore) / span))
  }
}

/// Same shape as the worker's /v1/players/:id/widget response.
struct Snapshot: Codable {
  struct Rank: Codable { let name: String?; let rr: Int? }
  struct Today: Codable { let delta: Int; let matches: Int; let wins: Int; let losses: Int }
  struct Status: Codable { let online: Bool?; let inGame: Bool? }
  struct Day: Codable { let day: String; let score: Int?; let delta: Int }
  struct Match: Codable {
    let ts: Double
    let delta: Int
    let kind: String?
    let map: String?
    let legend: String?
    let agent: String?
  }

  let score: Int?
  let rankLabel: String?
  let rank: Rank?
  let today: Today?
  let status: Status?
  let polledAt: Double?
  var history: [Day]? = nil
  var matches: [Match]? = nil

  var polledDate: Date? { polledAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

  /// A cached snapshot from yesterday shouldn't claim yesterday's points as today's.
  var todayIfCurrent: Today {
    guard let today, let polled = polledDate, Calendar.current.isDateInToday(polled) else {
      return Today(delta: 0, matches: 0, wins: 0, losses: 0)
    }
    return today
  }

  var isLive: Bool { status?.inGame == true || status?.online == true }

  /// Scores to chart, oldest first.
  var chartPoints: [ChartPoint] {
    (history ?? []).enumerated().compactMap { i, day in day.score.map { ChartPoint(index: i, score: $0) } }
  }
}

struct ChartPoint: Identifiable {
  let index: Int
  let score: Int
  var id: Int { index }
}

struct TrackerEntry: TimelineEntry {
  enum State { case ready, notLinked }

  let date: Date
  let game: TrackedGame
  let state: State
  let name: String
  let snapshot: Snapshot?
  let goal: Goal?

  static func preview(_ game: TrackedGame) -> TrackerEntry {
    let base = game == .apex ? 10_400 : 1_380
    let steps = [0, 60, 25, 140, 120, 230, 345]
    let now = Date.now.timeIntervalSince1970 * 1000
    return TrackerEntry(
      date: .now,
      game: game,
      state: .ready,
      name: game == .apex ? "Phami" : "Phami#EUW",
      snapshot: Snapshot(
        score: base + steps.last!,
        rankLabel: game == .apex ? "Platinum I" : "Diamond 1",
        rank: .init(name: game == .apex ? "Platinum" : "Diamond 1", rr: 42),
        today: .init(delta: 115, matches: 3, wins: 2, losses: 1),
        status: .init(online: true, inGame: false),
        polledAt: now,
        history: steps.enumerated().map { Snapshot.Day(day: "d\($0.offset)", score: base + $0.element, delta: 0) },
        matches: [
          Snapshot.Match(ts: now - 600_000, delta: 141, kind: "match", map: "Olympus", legend: "Wraith", agent: nil),
          Snapshot.Match(ts: now - 3_000_000, delta: -26, kind: "match", map: "Olympus", legend: "Wraith", agent: nil),
          Snapshot.Match(ts: now - 5_400_000, delta: 0, kind: "match", map: "Storm Point", legend: "Bangalore", agent: nil),
        ]
      ),
      goal: Goal(label: game == .apex ? "Diamond IV" : "Ascendant 1", targetScore: game == .apex ? 11_400 : 1_800, startScore: base)
    )
  }
}

enum TrackerStore {
  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  static func config() -> SharedConfig? {
    guard let json = defaults?.string(forKey: "config"), let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SharedConfig.self, from: data)
  }

  static func cached<T: Decodable>(_ key: String) -> T? {
    guard let data = defaults?.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  static func cache<T: Encodable>(_ value: T, key: String) {
    if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: key) }
  }

  static func get<T: Decodable>(_ path: String, config: SharedConfig) async -> T? {
    guard let url = URL(string: config.apiUrl + path) else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue(config.appKey, forHTTPHeaderField: "x-app-key")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  static func load(_ game: TrackedGame) async -> TrackerEntry {
    guard let config = config(), let account = config.games[game.rawValue] else {
      return TrackerEntry(date: .now, game: game, state: .notLinked, name: "", snapshot: nil, goal: nil)
    }
    let key = "snapshot.\(game.rawValue)"
    var snapshot: Snapshot? = cached(key) ?? account.snapshot
    let offset = TimeZone.current.secondsFromGMT() / 60
    if let fresh: Snapshot = await get("/v1/players/\(account.playerId)/widget?tzOffset=\(offset)", config: config) {
      snapshot = fresh
      cache(fresh, key: key)
    }
    return TrackerEntry(date: .now, game: game, state: .ready, name: account.name, snapshot: snapshot, goal: account.goal)
  }
}

struct Provider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> TrackerEntry { .preview(.apex) }

  func snapshot(for configuration: GameIntent, in context: Context) async -> TrackerEntry {
    if context.isPreview { return .preview(configuration.game) }
    return await TrackerStore.load(configuration.game)
  }

  func timeline(for configuration: GameIntent, in context: Context) async -> Timeline<TrackerEntry> {
    let entry = await TrackerStore.load(configuration.game)
    // Refresh sooner mid-session. iOS rations widget refreshes, so this is a request, not a promise.
    let minutes = entry.snapshot?.isLive == true ? 10 : 20
    let next = Calendar.current.date(byAdding: .minute, value: minutes, to: .now)!
    return Timeline(entries: [entry], policy: .after(next))
  }
}

// MARK: Map rotation data

/// Same shape as the worker's /v1/apex/maps response.
struct MapRotation: Codable {
  struct Slot: Codable {
    let map: String?
    let start: Double?
    let end: Double?

    var startDate: Date? { start.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var endDate: Date? { end.map { Date(timeIntervalSince1970: $0 / 1000) } }
  }
  struct Pair: Codable { let current: Slot?; let next: Slot? }

  let battleRoyale: Pair?
  let ranked: Pair?

  func pair(_ mode: RotationMode) -> Pair? { mode == .ranked ? ranked : battleRoyale }
}

struct RotationEntry: TimelineEntry {
  let date: Date
  let mode: RotationMode
  let current: String?
  let next: String?
  let start: Date?
  let end: Date?

  static func preview(_ mode: RotationMode) -> RotationEntry {
    RotationEntry(
      date: .now,
      mode: mode,
      current: mode == .ranked ? "E-District" : "Olympus",
      next: mode == .ranked ? "Broken Moon" : "Storm Point",
      start: .now.addingTimeInterval(-3600),
      end: .now.addingTimeInterval(mode == .ranked ? 5 * 3600 : 1800)
    )
  }
}

struct RotationProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> RotationEntry { .preview(.ranked) }

  func snapshot(for configuration: RotationIntent, in context: Context) async -> RotationEntry {
    if context.isPreview { return .preview(configuration.mode) }
    return entry(configuration.mode, await load())
  }

  func timeline(for configuration: RotationIntent, in context: Context) async -> Timeline<RotationEntry> {
    let maps = await load()
    let entry = entry(configuration.mode, maps)
    // Swap to the next map right when the rotation ends; otherwise check back every half hour.
    var entries = [entry]
    if let end = entry.end, end > .now, let next = entry.next {
      entries.append(RotationEntry(date: end, mode: entry.mode, current: next, next: nil, start: end, end: nil))
    }
    let refresh = min(entry.end ?? .distantFuture, .now.addingTimeInterval(30 * 60))
    return Timeline(entries: entries, policy: .after(max(refresh, .now.addingTimeInterval(60))))
  }

  private func load() async -> MapRotation? {
    let cached: MapRotation? = TrackerStore.cached("maps")
    guard let config = TrackerStore.config() else { return cached }
    if let fresh: MapRotation = await TrackerStore.get("/v1/apex/maps", config: config) {
      TrackerStore.cache(fresh, key: "maps")
      return fresh
    }
    return cached
  }

  private func entry(_ mode: RotationMode, _ maps: MapRotation?) -> RotationEntry {
    let pair = maps?.pair(mode)
    return RotationEntry(
      date: .now,
      mode: mode,
      current: pair?.current?.map,
      next: pair?.next?.map,
      start: pair?.current?.startDate,
      end: pair?.current?.endDate
    )
  }
}

// MARK: - Widgets

struct RPTodayWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "RPToday", intent: GameIntent.self, provider: Provider()) { entry in
      RPTodayView(entry: entry)
    }
    .configurationDisplayName("RP Today")
    .description("Rank points won or lost today.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

struct RankGoalWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "RankGoal", intent: GameIntent.self, provider: Provider()) { entry in
      RankGoalView(entry: entry)
    }
    .configurationDisplayName("Rank Goal")
    .description("Your progress towards the rank you're grinding for.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

struct ClimbWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Climb", intent: GameIntent.self, provider: Provider()) { entry in
      ClimbView(entry: entry)
    }
    .configurationDisplayName("Climb")
    .description("Your rank points over the last 7 days.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
  }
}

struct MapRotationWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "MapRotation", intent: RotationIntent.self, provider: RotationProvider()) { entry in
      MapRotationView(entry: entry)
    }
    .configurationDisplayName("Map Rotation")
    .description("The current Apex map and when it changes.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

@main
struct PhamiTrackerWidgets: WidgetBundle {
  var body: some Widget {
    RPTodayWidget()
    RankGoalWidget()
    ClimbWidget()
    MapRotationWidget()
  }
}

// MARK: - Shared views

struct GameHeader: View {
  let entry: TrackerEntry

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: entry.game.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(entry.game.accent)
      Text(entry.game.title).font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(dim)
      Spacer(minLength: 0)
      if entry.snapshot?.isLive == true {
        Circle().fill(gain).frame(width: 6, height: 6)
      }
    }
  }
}

struct NotLinkedView: View {
  let game: TrackedGame

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: game.symbol).font(.title2.weight(.bold)).foregroundStyle(game.accent)
      Spacer(minLength: 0)
      Text("Link \(game == .apex ? "Apex" : "VALORANT")").font(.headline.weight(.heavy))
      Text("Open PhamiTracker to start tracking.").font(.caption2).foregroundStyle(dim)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

// MARK: - RP Today

struct RPTodayView: View {
  @Environment(\.widgetFamily) var family
  let entry: TrackerEntry

  var today: Snapshot.Today { entry.snapshot?.todayIfCurrent ?? .init(delta: 0, matches: 0, wins: 0, losses: 0) }

  var body: some View {
    content.containerBackground(for: .widget) { cardBackground(entry.game.accent) }
  }

  @ViewBuilder var content: some View {
    switch family {
    case .accessoryInline:
      Label("\(signed(today.delta)) \(entry.game.unit) today", systemImage: entry.game.symbol)
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: -2) {
          Text(signed(today.delta)).font(.system(size: 17, weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
          Text(entry.game.unit).font(.system(size: 9, weight: .heavy))
        }
      }
      .widgetAccentable()
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Label(entry.game.title, systemImage: entry.game.symbol).font(.caption2.weight(.heavy))
        Text("\(signed(today.delta)) \(entry.game.unit)").font(.title3.weight(.bold)).widgetAccentable()
        Text("\(today.matches) games · \(today.wins)W \(today.losses)L").font(.caption2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    default:
      if entry.state == .notLinked {
        NotLinkedView(game: entry.game)
      } else if family == .systemMedium {
        HStack(spacing: 16) {
          todayBlock
          Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
          rankBlock
        }
        .foregroundStyle(.white)
      } else {
        todayBlock.foregroundStyle(.white)
      }
    }
  }

  var todayBlock: some View {
    VStack(alignment: .leading, spacing: 2) {
      GameHeader(entry: entry)
      Spacer(minLength: 0)
      Text(signed(today.delta))
        .font(.system(size: 40, weight: .bold, design: .rounded))
        .foregroundStyle(deltaColor(today.delta))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .contentTransition(.numericText())
      Text("\(entry.game.unit) today").font(.system(size: 13, weight: .semibold)).foregroundStyle(dim)
      Spacer(minLength: 0)
      Text("\(today.matches) games · \(today.wins)W \(today.losses)L")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(dim)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  var rankBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).foregroundStyle(dim)
      Spacer(minLength: 0)
      Text(entry.snapshot?.rankLabel ?? "—")
        .font(.system(size: 20, weight: .bold))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
      if let score = entry.snapshot?.score {
        Text(entry.game == .apex ? "\(score.formatted()) RP" : "\(entry.snapshot?.rank?.rr ?? 0) RR")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(entry.game.accent)
      }
      Spacer(minLength: 0)
      if let polled = entry.snapshot?.polledDate {
        Text("Updated \(polled, style: .relative) ago").font(.system(size: 10, weight: .medium)).foregroundStyle(dim)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Rank Goal

struct GoalRing: View {
  let progress: Double
  let colors: [Color]
  var lineWidth: CGFloat = 10

  var body: some View {
    ZStack {
      Circle().stroke(.white.opacity(0.08), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: max(0.001, progress))
        .stroke(
          AngularGradient(colors: colors + [colors[0]], center: .center),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
    }
  }
}

struct RankGoalView: View {
  @Environment(\.widgetFamily) var family
  let entry: TrackerEntry

  var score: Int { entry.snapshot?.score ?? 0 }
  var progress: Double { entry.goal?.progress(score) ?? 0 }
  var remaining: Int { max(0, (entry.goal?.targetScore ?? 0) - score) }
  var ringColors: [Color] { [orange, purple] }

  var body: some View {
    content.containerBackground(for: .widget) { cardBackground(entry.game.accent) }
  }

  @ViewBuilder var content: some View {
    switch family {
    case .accessoryInline:
      Label(entry.goal.map { "\(Int(progress * 100))% to \($0.label)" } ?? "No rank goal", systemImage: "flag.fill")
    case .accessoryCircular:
      Gauge(value: progress) {
        Image(systemName: entry.game.symbol)
      } currentValueLabel: {
        Text("\(Int(progress * 100))")
      }
      .gaugeStyle(.accessoryCircularCapacity)
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.goal.map { "→ \($0.label)" } ?? "No goal set").font(.caption.weight(.heavy))
        ProgressView(value: progress).widgetAccentable()
        Text(entry.goal == nil ? entry.game.title : "\(remaining.formatted()) \(entry.game.unit) to go").font(.caption2)
      }
    default:
      if entry.state == .notLinked {
        NotLinkedView(game: entry.game)
      } else if entry.goal == nil {
        VStack(alignment: .leading, spacing: 6) {
          GameHeader(entry: entry)
          Spacer(minLength: 0)
          Image(systemName: "flag.checkered").font(.title.weight(.semibold)).foregroundStyle(purple)
          Text("Set a rank goal in the app").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      } else if family == .systemMedium {
        HStack(spacing: 18) {
          ring.frame(width: 112, height: 112)
          details
        }
        .foregroundStyle(.white)
      } else {
        VStack(spacing: 8) {
          GameHeader(entry: entry)
          ring.frame(width: 92, height: 92)
          Text("\(remaining.formatted()) \(entry.game.unit) to go")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(dim)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
      }
    }
  }

  var ring: some View {
    ZStack {
      GoalRing(progress: progress, colors: ringColors, lineWidth: family == .systemMedium ? 11 : 9)
      VStack(spacing: 0) {
        Text("\(Int(progress * 100))%").font(.system(size: family == .systemMedium ? 24 : 20, weight: .bold, design: .rounded))
        Text(entry.goal?.label ?? "").font(.system(size: 9, weight: .heavy)).foregroundStyle(purple).lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      .padding(.horizontal, 12)
    }
  }

  var details: some View {
    VStack(alignment: .leading, spacing: 4) {
      GameHeader(entry: entry)
      Spacer(minLength: 0)
      Text(entry.snapshot?.rankLabel ?? "—").font(.system(size: 13, weight: .semibold)).foregroundStyle(dim)
      Text("→ \(entry.goal?.label ?? "")").font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
      Text(remaining == 0 ? "Goal reached! 🎉" : "\(remaining.formatted()) \(entry.game.unit) to go")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(entry.game.accent)
      Spacer(minLength: 0)
      let today = entry.snapshot?.todayIfCurrent.delta ?? 0
      Text("\(signed(today)) \(entry.game.unit) today")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(deltaColor(today))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Climb (chart)

struct ClimbChart: View {
  let entry: TrackerEntry
  var showGoal = true
  var lineWidth: CGFloat = 2.5

  var body: some View {
    let points = entry.snapshot?.chartPoints ?? []
    let scores = points.map(\.score)
    let goal = entry.goal?.targetScore
    // Only draw the goal line when it's close enough not to flatten the chart.
    let lo = scores.min() ?? 0
    let hi = scores.max() ?? 0
    let span = max(hi - lo, 50)
    let goalVisible = showGoal && goal.map { $0 <= hi + span / 2 } == true
    let top = goalVisible ? max(hi, goal!) : hi
    let pad = max((top - lo) / 8, 10)

    Chart {
      ForEach(points) { point in
        AreaMark(x: .value("Day", point.index), yStart: .value("Base", lo - pad), yEnd: .value("Score", point.score))
          .interpolationMethod(.monotone)
          .foregroundStyle(
            LinearGradient(colors: [entry.game.accent.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
          )
        LineMark(x: .value("Day", point.index), y: .value("Score", point.score))
          .interpolationMethod(.monotone)
          .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .foregroundStyle(LinearGradient(colors: [orange, purple], startPoint: .leading, endPoint: .trailing))
      }
      if let last = points.last {
        PointMark(x: .value("Day", last.index), y: .value("Score", last.score))
          .symbolSize(lineWidth * 14)
          .foregroundStyle(.white)
      }
      if goalVisible, let goal {
        RuleMark(y: .value("Goal", goal))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          .foregroundStyle(purple.opacity(0.8))
      }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: (lo - pad)...(top + pad))
    .chartLegend(.hidden)
  }
}

struct ClimbView: View {
  @Environment(\.widgetFamily) var family
  let entry: TrackerEntry

  var weekDelta: Int {
    let scores = entry.snapshot?.chartPoints.map(\.score) ?? []
    guard let first = scores.first, let last = scores.last else { return 0 }
    return last - first
  }

  var body: some View {
    content.containerBackground(for: .widget) { cardBackground(entry.game.accent) }
  }

  @ViewBuilder var content: some View {
    if family == .accessoryRectangular {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Image(systemName: entry.game.symbol)
          Text("\(signed(weekDelta)) \(entry.game.unit)").font(.caption.weight(.heavy))
          Spacer(minLength: 0)
          Text("7d").font(.caption2)
        }
        ClimbChart(entry: entry, showGoal: false, lineWidth: 2).widgetAccentable()
      }
    } else if entry.state == .notLinked {
      NotLinkedView(game: entry.game)
    } else if (entry.snapshot?.chartPoints.count ?? 0) < 2 {
      VStack(alignment: .leading) {
        GameHeader(entry: entry)
        Spacer()
        Text("Your climb shows up here after a few games.").font(.caption.weight(.semibold)).foregroundStyle(dim)
      }
      .foregroundStyle(.white)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        GameHeader(entry: entry)
        HStack(alignment: .firstTextBaseline) {
          Text(entry.snapshot?.rankLabel ?? "—")
            .font(.system(size: family == .systemSmall ? 15 : 18, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
          Spacer(minLength: 4)
          Text("\(signed(weekDelta)) \(family == .systemSmall ? "" : entry.game.unit + " · 7d")")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(deltaColor(weekDelta))
        }
        ClimbChart(entry: entry, showGoal: family != .systemSmall)
        if family == .systemLarge { recentMatches }
      }
      .foregroundStyle(.white)
    }
  }

  var recentMatches: some View {
    VStack(spacing: 6) {
      ForEach(Array((entry.snapshot?.matches ?? []).prefix(4).enumerated()), id: \.offset) { _, match in
        let title = [match.legend ?? match.agent, match.map].compactMap { $0 }.joined(separator: " · ")
        HStack {
          Text(title.isEmpty ? "Ranked match" : title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
          Spacer()
          Text(Date(timeIntervalSince1970: match.ts / 1000), style: .time)
            .font(.system(size: 11))
            .foregroundStyle(dim)
          Text("\(signed(match.delta))")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(deltaColor(match.delta))
            .frame(width: 44, alignment: .trailing)
        }
      }
    }
    .padding(.top, 4)
  }
}

// MARK: - Map Rotation

struct MapRotationView: View {
  @Environment(\.widgetFamily) var family
  let entry: RotationEntry

  var body: some View {
    content.containerBackground(for: .widget) { cardBackground(entry.mode == .ranked ? orange : purple) }
  }

  var accent: Color { entry.mode == .ranked ? orange : purple }

  @ViewBuilder var countdown: some View {
    if let end = entry.end, end > entry.date {
      Text(end, style: .timer).monospacedDigit()
    } else {
      Text("—")
    }
  }

  @ViewBuilder var content: some View {
    switch family {
    case .accessoryInline:
      if let end = entry.end {
        Label("\(entry.current ?? "—") · \(Text(end, style: .relative))", systemImage: "map.fill")
      } else {
        Label(entry.current ?? "Map rotation", systemImage: "map.fill")
      }
    case .accessoryCircular:
      if let start = entry.start, let end = entry.end, end > start {
        ProgressView(timerInterval: start...end, countsDown: true) {
          Image(systemName: "map.fill")
        } currentValueLabel: {
          Text(String((entry.current ?? "?").prefix(3)).uppercased())
            .font(.system(size: 12, weight: .heavy))
        }
        .progressViewStyle(.circular)
        .widgetAccentable()
      } else {
        ZStack {
          AccessoryWidgetBackground()
          Text(String((entry.current ?? "?").prefix(3)).uppercased()).font(.system(size: 14, weight: .heavy))
        }
      }
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Label(entry.mode.title, systemImage: "map.fill").font(.caption2.weight(.heavy))
        Text(entry.current ?? "—").font(.headline.weight(.bold)).lineLimit(1).widgetAccentable()
        HStack(spacing: 4) {
          countdown
          if let next = entry.next { Text("→ \(next)").lineLimit(1) }
        }
        .font(.caption2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    default:
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Image(systemName: "map.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(accent)
          Text("APEX · \(entry.mode.title)").font(.system(size: 11, weight: .heavy)).tracking(1).foregroundStyle(dim)
        }
        Spacer(minLength: 0)
        Text(entry.current ?? "—")
          .font(.system(size: family == .systemSmall ? 22 : 26, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        countdown
          .font(.system(size: family == .systemSmall ? 20 : 22, weight: .semibold, design: .rounded))
          .foregroundStyle(accent)
        Spacer(minLength: 0)
        if let next = entry.next {
          Text("Next: \(next)").font(.system(size: 12, weight: .semibold)).foregroundStyle(dim).lineLimit(1)
        }
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

#Preview(as: .systemMedium) {
  ClimbWidget()
} timeline: {
  TrackerEntry.preview(.apex)
  TrackerEntry.preview(.valorant)
}

#Preview(as: .accessoryRectangular) {
  MapRotationWidget()
} timeline: {
  RotationEntry.preview(.ranked)
}
