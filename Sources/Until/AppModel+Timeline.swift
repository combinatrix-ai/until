import Foundation

/// Pure timeline selection and layout decisions kept separate from
/// AppModel's account, persistence, and side-effect orchestration.
extension AppModel {
  static func groupByDay(
    timed: [CalendarEvent],
    allDay: [CalendarEvent],
    now: Date,
    lookaheadHours: Int
  ) -> [DaySection] {
    let calendar = Calendar.current
    let windowStart = calendar.startOfDay(for: now)
    let windowEndDay = calendar.startOfDay(
      for: now.addingTimeInterval(TimeInterval(max(0, lookaheadHours) * 3600))
    )

    // All-day events span [startDate, endDate) where endDate is exclusive
    // (Google's `end.date` is the day after the last day). Repeat each event on
    // every covered day within the visible window.
    var allDayByDay: [Date: [CalendarEvent]] = [:]
    for event in allDay {
      var day = max(calendar.startOfDay(for: event.startDate), windowStart)
      while day < event.endDate && day <= windowEndDay {
        allDayByDay[day, default: []].append(event)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      }
    }

    var timedByDay: [Date: [CalendarEvent]] = [:]
    for event in timed {
      let eventDay = calendar.startOfDay(for: event.startDate)
      // Calendar APIs return an event that overlaps today even when it began
      // before today's time window. Place that active interval in today's
      // section so the now-line and hero share one chronological rail.
      let day = eventDay < windowStart && event.endDate > windowStart ? windowStart : eventDay
      timedByDay[day, default: []].append(event)
    }

    let days = Set(allDayByDay.keys).union(timedByDay.keys).sorted()
    return days.map { day in
      let events = (allDayByDay[day] ?? []) + (timedByDay[day] ?? [])
      return DaySection(day: day, rows: events.map { DayEvent(day: day, event: $0) })
    }
  }

  /// Gaps at or above this length between two consecutive timed rows earn a
  /// "free until …" divider in the popover list.
  static let freeGapThresholdMinutes = 30

  /// Pure: interleaves `FreeGap` dividers into `rows` wherever two
  /// consecutive TIMED rows are separated by at least
  /// `freeGapThresholdMinutes` and the gap hasn't already elapsed. `rows` is
  /// assumed pre-ordered as `DaySection.rows` provides it (all-day first,
  /// then timed by start time), which keeps every section's timed rows
  /// already contiguous, so only adjacent timed pairs need checking. All-day
  /// rows pass through untouched and never bracket a gap.
  static func insertingFreeGaps(_ rows: [DayEvent], now: Date) -> [PopoverListItem] {
    var result: [PopoverListItem] = []
    var previousTimed: DayEvent?
    for row in rows {
      if !row.event.allDay, let previous = previousTimed {
        let gapMinutes = row.event.startDate.timeIntervalSince(previous.event.endDate) / 60
        if gapMinutes >= Double(freeGapThresholdMinutes), row.event.startDate > now {
          result.append(
            .gap(
              FreeGap(
                afterActionKey: previous.event.actionKey,
                until: row.event.startDate,
                durationMinutes: max(0, Int(gapMinutes.rounded()))
              )
            )
          )
        }
      }
      result.append(.event(row))
      if !row.event.allDay {
        previousTimed = row
      }
    }
    return result
  }

