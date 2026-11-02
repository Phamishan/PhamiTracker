import AppIntents
import SwiftUI
import WidgetKit

// Home-screen and lock-screen widgets: "RP Today" and "Rank Goal".
//
// The app writes the worker URL, linked accounts and goals into the App Group (see
// widget_bridge.dart / AppDelegate.swift). Each timeline refresh fetches fresh numbers straight
// from the worker, which polls the game APIs every minute, so the widgets stay current even
// when the app hasn't been opened all day.

let appGroup = "group.phamishan.phamitracker"

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
  var gradient: [Color] {
    self == .apex
      ? [Color(hex: 0xFF2E4D), Color(hex: 0xFF8A00)]
      : [Color(hex: 0xFF4655), Color(hex: 0x8B2CF5)]
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

  let score: Int?
  let rankLabel: String?
  let rank: Rank?
  let today: Today?
  let status: Status?
  let polledAt: Double?

  var polledDate: Date? { polledAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

  /// A cached snapshot from yesterday shouldn't claim yesterday's points as today's.
  var todayIfCurrent: Today {
    guard let today, let polled = polledDate, Calendar.current.isDateInToday(polled) else {
      return Today(delta: 0, matches: 0, wins: 0, losses: 0)
    }
    return today
  }

  var isLive: Bool { status?.inGame == true || status?.online == true }
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
    TrackerEntry(
      date: .now,
      game: game,
      state: .ready,
      name: game == .apex ? "Phami" : "Phami#EUW",
      snapshot: Snapshot(
        score: game == .apex ? 10_900 : 1_542,
        rankLabel: game == .apex ? "Platinum I" : "Diamond 1",
        rank: .init(name: game == .apex ? "Platinum" : "Diamond 1", rr: 42),
        today: .init(delta: 184, matches: 3, wins: 2, losses: 1),
        status: .init(online: true, inGame: false),
        polledAt: Date.now.timeIntervalSince1970 * 1000
      ),
      goal: Goal(label: game == .apex ? "Diamond IV" : "Ascendant 1", targetScore: game == .apex ? 11_400 : 1_800, startScore: game == .apex ? 10_100 : 1_400)
    )
  }
}

enum TrackerStore {
  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  static func config() -> SharedConfig? {
    guard let json = defaults?.string(forKey: "config"), let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SharedConfig.self, from: data)
  }

  static func cached(_ game: TrackedGame) -> Snapshot? {
    guard let data = defaults?.data(forKey: "snapshot.\(game.rawValue)") else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
  }

  static func cache(_ snapshot: Snapshot, for game: TrackedGame) {
    if let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: "snapshot.\(game.rawValue)") }
  }

  static func load(_ game: TrackedGame) async -> TrackerEntry {
    guard let config = config(), let account = config.games[game.rawValue] else {
      return TrackerEntry(date: .now, game: game, state: .notLinked, name: "", snapshot: nil, goal: nil)
    }
    var snapshot = cached(game) ?? account.snapshot
    if let fresh = await fetch(config: config, playerId: account.playerId) {
      snapshot = fresh
      cache(fresh, for: game)
    }
    return TrackerEntry(date: .now, game: game, state: .ready, name: account.name, snapshot: snapshot, goal: account.goal)
  }

  static func fetch(config: SharedConfig, playerId: String) async -> Snapshot? {
    let offset = TimeZone.current.secondsFromGMT() / 60
    guard let url = URL(string: "\(config.apiUrl)/v1/players/\(playerId)/widget?tzOffset=\(offset)") else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue(config.appKey, forHTTPHeaderField: "x-app-key")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
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

// MARK: - Widgets

struct RPTodayWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "RPToday", intent: GameIntent.self, provider: Provider()) { entry in
      RPTodayView(entry: entry)
    }
    .configurationDisplayName("RP Today")
    .description("Rank points won or lost today.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
  }
}

struct RankGoalWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "RankGoal", intent: GameIntent.self, provider: Provider()) { entry in
      RankGoalView(entry: entry)
    }
    .configurationDisplayName("Rank Goal")
    .description("Your progress towards the rank you're grinding for.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
  }
}

@main
struct PhamiTrackerWidgets: WidgetBundle {
  var body: some Widget {
    RPTodayWidget()
    RankGoalWidget()
  }
}

// MARK: - Views

private let surface = Color(hex: 0x11111B)
private let gain = Color(hex: 0x2EE59D)
private let loss = Color(hex: 0xFF4D6D)
private let cyan = Color(hex: 0x26D9FF)

private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

private func deltaColor(_ n: Int) -> Color { n > 0 ? gain : n < 0 ? loss : .white.opacity(0.7) }

struct GameHeader: View {
  let entry: TrackerEntry

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: entry.game.symbol).font(.system(size: 11, weight: .black))
      Text(entry.game.title).font(.system(size: 11, weight: .black)).tracking(1)
      Spacer(minLength: 0)
      if entry.snapshot?.isLive == true {
        Circle().fill(Color(hex: 0x3DFF8B)).frame(width: 7, height: 7)
          .shadow(color: Color(hex: 0x3DFF8B), radius: 4)
      }
    }
  }
}

