import SwiftUI
import WidgetKit

private struct AgendaEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetAgendaSnapshot?
}

private struct AgendaProvider: TimelineProvider {
  func placeholder(in context: Context) -> AgendaEntry {
    AgendaEntry(date: .now, snapshot: .preview)
  }

  func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
    completion(AgendaEntry(date: .now, snapshot: context.isPreview ? .preview : loadSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
    let now = Date()
    let snapshot = loadSnapshot()
    let dates = [now] + (snapshot?.transitionDates(after: now) ?? []).prefix(32)
    let entries = dates.map { AgendaEntry(date: $0, snapshot: snapshot) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
  }

  private func loadSnapshot() -> WidgetAgendaSnapshot? {
    guard let url = WidgetAgendaStore.sharedURL() else { return nil }
    return WidgetAgendaStore.read(from: url)
  }
}

private struct AgendaWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetAgendaStore.widgetKind, provider: AgendaProvider()) { entry in
      AgendaWidgetView(entry: entry)
    }
    .configurationDisplayName("Until")
    .description("Today's events from Until")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}

@main struct UntilWidgets: WidgetBundle {
  var body: some Widget { AgendaWidget() }
}

private struct AgendaWidgetView: View {
  let entry: AgendaEntry

  private var presentation: WidgetAgendaPresentation? {
    entry.snapshot?.presentation(at: entry.date)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(localized("Today"))
          .font(.caption.weight(.bold))
        Spacer()
        Text(entry.date, format: .dateTime.month().day().weekday(.abbreviated))
          .font(.caption2)
      }
      .foregroundStyle(.secondary)
      .padding(.bottom, 2)

      if let snapshot = entry.snapshot, snapshot.authenticated, let presentation {
        if let hero = presentation.hero {
          ForEach(presentation.allDay.indices, id: \.self) { index in
            allDayRow(presentation.allDay[index])
          }
          if hero.startDate > entry.date {
            nowLine()
          }
          heroRow(hero)
          footer(snapshot: snapshot, presentation: presentation)
        } else if !presentation.allDay.isEmpty {
          ForEach(presentation.allDay.indices, id: \.self) { index in
            allDayRow(presentation.allDay[index])
          }
          Spacer(minLength: 0)
          footer(snapshot: snapshot, presentation: presentation)
        } else {
          emptyMessage(presentation.coversDay ? localized("No events today") : localized("Open Until to refresh"))
        }
      } else {
        emptyMessage(entry.snapshot?.authenticated == false
          ? localized("Open Until to sign in") : localized("Open Until to refresh"))
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(Color(nsColor: .textBackgroundColor), for: .widget)
    .widgetURL(URL(string: "until://agenda"))
  }

  private func allDayRow(_ event: WidgetAgendaEvent) -> some View {
    HStack(spacing: 0) {
      Text(localized("all-day"))
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 52, alignment: .trailing)
      railNode(color: Color(hex: event.colorHex) ?? .accentColor, size: 7)
      Text(event.title)
        .font(.system(size: 12))
        .lineLimit(1)
    }
    .frame(height: 17)
  }

  private func nowLine() -> some View {
    HStack(spacing: 0) {
      Text(entry.date, format: .dateTime.hour().minute())
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(.green)
        .frame(width: 52, alignment: .trailing)
      railNode(color: .green, size: 7)
      Capsule()
        .fill(.green)
        .frame(height: 2)
    }
    .frame(height: 13)
  }

  private func heroRow(_ event: WidgetAgendaEvent) -> some View {
    let isNow = event.startDate <= entry.date
    let tint: Color = isNow ? .green : .accentColor
    return HStack(alignment: .top, spacing: 0) {
      Text(event.startDate, format: .dateTime.hour().minute())
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(tint)
        .frame(width: 52, alignment: .trailing)
        .padding(.top, 9)
      railNode(color: tint, size: 10)
        .padding(.top, 7)
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(isNow ? "NOW" : "NEXT")
            .tracking(0.6)
          Spacer(minLength: 3)
          Text(isNow ? event.endDate : event.startDate, style: .relative)
            .monospacedDigit()
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(tint)
        Text(event.title)
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(event.startDate, format: .dateTime.hour().minute())
          + Text("–")
          + Text(event.endDate, format: .dateTime.hour().minute())
      }
      .font(.system(size: 10))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    .frame(height: 58, alignment: .top)
  }

  private func footer(
    snapshot: WidgetAgendaSnapshot,
    presentation: WidgetAgendaPresentation
  ) -> some View {
    Group {
      if let lastSync = snapshot.lastSync, entry.date.timeIntervalSince(lastSync) > 6 * 3600 {
        Text(localized("Open Until to refresh"))
      } else if presentation.hiddenCount > 0 {
        Text(String(format: localized("more_count"), presentation.hiddenCount))
      } else {
        Text(" ")
      }
    }
    .font(.system(size: 10, weight: .medium))
    .foregroundStyle(.secondary)
    .padding(.leading, 74)
    .padding(.top, 2)
  }

  private func emptyMessage(_ message: String) -> some View {
    HStack {
      Spacer()
      Text(message)
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
      Spacer()
    }
    .frame(maxHeight: .infinity)
  }

  private func railNode(color: Color, size: CGFloat) -> some View {
    ZStack {
      Rectangle()
        .fill(Color.primary.opacity(0.1))
        .frame(width: 1)
      Circle()
        .fill(color)
        .frame(width: size, height: size)
    }
    .frame(width: 22)
    .frame(maxHeight: .infinity)
  }
}

private func localized(_ key: String) -> String {
  NSLocalizedString(key, bundle: .main, comment: "")
}

private extension Color {
  init?(hex: String) {
    let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
    self.init(
      .sRGB,
      red: Double((number >> 16) & 0xff) / 255,
      green: Double((number >> 8) & 0xff) / 255,
      blue: Double(number & 0xff) / 255,
      opacity: 1
    )
  }
}

private extension WidgetAgendaSnapshot {
  static let preview = WidgetAgendaSnapshot(
    authenticated: true,
    lastSync: .now,
    coverageEnd: .now.addingTimeInterval(48 * 3600),
    events: [
      WidgetAgendaEvent(
        title: "Focus time",
        startDate: Calendar.current.startOfDay(for: .now),
        endDate: Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 3600),
        allDay: true,
        colorHex: "#4b87e8"
      ),
      WidgetAgendaEvent(
        title: "Design review",
        startDate: .now.addingTimeInterval(12 * 60),
        endDate: .now.addingTimeInterval(72 * 60),
        allDay: false,
        colorHex: "#087afb"
      )
    ]
  )
}