  /// `events` is assumed sorted by start date. `static` (taking `config`
  /// explicitly rather than reading `self.config`) so tests can exercise it
  /// deterministically without a live `AppModel` instance or wall clock —
  /// same rationale as `groupByDay`.
  ///
  /// When `menubarPrefersImminentNext` is on, this deliberately reuses
  /// `notifyLeadMinutes` (even if notifications are disabled) so the menubar
  /// switches to the next event at the same moment its reminder notification
  /// fires, rather than waiting for the current event to end. This also
  /// applies when no event is currently ongoing — in that case it behaves
  /// identically to the existing upcoming-event branches below once the
  /// next event enters its lead window, so no special-casing is needed.
  ///
  /// Events skipped via `skipInMenubar` are excluded up front, before any
  /// branch below, so a skip always takes effect regardless of which branch
  /// would otherwise have picked it. The popover list (`state.events` /
  /// `daySections`) is built separately in `reapplyFilter` and is never
  /// passed through this filtering, so skipped events stay visible there.
  ///
  /// Among events already in progress (`startDate <= now && endDate > now`),
  /// the one with the LATEST startDate wins — the meeting most recently
  /// entered, not the earliest-starting one. Without this, a double-booked
  /// event B that starts while an older meeting A is still running would
  /// either keep showing A after the user has already moved on to B, or —
  /// combined with `menubarPrefersImminentNext` switching the menubar to B
  /// slightly before it starts — bounce back to A the instant B's start time
  /// arrives. Ties (equal startDate) fall back to `events`'s existing order,
  /// which `reapplyFilter` already sorts deterministically via `compareEvents`.
  static func pickMenubarEvent(
    config: AppConfig,
    timed timedCandidates: [CalendarEvent],
    allDay allDayCandidates: [CalendarEvent],
    now: Date
  ) -> CalendarEvent? {
    let events = timedCandidates.filter { config.skippedMenubarEvents[$0.actionKey] == nil }
    let allDayEvents = allDayCandidates.filter { config.skippedMenubarEvents[$0.actionKey] == nil }
    if config.menubarPrefersImminentNext {
      let lead = TimeInterval(max(0, config.notifyLeadMinutes) * 60)
      if let imminent = events.first(where: { event in
        let startsIn = event.startDate.timeIntervalSince(now)
        return startsIn >= 0 && startsIn <= lead
      }) {
        return imminent
      }
    }
    var mostRecentlyEntered: CalendarEvent?
    for event in events {
      guard event.startDate <= now, event.endDate > now else { continue }
      guard let candidate = mostRecentlyEntered else {
        mostRecentlyEntered = event
        continue
      }
      if event.startDate > candidate.startDate {
        mostRecentlyEntered = event
      }
    }
    if let mostRecentlyEntered {
      return mostRecentlyEntered
    }
    if config.menubarShowsNextAlways {
      // Always surface the next upcoming timed event, regardless of lead time.
      if let upcoming = events.first(where: { $0.startDate.timeIntervalSince(now) >= 0 }) {
        return upcoming
      }
    } else {
      let lead = TimeInterval(max(0, config.menubarLeadMinutes) * 60)
      if let upcoming = events.first(where: { event in
        let startsIn = event.startDate.timeIntervalSince(now)
        return startsIn >= 0 && startsIn <= lead
      }) {
        return upcoming
      }
    }
    return allDayEvents.first { event in
      event.startDate <= now && event.endDate > now
    }
  }

  /// Pure picker for the popover rail's green NOW emphasis: the in-progress
  /// event that is not itself the inline hero (`menubarEvent`). Mirrors
  /// `pickMenubarEvent`'s testable shape (explicit `config`/`now`, no `self`
  /// access) for the same reason.
  ///
  /// Returns nil whenever `menubarEvent` is a timed, in-progress event — the
  /// hero already renders that "Now" state, and showing the same event in
  /// both the hero and the rail emphasis would be redundant. An all-day
  /// menubar event is never "in progress" for this purpose (the hero has no
  /// countdown for it), so it never suppresses the emphasis.
  ///
  /// Otherwise, among `timed`, candidates are events currently in progress,
  /// not menubar-skipped (a skip means "stop surfacing this near the
  /// menubar"; the event still shows in the popover list), and distinct from
  /// `menubarEvent` itself. The candidate ending SOONEST wins — "when am I
  /// next free" — the opposite tie-break from `pickMenubarEvent` (latest
  /// started): the two answer different questions, so a double booking can
  /// legitimately show one event in the hero and a different one in the
  /// rail. Ties (equal endDate) fall back to `timed`'s existing order.
  /// All-day events never qualify since callers only pass timed events in.
  static func pickNowStripEvent(
    menubarEvent: CalendarEvent?,
    config: AppConfig,
    timed: [CalendarEvent],
    now: Date
  ) -> CalendarEvent? {
    if let menubarEvent, !menubarEvent.allDay, menubarEvent.startDate <= now, menubarEvent.endDate > now {
      return nil
    }
    var soonestEnding: CalendarEvent?
    for event in timed {
      guard event.startDate <= now, event.endDate > now else { continue }
      guard config.skippedMenubarEvents[event.actionKey] == nil else { continue }
      guard event.actionKey != menubarEvent?.actionKey else { continue }
      guard let candidate = soonestEnding else {
        soonestEnding = event
        continue
      }
      if event.endDate < candidate.endDate {
        soonestEnding = event
      }
    }
    return soonestEnding
  }

