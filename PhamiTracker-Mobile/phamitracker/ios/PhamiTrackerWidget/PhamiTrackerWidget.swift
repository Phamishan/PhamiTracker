import AppIntents
import Charts
import SwiftUI
import UIKit
import WidgetKit

// Widgets: "RP Today", "Rank Goal", "Climb" (chart) and "Map Rotation", each on the home screen
// and the lock screen.
//
// The app writes the worker URL, linked accounts and goals into the App Group (see
// widget_bridge.dart / AppDelegate.swift). Each timeline refresh fetches fresh numbers straight
// from the worker, which polls the game APIs every minute, so the widgets stay current even
// when the app hasn't been opened all day.

let appGroup = "group.phamishan.phamitracker"

// MARK: - Style (matches lib/theme/app_theme.dart)

// PhamiJam's family look: warm charcoal, coral accent, PhamiJam gold for goals.
private let cardTop = Color(hex: 0x2A2724)
private let cardBottom = Color(hex: 0x24221F)
private let track = Color(hex: 0x35312C)
private let textDim = Color(hex: 0xCBBFA8)
private let textFaint = Color(hex: 0x8C8273)
private let accent = Color(hex: 0xE0604E)
private let goalColor = Color(hex: 0xDBA43A)
private let goalSoft = Color(hex: 0xE9C77E)
private let gain = Color(hex: 0x5BC98D)
private let loss = Color(hex: 0xEF5B5B)

/// "Today 13:48", "Yesterday 21:02", "Sun 1 Nov".
private func matchDate(_ date: Date) -> String {
  let time = date.formatted(date: .omitted, time: .shortened)
  if Calendar.current.isDateInToday(date) { return "Today \(time)" }
  if Calendar.current.isDateInYesterday(date) { return "Yesterday \(time)" }
  return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}

private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }
private func deltaColor(_ n: Int) -> Color { n > 0 ? gain : n < 0 ? loss : textDim }

/// Space Grotesk (bundled in Fonts/, listed under UIAppFonts) in the three weights the app uses.
private func grotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
  switch weight {
  case .heavy, .black, .bold: return .custom("SpaceGrotesk-Bold", size: size)
  case .medium, .semibold: return .custom("SpaceGrotesk-Medium", size: size)
  default: return .custom("SpaceGrotesk-Regular", size: size)
  }
}

/// Headline numbers and names: `Diamond III`, `+359`.
private func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { grotesk(size, weight).monospacedDigit() }

/// Spaced-out capital label: `TODAY · 6 GAMES`.
private struct MonoLabel: View {
  let text: String
  var color: Color = textDim
  var size: CGFloat = 11

  init(_ text: String, color: Color = textDim, size: CGFloat = 11) {
    self.text = text
    self.color = color
    self.size = size
  }

  var body: some View {
    Text(text.uppercased())
      .font(grotesk(size, .medium))
      .tracking(size * 0.16)
      .foregroundStyle(color)
      .lineLimit(1)
  }
}

