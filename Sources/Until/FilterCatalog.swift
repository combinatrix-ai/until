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
    FilterField(id: "title", label: "Title", operators: stringOperators()),
    FilterField(id: "description", label: "Description", operators: stringOperators()),
    FilterField(id: "location", label: "Location", operators: stringOperators()),
    FilterField(id: "organizer", label: "Organizer email", operators: stringOperators()),
    FilterField(id: "calendar", label: "Calendar", operators: [
      FilterOperator(id: "is", label: "is", value: .calendars),
      FilterOperator(id: "is_not", label: "is not", value: .calendars),
      FilterOperator(id: "is_any_of", label: "is any of", value: .multiCalendars),
      FilterOperator(id: "is_none_of", label: "is none of", value: .multiCalendars)
    ]),
    FilterField(id: "selfResponse", label: "My response", operators: enumOperators([
      FilterChoice(value: "accepted", label: "Accepted"),
      FilterChoice(value: "declined", label: "Declined"),
      FilterChoice(value: "tentative", label: "Tentative"),
      FilterChoice(value: "needsAction", label: "Needs action"),
      FilterChoice(value: "none", label: "No response / not invited")
    ])),
    FilterField(id: "status", label: "Status", operators: enumOperators([
      FilterChoice(value: "confirmed", label: "Confirmed"),
      FilterChoice(value: "tentative", label: "Tentative"),
      FilterChoice(value: "cancelled", label: "Cancelled")
    ])),
    FilterField(id: "transparency", label: "Shows as", operators: enumOperators([
      FilterChoice(value: "busy", label: "Busy"),
      FilterChoice(value: "free", label: "Free")
    ])),
    FilterField(id: "allDay", label: "All-day", operators: booleanOperators()),
    FilterField(id: "isRecurring", label: "Recurring", operators: booleanOperators()),
    FilterField(id: "hasVideo", label: "Has video call", operators: booleanOperators()),
    FilterField(id: "attendeeCount", label: "Attendee count", operators: numberOperators(unit: nil)),
    FilterField(id: "durationMinutes", label: "Duration", operators: numberOperators(unit: "min")),
    FilterField(id: "startsWithin", label: "Starts within", operators: [
      FilterOperator(id: "within", label: "within", value: .number(unit: "min"))
    ]),
    FilterField(id: "hour", label: "Starts at hour", operators: numberOperators(unit: "h")),
    FilterField(id: "weekday", label: "Weekday", operators: numericEnumOperators([
      FilterChoice(value: "0", label: "Sunday"),
      FilterChoice(value: "1", label: "Monday"),
      FilterChoice(value: "2", label: "Tuesday"),
      FilterChoice(value: "3", label: "Wednesday"),
      FilterChoice(value: "4", label: "Thursday"),
      FilterChoice(value: "5", label: "Friday"),
      FilterChoice(value: "6", label: "Saturday")
    ])),
    FilterField(id: "attendee", label: "Attendee email", operators: [
      FilterOperator(id: "includes", label: "includes", value: .text),
      FilterOperator(id: "excludes", label: "excludes", value: .text)
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
      FilterOperator(id: "contains", label: "contains", value: .text),
      FilterOperator(id: "not_contains", label: "does not contain", value: .text),
      FilterOperator(id: "starts_with", label: "starts with", value: .text),
      FilterOperator(id: "ends_with", label: "ends with", value: .text),
      FilterOperator(id: "equals", label: "is exactly", value: .text),
      FilterOperator(id: "not_equals", label: "is not exactly", value: .text),
      FilterOperator(id: "matches", label: "matches regex", value: .text),
      FilterOperator(id: "is_empty", label: "is empty", value: .none),
      FilterOperator(id: "is_not_empty", label: "is not empty", value: .none)
    ]
  }

  private static func numberOperators(unit: String?) -> [FilterOperator] {
    [
      FilterOperator(id: "lte", label: "<=", value: .number(unit: unit)),
      FilterOperator(id: "lt", label: "<", value: .number(unit: unit)),
      FilterOperator(id: "gte", label: ">=", value: .number(unit: unit)),
      FilterOperator(id: "gt", label: ">", value: .number(unit: unit)),
      FilterOperator(id: "eq", label: "=", value: .number(unit: unit)),
      FilterOperator(id: "neq", label: "!=", value: .number(unit: unit)),
      FilterOperator(id: "between", label: "between", value: .numberRange(unit: unit)),
      FilterOperator(id: "not_between", label: "not between", value: .numberRange(unit: unit))
    ]
  }

  private static func enumOperators(_ choices: [FilterChoice]) -> [FilterOperator] {
    [
      FilterOperator(id: "is", label: "is", value: .select(choices)),
      FilterOperator(id: "is_not", label: "is not", value: .select(choices)),
      FilterOperator(id: "is_any_of", label: "is any of", value: .multiSelect(choices)),
      FilterOperator(id: "is_none_of", label: "is none of", value: .multiSelect(choices)),
      FilterOperator(id: "is_empty", label: "is empty", value: .none),
      FilterOperator(id: "is_set", label: "is set", value: .none)
    ]
  }

  private static func numericEnumOperators(_ choices: [FilterChoice]) -> [FilterOperator] {
    [
      FilterOperator(id: "is", label: "is", value: .select(choices)),
      FilterOperator(id: "is_not", label: "is not", value: .select(choices)),
      FilterOperator(id: "is_any_of", label: "is any of", value: .multiSelect(choices)),
      FilterOperator(id: "is_none_of", label: "is none of", value: .multiSelect(choices))
    ]
  }

  private static func booleanOperators() -> [FilterOperator] {
    [
      FilterOperator(id: "is_true", label: "is true", value: .none),
      FilterOperator(id: "is_false", label: "is false", value: .none)
    ]
  }
}