  /// Derives the hero's visual state from the same menubar event that drives
  /// the status item. All-day events intentionally have no card state because
  /// they have no countdown to display.
  enum MenubarHeroState: Equatable {
    case now
    case next
  }

  static func menubarHeroState(event: CalendarEvent?, now: Date) -> MenubarHeroState? {
    guard let event, !event.allDay, event.endDate > now else { return nil }
    return event.startDate <= now ? .now : .next
  }

  /// Returns the number of timed rows before the now-line in one day section.
  /// `nil` means the current moment is inside a rendered in-progress event, so
  /// that event's green rail treatment already marks the current position.
  static func nowLineInsertionIndex(timed: [CalendarEvent], now: Date) -> Int? {
    let ordered = timed.filter { !$0.allDay }.sorted { lhs, rhs in
      if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
      return lhs.actionKey < rhs.actionKey
    }
    guard !ordered.contains(where: { $0.startDate <= now && $0.endDate > now }) else {
      return nil
    }
    return ordered.prefix { $0.endDate <= now }.count
  }

  /// The next timed event used for the small NEXT chip. It is only meaningful
  /// while the menubar hero itself is in progress; an UP NEXT hero is already
  /// the one event carrying that emphasis.
  static func nextTimelineEvent(
    heroEvent: CalendarEvent?,
    timed: [CalendarEvent],
    now: Date
  ) -> CalendarEvent? {
    guard let heroEvent,
          menubarHeroState(event: heroEvent, now: now) == .now else { return nil }
    return timed
      .filter { !$0.allDay && $0.startDate > now && $0.actionKey != heroEvent.actionKey }
      .min {
        if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
        return $0.actionKey < $1.actionKey
      }
  }

  /// Combines the menubar selection with the popover-only emphasis decisions.
  /// The hero never gets replaced by a later-day free-day message: that would
  /// make the popover disagree with the countdown the user just clicked.
  static func timelinePresentation(
    menubarEvent: CalendarEvent?,
    config: AppConfig,
    timed: [CalendarEvent],
    now: Date,
    coverageEnd: Date?
  ) -> TimelinePresentation {
    let heroEvent = menubarEvent.flatMap { event in
      menubarHeroState(event: event, now: now) == nil ? nil : event
    }
    let nowEmphasisEvent = pickNowStripEvent(
      menubarEvent: menubarEvent,
      config: config,
      timed: timed,
      now: now
    )
    let freeDayDecision = freeDayHeroNextEvent(timed: timed, now: now)
    let calendar = Calendar.current
    let endOfToday = calendar.date(
      byAdding: .day,
      value: 1,
      to: calendar.startOfDay(for: now)
    ) ?? now
    let coverageCoversToday = coverageEnd.map { $0 >= endOfToday } ?? false
    let freeDayNextEvent: CalendarEvent?
    let isFreeDay: Bool
    switch freeDayDecision {
    case .free(let nextEvent):
      freeDayNextEvent = nextEvent
      isFreeDay = true
    case .notFree:
      freeDayNextEvent = nil
      isFreeDay = false
    }
    let showsFreeDayHero = heroEvent == nil && coverageCoversToday && isFreeDay

    return TimelinePresentation(
      heroEvent: heroEvent,
      nowEmphasisEvent: nowEmphasisEvent,
      freeDayNextEvent: showsFreeDayHero ? freeDayNextEvent : nil,
      showsFreeDayHero: showsFreeDayHero
    )
  }

  /// Produces the one continuous sequence rendered by the popover. The hero
  /// event remains a normal `.event` item and is styled as a card by the view;
  /// no event is removed for occupying that card or NOW emphasis.
  static func timelineSections(
    _ sections: [DaySection],
    presentation: TimelinePresentation,
    now: Date,
    coverageEnd: Date?
  ) -> [(section: DaySection, items: [PopoverListItem])] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    var sectionsByDay = mergedDaySections(sections)
    if sectionsByDay[today] == nil {
      sectionsByDay[today] = DaySection(day: today, rows: [])
    }

    var visible: [(section: DaySection, items: [PopoverListItem])] = []
    for day in sectionsByDay.keys.sorted() {
      guard let section = sectionsByDay[day] else { continue }
      let items = timelineItems(
        rows: section.rows,
        day: section.day,
        now: now,
        showsFreeDayHero: presentation.showsFreeDayHero && calendar.isDate(section.day, inSameDayAs: today)
      )
      guard !items.isEmpty else { continue }
      visible.append((section, items))
    }