private var cardBackground: some View {
  LinearGradient(colors: [cardTop, cardBottom], startPoint: .top, endPoint: .bottom)
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
  /// Bundled logo (Logos/logo-<game>@3x.png, rendered from lib/models/game.dart).
  var logo: UIImage? { UIImage(named: "logo-\(rawValue)") }
  var accent: Color { self == .apex ? Color(hex: 0xE0604E) : Color(hex: 0xFF4655) }
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

/// Range for the Climb widget, picked in Edit Widget (widgets can't load data on a tap).
enum ClimbSpan: String, AppEnum {
  case allTime, threeMonths, month, twoWeeks, week

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Range"
  static var caseDisplayRepresentations: [ClimbSpan: DisplayRepresentation] = [
    .allTime: "All time",
    .threeMonths: "3 months",
    .month: "1 month",
    .twoWeeks: "14 days",
    .week: "7 days",
  ]

  /// Days to ask the worker for; 0 = since the account was linked.
  var days: Int {
    switch self {
    case .allTime: 0
    case .threeMonths: 90
    case .month: 30
    case .twoWeeks: 14
    case .week: 7
    }
  }

  var short: String {
    switch self {
    case .allTime: "All"
    case .threeMonths: "3M"
    case .month: "1M"
    case .twoWeeks: "14D"
    case .week: "7D"
    }
  }

  var title: String {
    switch self {
    case .allTime: "All time"
    case .threeMonths: "3 months"
    case .month: "1 month"
    case .twoWeeks: "14 days"
    case .week: "7 days"
    }
  }
}

struct ClimbIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Climb"
  static var description = IntentDescription("Choose the game and how far back the chart goes.")

  @Parameter(title: "Game", default: .apex)
  var game: TrackedGame

  @Parameter(title: "Range", default: .week)
  var range: ClimbSpan

  init() {}
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
  /// Rank art for the goal (see goalIconUrl in ranks.dart).
  var icon: String? = nil

  func progress(_ score: Int) -> Double {
    if score >= targetScore { return 1 }
    let span = Double(targetScore - startScore)
    guard span > 0 else { return 0 }
    return min(1, max(0, Double(score - startScore) / span))
  }
}

/// Same shape as the worker's /v1/players/:id/widget response.
struct Snapshot: Codable {
  struct Rank: Codable { let name: String?; let rr: Int?; var image: String? = nil }
  struct Today: Codable {
    let delta: Int
    let matches: Int
    let wins: Int
    let losses: Int
    var best: Int? = nil
    var series: [Int]? = nil
  }
  struct Status: Codable { let online: Bool?; let inGame: Bool? }
  /// Apex season + ranked split (scraped from apexseasons.online by the worker).
  struct Season: Codable {
    let season: String?
    let split: Int?
    let splitEnd: Double?

    var splitEndDate: Date? { splitEnd.map { Date(timeIntervalSince1970: $0 / 1000) } }
  }
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
  var season: Season? = nil

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

