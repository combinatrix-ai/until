import Foundation

enum ValueInputKind {
  case none
  case text
  case number(unit: String?)
  case numberRange(unit: String?)
  case select([FilterChoice])
  case multiSelect([FilterChoice])
  case calendars
  case multiCalendars
}

struct FilterChoice: Identifiable, Hashable {
  var id: String { value }
  var value: String
  var label: String
}

struct FilterOperator: Identifiable {
  var id: String
  var label: String
  var value: ValueInputKind
}

struct FilterField: Identifiable {
  var id: String
  var label: String
  var operators: [FilterOperator]
}

enum FilterCatalog {
  static let fields: [FilterField] = [
    FilterField(id: "title", label: loc("Title"), operators: stringOperators()),
    FilterField(id: "description", label: loc("Description"), operators: stringOperators()),
    FilterField(id: "location", label: loc("Location"), operators: stringOperators()),
    FilterField(id: "organizer", label: loc("Organizer email"), operators: stringOperators()),
    FilterField(id: "calendar", label: loc("Calendar"), operators: [
      FilterOperator(id: "is", label: loc("is"), value: .calendars),
      FilterOperator(id: "is_not", label: loc("is not"), value: .calendars),
      FilterOperator(id: "is_any_of", label: loc("is any of"), value: .multiCalendars),
      FilterOperator(id: "is_none_of", label: loc("is none of"), value: .multiCalendars)
    ]),
    FilterField(id: "selfResponse", label: loc("My response"), operators: enumOperators([
      FilterChoice(value: "accepted", label: loc("Accepted")),
      FilterChoice(value: "declined", label: loc("Declined")),
      FilterChoice(value: "tentative", label: loc("Tentative")),
      FilterChoice(value: "needsAction", label: loc("Needs action")),
      FilterChoice(value: "none", label: loc("No response / not invited"))
    ])),
    FilterField(id: "status", label: loc("Status"), operators: enumOperators([
      FilterChoice(value: "confirmed", label: loc("Confirmed")),
      FilterChoice(value: "tentative", label: loc("Tentative")),
      FilterChoice(value: "cancelled", label: loc("Cancelled"))
    ])),
    FilterField(id: "transparency", label: loc("Shows as"), operators: enumOperators([
      FilterChoice(value: "busy", label: loc("Busy")),
      FilterChoice(value: "free", label: loc("Free"))
    ])),
    FilterField(id: "allDay", label: loc("All-day"), operators: booleanOperators()),
    FilterField(id: "isRecurring", label: loc("Recurring"), operators: booleanOperators()),
    FilterField(id: "hasVideo", label: loc("Has video call"), operators: booleanOperators()),
    FilterField(id: "attendeeCount", label: loc("Attendee count"), operators: numberOperators(unit: nil)),
    FilterField(id: "durationMinutes", label: loc("Duration"), operators: numberOperators(unit: loc("min"))),
    FilterField(id: "startsWithin", label: loc("Starts within"), operators: [
      FilterOperator(id: "within", label: loc("within"), value: .number(unit: loc("min")))
    ]),
    FilterField(id: "hour", label: loc("Starts at hour"), operators: numberOperators(unit: loc("h"))),
    FilterField(id: "weekday", label: loc("Weekday"), operators: numericEnumOperators([
      FilterChoice(value: "0", label: loc("Sunday")),
      FilterChoice(value: "1", label: loc("Monday")),
      FilterChoice(value: "2", label: loc("Tuesday")),
      FilterChoice(value: "3", label: loc("Wednesday")),
      FilterChoice(value: "4", label: loc("Thursday")),
      FilterChoice(value: "5", label: loc("Friday")),
      FilterChoice(value: "6", label: loc("Saturday"))
    ])),
    FilterField(id: "attendee", label: loc("Attendee email"), operators: [
      FilterOperator(id: "includes", label: loc("includes"), value: .text),
      FilterOperator(id: "excludes", label: loc("excludes"), value: .text)
    ])
  ]