    // `.distantFuture` is useful in pure presentation tests to mean "the
    // snapshot is known complete", but it is not a finite render horizon.
    // Treat it as complete coverage without attempting to synthesize several
    // thousand years of empty day sections.
    if let coverageEnd, coverageEnd != .distantFuture,
       let firstFutureDay = calendar.date(byAdding: .day, value: 1, to: today),
       let lastFullyCoveredDay = calendar.date(
         byAdding: .day,
         value: -1,
         to: calendar.startOfDay(for: coverageEnd)
       ) {
      func isOccupiedByTimedEvent(_ day: Date) -> Bool {
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: day) else {
          return false
        }
        return sectionsByDay.values.contains { section in
          section.rows.contains { row in
            !row.event.allDay
              && row.event.startDate < nextMidnight
              && row.event.endDate > day
          }
        }
      }

      var day = calendar.startOfDay(for: firstFutureDay)
      while day <= lastFullyCoveredDay {
        if sectionsByDay[day] == nil, !isOccupiedByTimedEvent(day) {
          visible.append((DaySection(day: day, rows: []), [.freeDay(day)]))
        }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = calendar.startOfDay(for: nextDay)
      }
    }

    return visible.sorted { $0.section.day < $1.section.day }
  }

  /// Interleaves free gaps and the now-line without changing the event order.
  static func timelineItems(
    rows: [DayEvent],
    day: Date,
    now: Date,
    showsFreeDayHero: Bool
  ) -> [PopoverListItem] {
    let calendar = Calendar.current
    let base = insertingFreeGaps(rows, now: now)
    let timed = rows.filter { !$0.event.allDay }.map(\.event)
    let nowIndex = calendar.isDate(day, inSameDayAs: now)
      ? nowLineInsertionIndex(timed: timed, now: now)
      : nil
    var result: [PopoverListItem] = []
    if showsFreeDayHero {
      result.append(.freeDayHero(day))
    }

    var timedSeen = 0
    var insertedNowLine = false
    for item in base {
      if case .event(let dayEvent) = item, !dayEvent.event.allDay,
         !insertedNowLine, nowIndex == timedSeen {
        result.append(.nowLine(now))
        insertedNowLine = true
      }
      result.append(item)
      if case .event(let dayEvent) = item, !dayEvent.event.allDay {
        timedSeen += 1
      }
    }
    if let nowIndex, !insertedNowLine, nowIndex == timedSeen {
      result.append(.nowLine(now))
    }
    return result
  }

  private static func mergedDaySections(_ sections: [DaySection]) -> [Date: DaySection] {
    var sectionsByDay: [Date: DaySection] = [:]
    for section in sections {
      let day = Calendar.current.startOfDay(for: section.day)
      let rows = section.rows.map { DayEvent(day: day, event: $0.event) }
      if var existing = sectionsByDay[day] {
        existing.rows.append(contentsOf: rows)
        existing.rows.sort { lhs, rhs in
          if lhs.event.allDay != rhs.event.allDay { return lhs.event.allDay }
          if lhs.event.startDate != rhs.event.startDate { return lhs.event.startDate < rhs.event.startDate }
          return lhs.event.actionKey < rhs.event.actionKey
        }
        sectionsByDay[day] = existing
      } else {
        sectionsByDay[day] = DaySection(day: day, rows: rows)
      }
    }
    return sectionsByDay
  }

  /// Pure decision for the popover's free-day hero. A timed event that is
  /// currently in progress — including one that started on a previous day —
  /// or a timed event later today suppresses the hero. All-day events do not,
  /// which matches `insertingFreeGaps`'s free-time semantics. The next event
  /// is the earliest future timed event in the same list the popover displays,
  /// so menubar-skipped events remain eligible here.
  static func freeDayHeroNextEvent(
    timed candidates: [CalendarEvent],
    now: Date
  ) -> FreeDayHeroDecision {
    let calendar = Calendar.current
    let timed = candidates.filter { !$0.allDay }
    if timed.contains(where: { event in
      event.endDate > now
        && (event.startDate <= now || calendar.isDate(event.startDate, inSameDayAs: now))
    }) {
      return .notFree
    }

    let next = timed
      .filter { $0.startDate > now }
      .min { lhs, rhs in lhs.startDate < rhs.startDate }
    return .free(next: next)
  }
}
