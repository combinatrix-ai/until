import Foundation

enum RuleEngine {
  static func apply(_ rule: Rule, to events: [CalendarEvent], now: Date) -> [CalendarEvent] {
    events.filter { evaluate(rule, event: $0, now: now) }
  }

  static func evaluate(_ rule: Rule, event: CalendarEvent, now: Date) -> Bool {
    let result: Bool
    switch rule.kind {
    case .group:
      let children = rule.children ?? []
      if children.isEmpty {
        result = true
      } else if rule.groupOperator == .any {
        result = children.contains { evaluate($0, event: event, now: now) }
      } else {
        result = children.allSatisfy { evaluate($0, event: event, now: now) }
      }
    case .cond:
      result = evaluateCondition(rule, event: event, now: now)
    }
    return (rule.negate ?? false) ? !result : result
  }

  private static func evaluateCondition(_ rule: Rule, event: CalendarEvent, now: Date) -> Bool {
    let field = rule.field ?? ""
    let operatorId = rule.operatorId ?? ""
    let value = rule.value ?? .null

    if let actual = stringValue(for: field, event: event) {
      return compareString(actual, operatorId, value)
    }
    if let actual = enumValue(for: field, event: event) {
      return compareEnum(actual, operatorId, value)
    }
    if let actual = boolValue(for: field, event: event) {
      return compareBool(actual, operatorId)
    }
    if let actual = numberValue(for: field, event: event) {
      return compareNumber(actual, operatorId, value)
    }

    switch field {
    case "calendar": return compareCalendar(event.calendar, operatorId, value)
    case "startsWithin": return event.startMinutesFromNow >= 0 && event.startMinutesFromNow <= Int(value.number)
    case "hour":
      let hour = Calendar.current.component(.hour, from: event.startDate)
      return compareNumber(Double(hour), operatorId, value)
    case "weekday":
      let weekday = Calendar.current.component(.weekday, from: event.startDate) - 1
      return compareEnum(String(weekday), operatorId, value)
    case "attendee":
      let needle = value.string.lowercased()
      let contains = event.attendees.contains { $0.email.lowercased().contains(needle) }
      return operatorId == "excludes" ? !contains : contains
    default:
      return true
    }
  }

  private static func stringValue(for field: String, event: CalendarEvent) -> String? {
    switch field {
    case "title": return event.title
    case "description": return event.description
    case "location": return event.location
    case "organizer": return event.organizer
    default: return nil
    }
  }

  private static func enumValue(for field: String, event: CalendarEvent) -> String? {
    switch field {
    case "selfResponse": return event.selfResponse
    case "status": return event.status
    case "transparency": return event.transparency
    default: return nil
    }
  }

  private static func boolValue(for field: String, event: CalendarEvent) -> Bool? {
    switch field {
    case "allDay": return event.allDay
    case "isRecurring": return event.isRecurring
    case "hasVideo": return !event.conferenceUrl.isEmpty
    default: return nil
    }
  }

  private static func numberValue(for field: String, event: CalendarEvent) -> Double? {
    switch field {
    case "attendeeCount": return Double(event.attendeeCount)
    case "durationMinutes": return Double(event.durationMinutes)
    default: return nil
    }
  }

  private static func compareString(_ actual: String, _ operatorId: String, _ value: RuleValue) -> Bool {
    let actualLowercased = actual.lowercased()
    let valueLowercased = value.string.lowercased()
    switch operatorId {
    case "contains": return actualLowercased.contains(valueLowercased)
    case "not_contains": return !actualLowercased.contains(valueLowercased)
    case "starts_with": return actualLowercased.hasPrefix(valueLowercased)
    case "ends_with": return actualLowercased.hasSuffix(valueLowercased)
    case "equals": return actualLowercased == valueLowercased
    case "not_equals": return actualLowercased != valueLowercased
    case "matches": return actual.range(of: value.string, options: [.regularExpression, .caseInsensitive]) != nil
    case "is_empty": return actual.isEmpty
    case "is_not_empty": return !actual.isEmpty
    default: return true
    }
  }

  private static func compareEnum(_ actual: String, _ operatorId: String, _ value: RuleValue) -> Bool {
    switch operatorId {
    case "is": return actual == value.string
    case "is_not": return actual != value.string
    case "is_any_of": return value.stringArray.contains(actual)
    case "is_none_of": return !value.stringArray.contains(actual)
    case "is_empty": return actual.isEmpty
    case "is_set": return !actual.isEmpty
    default: return true
    }
  }

  private static func compareCalendar(_ actual: CalendarRef, _ operatorId: String, _ value: RuleValue) -> Bool {
    let values = Set(value.stringArray)
    let matchesSingle = actual.id == value.string || actual.googleId == value.string
    let matchesAny = values.contains(actual.id) || values.contains(actual.googleId)
    switch operatorId {
    case "is": return matchesSingle
    case "is_not": return !matchesSingle
    case "is_any_of": return matchesAny
    case "is_none_of": return !matchesAny
    default: return true
    }
  }

  private static func compareBool(_ actual: Bool, _ operatorId: String) -> Bool {
    switch operatorId {
    case "is_true": return actual
    case "is_false": return !actual
    default: return true
    }
  }

  private static func compareNumber(_ actual: Double, _ operatorId: String, _ value: RuleValue) -> Bool {
    switch operatorId {
    case "lte": return actual <= value.number
    case "lt": return actual < value.number
    case "gte": return actual >= value.number
    case "gt": return actual > value.number
    case "eq": return actual == value.number
    case "neq": return actual != value.number
    case "between", "not_between":
      return compareRange(actual, operatorId, value)
    default: return true
    }
  }

  private static func compareRange(_ actual: Double, _ operatorId: String, _ value: RuleValue) -> Bool {
    let bounds = value.numberArray
    guard bounds.count == 2 else { return true }
    let isInside = actual >= bounds[0] && actual <= bounds[1]
    return operatorId == "between" ? isInside : !isInside
  }
}