  /// Average points per day over the charted history.
  var pacePerDay: Int? {
    let scores = chartPoints.map(\.score)
    guard scores.count >= 2, let first = scores.first, let last = scores.last else { return nil }
    return Int((Double(last - first) / Double(scores.count - 1)).rounded())
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
  var rankImage: UIImage? = nil
  var goalImage: UIImage? = nil
  var climbRange: ClimbSpan = .week

  static func preview(_ game: TrackedGame) -> TrackerEntry {
    let base = game == .apex ? 13_100 : 1_380
    let steps = [0, 60, 25, 140, 120, 230, 360]
    let now = Date.now.timeIntervalSince1970 * 1000
    return TrackerEntry(
      date: .now,
      game: game,
      state: .ready,
      name: game == .apex ? "Phami" : "Phami#EUW",
      snapshot: Snapshot(
        score: base + steps.last!,
        rankLabel: game == .apex ? "Diamond III" : "Diamond 1",
        rank: Snapshot.Rank(name: game == .apex ? "Diamond" : "Diamond 1", rr: 42),
        today: Snapshot.Today(delta: 359, matches: 6, wins: 4, losses: 2, best: 196, series: [40, 25, 120, 95, 160, 359]),
        status: Snapshot.Status(online: true, inGame: false),
        polledAt: now,
        history: steps.enumerated().map { Snapshot.Day(day: "d\($0.offset)", score: base + $0.element, delta: 0) },
        matches: [
          Snapshot.Match(ts: now - 600_000, delta: 196, kind: "match", map: "World's Edge", legend: "Wraith", agent: nil),
          Snapshot.Match(ts: now - 3_000_000, delta: -26, kind: "match", map: "World's Edge", legend: "Wraith", agent: nil),
          Snapshot.Match(ts: now - 5_400_000, delta: 65, kind: "match", map: "World's Edge", legend: "Bangalore", agent: nil),
        ]
      ),
      goal: Goal(label: game == .apex ? "Master" : "Ascendant 1", targetScore: game == .apex ? 16_000 : 1_800, startScore: base)
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

  /// Widgets can't load images while rendering, so download, shrink (widgets have a tight
  /// memory budget) and cache them here.
  static func image(_ urlString: String?, maxPixels: CGFloat, opaque: Bool) async -> UIImage? {
    guard let urlString, let url = URL(string: urlString) else { return nil }
    let key = "img.\(urlString)"
    if let data = defaults?.data(forKey: key), let image = UIImage(data: data) { return image }
    guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return nil }

    let scale = min(1, maxPixels / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = opaque
    let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    if let encoded = opaque ? small.jpegData(compressionQuality: 0.8) : small.pngData() {
      defaults?.set(encoded, forKey: key)
    }
    return small
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
    async let rankImage = image(snapshot?.rank?.image, maxPixels: 120, opaque: false)
    async let goalImage = image(account.goal?.icon, maxPixels: 120, opaque: false)
    return TrackerEntry(
      date: .now, game: game, state: .ready, name: account.name, snapshot: snapshot, goal: account.goal,
      rankImage: await rankImage, goalImage: await goalImage)
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

/// The Climb widget: same entry as the others, with the chart swapped for the chosen range.
struct ClimbProvider: AppIntentTimelineProvider {
  struct HistoryResponse: Decodable { let history: [Snapshot.Day] }

  func placeholder(in context: Context) -> TrackerEntry { .preview(.apex) }

  func snapshot(for configuration: ClimbIntent, in context: Context) async -> TrackerEntry {
    if context.isPreview {
      var entry = TrackerEntry.preview(configuration.game)
      entry.climbRange = configuration.range
      return entry
    }
    return await load(configuration)
  }

  func timeline(for configuration: ClimbIntent, in context: Context) async -> Timeline<TrackerEntry> {
    let entry = await load(configuration)
    // Longer ranges barely change between games, so these can refresh less often.
    let minutes = configuration.range == .week ? 20 : 60
    return Timeline(entries: [entry], policy: .after(Calendar.current.date(byAdding: .minute, value: minutes, to: .now)!))
  }

  private func load(_ configuration: ClimbIntent) async -> TrackerEntry {
    var entry = await TrackerStore.load(configuration.game)
    entry.climbRange = configuration.range
    guard configuration.range != .week, let config = TrackerStore.config(),
      let playerId = config.games[configuration.game.rawValue]?.playerId
    else { return entry }

    let key = "climb.\(configuration.game.rawValue).\(configuration.range.rawValue)"
    let offset = TimeZone.current.secondsFromGMT() / 60
    let path = "/v1/players/\(playerId)/history?days=\(configuration.range.days)&tzOffset=\(offset)"
    var history: [Snapshot.Day]? = TrackerStore.cached(key)
    if let fresh: HistoryResponse = await TrackerStore.get(path, config: config) {
      history = fresh.history
      TrackerStore.cache(fresh.history, key: key)
    }
    if let history, var snapshot = entry.snapshot {
      snapshot.history = history
      entry = TrackerEntry(
        date: entry.date, game: entry.game, state: entry.state, name: entry.name, snapshot: snapshot,
        goal: entry.goal, rankImage: entry.rankImage, goalImage: entry.goalImage, climbRange: configuration.range)
    }
    return entry
  }
}

// MARK: Map rotation data

/// Same shape as the worker's /v1/apex/maps response.
struct MapRotation: Codable {
  struct Slot: Codable {
    let map: String?
    var image: String? = nil
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
  var art: UIImage? = nil

  static func preview(_ mode: RotationMode) -> RotationEntry {
    RotationEntry(
      date: .now,
      mode: mode,
      current: mode == .ranked ? "World's Edge" : "Olympus",
      next: mode == .ranked ? "Broken Moon" : "Storm Point",
      start: .now.addingTimeInterval(-3 * 3600),
      end: .now.addingTimeInterval(mode == .ranked ? 19 * 3600 : 1800)
    )
  }
}

struct RotationProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> RotationEntry { .preview(.ranked) }

  func snapshot(for configuration: RotationIntent, in context: Context) async -> RotationEntry {
    if context.isPreview { return .preview(configuration.mode) }
    return await entry(configuration.mode, await load())
  }

  func timeline(for configuration: RotationIntent, in context: Context) async -> Timeline<RotationEntry> {
    let maps = await load()
    let entry = await entry(configuration.mode, maps)
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

  private func entry(_ mode: RotationMode, _ maps: MapRotation?) async -> RotationEntry {
    let pair = maps?.pair(mode)
    return RotationEntry(
      date: .now,
      mode: mode,
      current: pair?.current?.map,
      next: pair?.next?.map,
      start: pair?.current?.startDate,
      end: pair?.current?.endDate,
      art: await TrackerStore.image(pair?.current?.image, maxPixels: 700, opaque: true)
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
    .description("Your current rank and how far you are from your goal.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

struct ClimbWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Climb", intent: ClimbIntent.self, provider: ClimbProvider()) { entry in
      ClimbView(entry: entry)
    }
    .configurationDisplayName("Climb")
    .description("Your rank points over time: all time, 3 months, 1 month, 14 days or 7 days.")
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
    .contentMarginsDisabled()
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

struct NotLinkedView: View {
  let game: TrackedGame

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      GameLogo(game: game, size: 22, color: game.accent)
      Spacer(minLength: 0)
      Text("LINK \(game == .apex ? "APEX" : "VALORANT")").font(display(22))
      Text("Open PhamiTracker to start tracking.").font(grotesk(11)).foregroundStyle(textDim)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

/// The game's logo, tinted.
struct GameLogo: View {
  let game: TrackedGame
  var size: CGFloat = 14
  var color: Color = .white

  var body: some View {
    if let logo = game.logo {
      Image(uiImage: logo).renderingMode(.template).resizable().scaledToFit()
        .frame(width: size, height: size)
        .foregroundStyle(color)
    }
  }
}

/// Rank art if we have it, otherwise a ring with the rank's initial.
struct RankIcon: View {
  let image: UIImage?
  let name: String
  var size: CGFloat = 34

  var body: some View {
    if let image {
      Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
    } else {
      Text(String(name.prefix(1)).uppercased())
        .font(display(size * 0.5))
        .frame(width: size, height: size)
        .overlay(Circle().stroke(textDim, lineWidth: 1.5))
    }
  }
}

struct Sparkline: View {
  let values: [Int]
  var color: Color = accent

  var body: some View {
    let points = values.count == 1 ? [0] + values : values
    Chart {
      ForEach(Array(points.enumerated()), id: \.offset) { i, value in
        AreaMark(x: .value("Game", i), yStart: .value("Base", points.min() ?? 0), yEnd: .value("Net", value))
          .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("Game", i), y: .value("Net", value))
          .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
          .foregroundStyle(color)
      }
      if let last = points.last {
        PointMark(x: .value("Game", points.count - 1), y: .value("Net", last))
          .symbolSize(50)
          .foregroundStyle(color)
      }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: (points.min() ?? 0)...max((points.max() ?? 1), (points.min() ?? 0) + 1))
  }
}

/// Dial with tick marks and a progress arc.
struct GaugeDial: View {
  let progress: Double
  var color: Color = goalColor

  var body: some View {
    GeometryReader { geo in
      let r = min(geo.size.width, geo.size.height) / 2
      ZStack {
        ForEach(0..<60, id: \.self) { i in
          let major = i % 5 == 0
          Capsule()
            .fill(Double(i) / 60 < progress ? color.opacity(0.75) : .white.opacity(major ? 0.22 : 0.12))
            .frame(width: major ? 2 : 1.2, height: major ? 8 : 5)
            .offset(y: -r + (major ? 5 : 3.5))
            .rotationEffect(.degrees(Double(i) * 6))
        }
        Circle().stroke(track, lineWidth: 5).padding(16)
        Circle()
          .trim(from: 0, to: max(0.001, progress))
          .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .padding(16)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }
}

// MARK: - RP Today

struct RPTodayView: View {
  @Environment(\.widgetFamily) var family
  let entry: TrackerEntry

  var today: Snapshot.Today { entry.snapshot?.todayIfCurrent ?? .init(delta: 0, matches: 0, wins: 0, losses: 0) }

  var body: some View {
    content.containerBackground(for: .widget) { cardBackground }
  }

  @ViewBuilder var content: some View {
    switch family {
    case .accessoryInline:
      Label("\(entry.game.title) \(signed(today.delta)) \(entry.game.unit) today", systemImage: "chart.line.uptrend.xyaxis")
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: -2) {
          Text(signed(today.delta)).font(display(20)).minimumScaleFactor(0.5)
          Text(entry.game.unit).font(grotesk(9, .medium).monospacedDigit())
        }
      }
      .widgetAccentable()
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text("Today · \(today.matches) games").font(grotesk(10, .medium).monospacedDigit())
        Text("\(signed(today.delta)) \(entry.game.unit)").font(display(26)).widgetAccentable()
        Text("\(today.wins)W \(today.losses)L").font(grotesk(11))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    default:
      if entry.state == .notLinked {
        NotLinkedView(game: entry.game)
      } else if family == .systemMedium {
        HStack(spacing: 18) {
          todayBlock
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
      HStack(spacing: 6) {
        GameLogo(game: entry.game, size: 12, color: entry.game.accent)
        MonoLabel("Today · \(today.matches) games", color: textFaint, size: 10)
      }
      Spacer(minLength: 2)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(signed(today.delta))
          .font(display(50, .bold))
          .foregroundStyle(deltaColor(today.delta))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .contentTransition(.numericText())
        Text(entry.game.unit).font(display(16, .bold)).foregroundStyle(textDim)
      }
      Text(today.best.map { "Net \(entry.game.unit) · best \(signed($0))" } ?? "No games yet")
        .font(grotesk(12))
        .foregroundStyle(textDim)
      Spacer(minLength: 4)
      if let series = today.series, !series.isEmpty {
        Sparkline(values: series, color: entry.game.accent).frame(height: 36)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  var rankBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      MonoLabel("Current rank", color: textFaint, size: 10)
      Spacer(minLength: 0)
      HStack(spacing: 8) {
        RankIcon(image: entry.rankImage, name: entry.snapshot?.rank?.name ?? "", size: 30)
        Text((entry.snapshot?.rankLabel ?? "—").uppercased()).font(display(20)).lineLimit(1).minimumScaleFactor(0.6)
      }
      if let score = entry.snapshot?.score {
        Text(entry.game == .apex ? "\(score.formatted()) RP" : "\(entry.snapshot?.rank?.rr ?? 0) RR")
          .font(display(22, .bold))
      }
      Spacer(minLength: 0)
      HStack(spacing: 10) {
        Text("\(today.wins)W").font(display(16, .bold)).foregroundStyle(gain)
        Text("\(today.losses)L").font(display(16, .bold)).foregroundStyle(loss)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Rank Goal

struct RankGoalView: View {
  @Environment(\.widgetFamily) var family
  let entry: TrackerEntry

  var score: Int { entry.snapshot?.score ?? 0 }
  var progress: Double { entry.goal?.progress(score) ?? 0 }
  var remaining: Int { max(0, (entry.goal?.targetScore ?? 0) - score) }

  var body: some View {
    content.containerBackground(for: .widget) { cardBackground }
  }

  @ViewBuilder var content: some View {
    switch family {
    case .accessoryInline:
      Label(entry.goal.map { "\(Int(progress * 100))% to \($0.label)" } ?? "No rank goal", systemImage: "scope")
    case .accessoryCircular:
      Gauge(value: progress) {
        Image(systemName: "scope")
      } currentValueLabel: {
        Text("\(Int(progress * 100))")
      }
      .gaugeStyle(.accessoryCircularCapacity)
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.goal.map { "→ \($0.label)" } ?? "No goal set").font(display(17))
        ProgressView(value: progress).widgetAccentable()
        Text(entry.goal == nil ? entry.game.title : "\(remaining.formatted()) \(entry.game.unit) to go").font(grotesk(11))
      }
    default:
      if entry.state == .notLinked {
        NotLinkedView(game: entry.game)
      } else if family == .systemMedium {
        medium.foregroundStyle(.white)
      } else {
        small.foregroundStyle(.white)
      }
    }
  }

  /// Wingman-style: current rank | rank goal.
  var medium: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: "shield.fill").font(grotesk(10)).foregroundStyle(textDim)
          MonoLabel("Current rank", size: 10)
        }
        HStack(spacing: 8) {
          RankIcon(image: entry.rankImage, name: entry.snapshot?.rank?.name ?? "", size: 30)
          Text((entry.snapshot?.rankLabel ?? "—").uppercased()).font(display(21)).lineLimit(1).minimumScaleFactor(0.6)
        }
        Text(entry.game == .apex ? "\(score.formatted()) RP" : "\(entry.snapshot?.rank?.rr ?? 0) RR")
          .font(display(24, .bold))
        Spacer(minLength: 0)
        MonoLabel("Today", size: 10)
        let today = entry.snapshot?.todayIfCurrent ?? .init(delta: 0, matches: 0, wins: 0, losses: 0)
        Text("\(signed(today.delta)) \(entry.game.unit) · \(today.matches) games")
          .font(display(15, .bold))
          .foregroundStyle(deltaColor(today.delta))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: "scope").font(grotesk(10)).foregroundStyle(textDim)
          MonoLabel("Rank goal", size: 10)
        }
        if let goal = entry.goal {
          HStack(spacing: 8) {
            RankIcon(image: entry.goalImage, name: goal.label, size: 30)
            Text(goal.label.uppercased()).font(display(21)).foregroundStyle(goalSoft).lineLimit(1).minimumScaleFactor(0.6)
          }
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(remaining == 0 ? "DONE" : remaining.formatted()).font(display(24, .bold))
            Text("\(entry.game.unit) to go").font(grotesk(11)).foregroundStyle(textDim).lineLimit(1)
          }
          Spacer(minLength: 0)
          Text("\(score.formatted()) / \(goal.targetScore.formatted())")
            .font(grotesk(10).monospacedDigit())
            .foregroundStyle(textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          ProgressView(value: progress).tint(goalColor)
          Text(paceText).font(grotesk(11)).foregroundStyle(textDim).lineLimit(1)
        } else {
          Text("SET A GOAL").font(display(21)).foregroundStyle(goalSoft)
          Spacer(minLength: 0)
          Text("Open the app and tap Rank goal.").font(grotesk(11)).foregroundStyle(textDim)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  var paceText: String {
    // Wingman-style: the pace needed to make the goal before the split resets.
    if let end = entry.snapshot?.season?.splitEndDate, end > .now {
      let hours = Int(end.timeIntervalSinceNow / 3600)
      let ends = hours < 24 ? "Split ends in \(hours)h" : "Split ends in \(hours / 24)d"
      guard remaining > 0 else { return ends }
      let perDay = Int((Double(remaining) / Double(max(1, hours / 24))).rounded(.up))
      return "\(ends) · ~\(perDay) \(entry.game.unit)/day"
    }
    guard let pace = entry.snapshot?.pacePerDay else { return "\(Int(progress * 100))% of the way" }
    guard pace > 0, remaining > 0 else { return "~\(pace) \(entry.game.unit)/day" }
    let days = Int((Double(remaining) / Double(pace)).rounded(.up))
    return "~\(pace) \(entry.game.unit)/day · \(days)d"
  }

  var small: some View {
    VStack(spacing: 4) {
      HStack {
        MonoLabel("Rank goal", color: textFaint, size: 10)
        Spacer(minLength: 0)
        Text("\(Int(progress * 100))%").font(display(14, .bold)).foregroundStyle(goalColor)
      }
      if let goal = entry.goal {
        ZStack {
          GaugeDial(progress: progress)
          VStack(spacing: 0) {
            Text(remaining == 0 ? "✓" : remaining.formatted()).font(display(24)).minimumScaleFactor(0.5).lineLimit(1)
            Text("\(entry.game.unit) to go").font(grotesk(7, .medium).monospacedDigit()).foregroundStyle(textDim)
          }
          .padding(.horizontal, 26)
        }
        Text(goal.label.uppercased()).font(display(14)).foregroundStyle(goalSoft).lineLimit(1)
      } else {
        Spacer()
        Text("SET A GOAL").font(display(20)).foregroundStyle(goalSoft)
        Text("In the app").font(grotesk(11)).foregroundStyle(textDim)
        Spacer()
      }
    }
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
          .foregroundStyle(LinearGradient(colors: [entry.game.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("Day", point.index), y: .value("Score", point.score))
          .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
          .foregroundStyle(entry.game.accent)
      }
      if let last = points.last {
        PointMark(x: .value("Day", last.index), y: .value("Score", last.score))
          .symbolSize(lineWidth * 18)
          .foregroundStyle(entry.game.accent)
      }
      if goalVisible, let goal {
        RuleMark(y: .value("Goal", goal))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          .foregroundStyle(goalColor.opacity(0.8))
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
    content.containerBackground(for: .widget) { cardBackground }
  }

  @ViewBuilder var content: some View {
    if family == .accessoryRectangular {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("\(signed(weekDelta)) \(entry.game.unit)").font(display(16))
          Spacer(minLength: 0)
          Text(entry.climbRange.short).font(grotesk(10, .medium).monospacedDigit())
        }
        ClimbChart(entry: entry, showGoal: false, lineWidth: 2).widgetAccentable()
      }
    } else if entry.state == .notLinked {
      NotLinkedView(game: entry.game)
    } else if (entry.snapshot?.chartPoints.count ?? 0) < 2 {
      VStack(alignment: .leading) {
        MonoLabel("Climb · \(entry.climbRange.title)", color: textFaint, size: 10)
        Spacer()
        Text("Your climb shows up here after a few games.").font(grotesk(12)).foregroundStyle(textDim)
      }
      .foregroundStyle(.white)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          GameLogo(game: entry.game, size: 12, color: entry.game.accent)
          MonoLabel("Climb · \(entry.climbRange.title)", color: textFaint, size: 10)
          Spacer(minLength: 4)
          Text("\(signed(weekDelta)) \(entry.game.unit)")
            .font(display(15, .bold))
            .foregroundStyle(deltaColor(weekDelta))
        }
        HStack(spacing: 8) {
          if family != .systemSmall {
            RankIcon(image: entry.rankImage, name: entry.snapshot?.rank?.name ?? "", size: 26)
          }
          Text((entry.snapshot?.rankLabel ?? "—").uppercased())
            .font(display(family == .systemSmall ? 18 : 22))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
          if family != .systemSmall, let score = entry.snapshot?.score {
            Text(entry.game == .apex ? "\(score.formatted()) RP" : "\(entry.snapshot?.rank?.rr ?? 0) RR")
              .font(grotesk(12).monospacedDigit())
              .foregroundStyle(textDim)
          }
        }
        ClimbChart(entry: entry, showGoal: family != .systemSmall)
        if family == .systemLarge { recentMatches }
      }
      .foregroundStyle(.white)
    }
  }

  var recentMatches: some View {
    VStack(spacing: 8) {
      ForEach(Array((entry.snapshot?.matches ?? []).prefix(5).enumerated()), id: \.offset) { _, match in
        let title = [match.legend ?? match.agent, match.map].compactMap { $0 }.joined(separator: " · ")
        let color = match.kind == "adjust" ? textDim : deltaColor(match.delta)
        HStack(spacing: 10) {
          RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 22)
          Text((title.isEmpty ? "Ranked match" : title).uppercased())
            .font(display(14, .bold))
            .lineLimit(1)
          Spacer()
          Text(matchDate(Date(timeIntervalSince1970: match.ts / 1000)))
            .font(grotesk(10).monospacedDigit())
            .foregroundStyle(textDim)
          Text(signed(match.delta))
            .font(display(15, .bold))
            .foregroundStyle(color)
            .frame(width: 44, alignment: .trailing)
        }
      }
    }
    .padding(.top, 6)
  }
}

// MARK: - Map Rotation

struct MapRotationView: View {
  @Environment(\.widgetFamily) var family
  let entry: RotationEntry

  var body: some View {
    content.containerBackground(for: .widget) { background }
  }

  @ViewBuilder var background: some View {
    if let art = entry.art, family == .systemSmall || family == .systemMedium {
      ZStack {
        Image(uiImage: art).resizable().scaledToFill()
        LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
      }
    } else {
      cardBackground
    }
  }

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
          Text(String((entry.current ?? "?").prefix(3)).uppercased()).font(display(15))
        }
        .progressViewStyle(.circular)
        .widgetAccentable()
      } else {
        ZStack {
          AccessoryWidgetBackground()
          Text(String((entry.current ?? "?").prefix(3)).uppercased()).font(display(16))
        }
      }
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text(entry.mode.title).font(grotesk(10, .medium).monospacedDigit())
        Text((entry.current ?? "—").uppercased()).font(display(20)).lineLimit(1).widgetAccentable()
        HStack(spacing: 4) {
          countdown
          if let next = entry.next { Text("→ \(next)").lineLimit(1) }
        }
        .font(grotesk(11).monospacedDigit())
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    default:
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          MonoLabel(entry.mode.title, color: .white, size: 10)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12)))
          Spacer(minLength: 0)
          if family == .systemMedium, let next = entry.next {
            MonoLabel("Next: \(next)", color: textDim, size: 9)
          }
        }
        Spacer(minLength: 0)
        HStack(spacing: 6) {
          Circle().fill(accent).frame(width: 6, height: 6)
          MonoLabel("Now playing", color: accent, size: 10)
        }
        Text((entry.current ?? "—").uppercased())
          .font(display(family == .systemSmall ? 28 : 34))
          .lineLimit(1)
          .minimumScaleFactor(0.5)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          countdown.font(grotesk(family == .systemSmall ? 16 : 20, .medium).monospacedDigit())
          if let end = entry.end, family == .systemMedium {
            Text("Ends \(end.formatted(date: .omitted, time: .shortened))")
              .font(grotesk(10).monospacedDigit())
              .foregroundStyle(textDim)
          }
        }
        if let start = entry.start, let end = entry.end, end > start {
          ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(accent)
        }
      }
      .foregroundStyle(.white)
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
  RankGoalWidget()
} timeline: {
  TrackerEntry.preview(.apex)
}

#Preview(as: .systemSmall) {
  RPTodayWidget()
} timeline: {
  TrackerEntry.preview(.apex)
}

#Preview(as: .systemSmall) {
  MapRotationWidget()
} timeline: {
  RotationEntry.preview(.ranked)
}