  static func field(_ id: String?) -> FilterField {
    fields.first { $0.id == id } ?? fields[0]
  }

  static func operatorFor(field fieldId: String?, operator operatorId: String?) -> FilterOperator {
    let field = field(fieldId)
    return field.operators.first { $0.id == operatorId } ?? field.operators[0]
  }

  static func defaultRule() -> Rule {
    let field = fields[0]
    let filterOperator = field.operators[0]
    return .condition(field.id, filterOperator.id, defaultValue(for: filterOperator.value))
  }

  static func defaultValue(for kind: ValueInputKind) -> RuleValue {
    switch kind {
    case .none:
      return .null
    case .text:
      return .string("")
    case .number:
      return .number(0)
    case .numberRange:
      return .numbers([0, 60])
    case .select(let choices):
      return .string(choices.first?.value ?? "")
    case .multiSelect:
      return .strings([])
    case .calendars:
      return .string("")
    case .multiCalendars:
      return .strings([])
    }
  }

  private static func stringOperators() -> [FilterOperator] {
    [
      FilterOperator(id: "contains", label: loc("contains"), value: .text),
      FilterOperator(id: "not_contains", label: loc("does not contain"), value: .text),
      FilterOperator(id: "starts_with", label: loc("starts with"), value: .text),
      FilterOperator(id: "ends_with", label: loc("ends with"), value: .text),
      FilterOperator(id: "equals", label: loc("is exactly"), value: .text),
      FilterOperator(id: "not_equals", label: loc("is not exactly"), value: .text),
      FilterOperator(id: "matches", label: loc("matches regex"), value: .text),
      FilterOperator(id: "is_empty", label: loc("is empty"), value: .none),
      FilterOperator(id: "is_not_empty", label: loc("is not empty"), value: .none)
    ]
  }

  private static func numberOperators(unit: String?) -> [FilterOperator] {
    // Mathematical comparison symbols (<=, <, >=, >, =, !=) are universal and
    // left untranslated.
    [
      FilterOperator(id: "lte", label: "<=", value: .number(unit: unit)),
      FilterOperator(id: "lt", label: "<", value: .number(unit: unit)),
      FilterOperator(id: "gte", label: ">=", value: .number(unit: unit)),
      FilterOperator(id: "gt", label: ">", value: .number(unit: unit)),
      FilterOperator(id: "eq", label: "=", value: .number(unit: unit)),
      FilterOperator(id: "neq", label: "!=", value: .number(unit: unit)),
      FilterOperator(id: "between", label: loc("between"), value: .numberRange(unit: unit)),
      FilterOperator(id: "not_between", label: loc("not between"), value: .numberRange(unit: unit))
    ]
  }

  private static func enumOperators(_ choices: [FilterChoice]) -> [FilterOperator] {
    [
      FilterOperator(id: "is", label: loc("is"), value: .select(choices)),
      FilterOperator(id: "is_not", label: loc("is not"), value: .select(choices)),
      FilterOperator(id: "is_any_of", label: loc("is any of"), value: .multiSelect(choices)),
      FilterOperator(id: "is_none_of", label: loc("is none of"), value: .multiSelect(choices)),
      FilterOperator(id: "is_empty", label: loc("is empty"), value: .none),
      FilterOperator(id: "is_set", label: loc("is set"), value: .none)
    ]
  }

  private static func numericEnumOperators(_ choices: [FilterChoice]) -> [FilterOperator] {
    [
      FilterOperator(id: "is", label: loc("is"), value: .select(choices)),
      FilterOperator(id: "is_not", label: loc("is not"), value: .select(choices)),
      FilterOperator(id: "is_any_of", label: loc("is any of"), value: .multiSelect(choices)),
      FilterOperator(id: "is_none_of", label: loc("is none of"), value: .multiSelect(choices))
    ]
  }

  private static func booleanOperators() -> [FilterOperator] {
    [
      FilterOperator(id: "is_true", label: loc("is true"), value: .none),
      FilterOperator(id: "is_false", label: loc("is false"), value: .none)
    ]
  }
}