struct NotLinkedView: View {
  let game: TrackedGame

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: game.symbol).font(.title2.weight(.black))
      Spacer(minLength: 0)
      Text("Link \(game == .apex ? "Apex" : "VALORANT")").font(.headline.weight(.heavy))
      Text("Open PhamiTracker to start tracking.").font(.caption2).opacity(0.85)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

struct RPTodayView: View {
  @Environment(\.widgetFamily) var family
  let entry: TrackerEntry

  var today: Snapshot.Today { entry.snapshot?.todayIfCurrent ?? .init(delta: 0, matches: 0, wins: 0, losses: 0) }

  var body: some View {
    content.containerBackground(for: .widget) {
      LinearGradient(colors: entry.game.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }

  @ViewBuilder var content: some View {
    switch family {
    case .accessoryInline:
      Text("\(entry.game.title) \(signed(today.delta)) \(entry.game.unit) today")
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Text(entry.game.title).font(.caption2.weight(.black))
        Text("\(signed(today.delta)) \(entry.game.unit)").font(.title3.weight(.heavy)).widgetAccentable()
        Text("\(today.matches) games · \(today.wins)W \(today.losses)L").font(.caption2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    default:
      if entry.state == .notLinked {
        NotLinkedView(game: entry.game)
      } else if family == .systemMedium {
        HStack(spacing: 16) {
          todayBlock
          Divider().overlay(.white.opacity(0.35))
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
        .font(.system(size: 40, weight: .black, design: .rounded))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .contentTransition(.numericText())
      Text("\(entry.game.unit) today").font(.system(size: 13, weight: .heavy)).opacity(0.85)
      Spacer(minLength: 0)
      Text("\(today.matches) games · \(today.wins)W \(today.losses)L")
        .font(.system(size: 11, weight: .bold))
        .opacity(0.85)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  var rankBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.name).font(.system(size: 12, weight: .bold)).lineLimit(1).opacity(0.85)
      Spacer(minLength: 0)
      Text(entry.snapshot?.rankLabel ?? "—")
        .font(.system(size: 20, weight: .black))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
      if let score = entry.snapshot?.score {
        Text(entry.game == .apex ? "\(score.formatted()) RP" : "\(entry.snapshot?.rank?.rr ?? 0) RR")
          .font(.system(size: 13, weight: .heavy))
          .opacity(0.9)
      }
      Spacer(minLength: 0)
      if let polled = entry.snapshot?.polledDate {
        Text("Updated \(polled, style: .relative) ago").font(.system(size: 10, weight: .semibold)).opacity(0.75)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct GoalRing: View {
  let progress: Double
  let colors: [Color]
  var lineWidth: CGFloat = 10

  var body: some View {
    ZStack {
      Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
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
  var ringColors: [Color] { entry.game.gradient + [cyan] }

  var body: some View {
    content.containerBackground(for: .widget) {
      ZStack {
        surface
        LinearGradient(colors: entry.game.gradient.map { $0.opacity(0.28) }, startPoint: .topLeading, endPoint: .bottomTrailing)
      }
    }
  }

  @ViewBuilder var content: some View {
    switch family {
    case .accessoryCircular:
      Gauge(value: progress) {
        Image(systemName: entry.game.symbol)
      } currentValueLabel: {
        Text("\(Int(progress * 100))")
      }
      .gaugeStyle(.accessoryCircularCapacity)
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.goal.map { "→ \($0.label)" } ?? "No goal set").font(.caption.weight(.black))
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
          Image(systemName: "flag.checkered").font(.title.weight(.bold)).foregroundStyle(cyan)
          Text("Set a rank goal in the app").font(.system(size: 13, weight: .heavy))
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
            .font(.system(size: 11, weight: .heavy))
            .opacity(0.85)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
      }
    }
  }

  var ring: some View {
    ZStack {
      GoalRing(progress: progress, colors: ringColors, lineWidth: family == .systemMedium ? 12 : 10)
      VStack(spacing: 0) {
        Text("\(Int(progress * 100))%").font(.system(size: family == .systemMedium ? 26 : 22, weight: .black, design: .rounded))
        Text(entry.goal?.label ?? "").font(.system(size: 9, weight: .heavy)).foregroundStyle(cyan).lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      .padding(.horizontal, 12)
    }
  }

  var details: some View {
    VStack(alignment: .leading, spacing: 4) {
      GameHeader(entry: entry)
      Spacer(minLength: 0)
      Text(entry.snapshot?.rankLabel ?? "—").font(.system(size: 13, weight: .bold)).opacity(0.85)
      Text("→ \(entry.goal?.label ?? "")").font(.system(size: 20, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
      Text(remaining == 0 ? "Goal reached! 🎉" : "\(remaining.formatted()) \(entry.game.unit) to go")
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(cyan)
      Spacer(minLength: 0)
      let today = entry.snapshot?.todayIfCurrent.delta ?? 0
      Text("\(signed(today)) \(entry.game.unit) today")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(deltaColor(today))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview(as: .systemSmall) {
  RPTodayWidget()
} timeline: {
  TrackerEntry.preview(.apex)
  TrackerEntry.preview(.valorant)
}

#Preview(as: .systemMedium) {
  RankGoalWidget()
} timeline: {
  TrackerEntry.preview(.apex)
}
