import Foundation

/// A correction-oriented validation failure for a structured filter rule.
///
/// Rules are persisted as data, so validation deliberately checks the encoded
/// shape instead of relying on the query builder having produced the value.
/// The evaluator and settings save path both use `RuleValidator.validate(_:)`
/// as their single source of truth.
enum RuleValidationError: Equatable {
  case malformedGroup
  case malformedCondition
  case unknownField
  case unknownOperator
  case missingValue
  case wrongValueType
  case invalidChoice
  case nonFiniteNumber
  case invalidNumberRange
  case invalidRegex

  var message: String {
    switch self {
    case .malformedGroup:
      return loc("Fix this filter group: choose a group mode and keep only nested rules.")
    case .malformedCondition:
      return loc("Fix this filter rule: choose a field, operator, and matching value.")
    case .unknownField:
      return loc("Choose a field from the list for this filter rule.")
    case .unknownOperator:
      return loc("Choose an operator supported by the selected field.")
    case .missingValue:
      return loc("Enter a value for this filter rule.")
    case .wrongValueType:
      return loc("Use the value type shown for this operator.")
    case .invalidChoice:
      return loc("Choose a value from the list.")
    case .nonFiniteNumber:
      return loc("Enter a finite number.")
    case .invalidNumberRange:
      return loc("Enter two finite numbers with Min no greater than Max.")
    case .invalidRegex:
      return loc("Enter a valid regular expression.")
    }
  }
}

/// Canonical recursive validator for the structured filter language.
enum RuleValidator {
  static func validate(_ rule: Rule) -> RuleValidationError? {
    validateNode(rule)
  }

  static func isValid(_ rule: Rule) -> Bool {
    validate(rule) == nil
  }

  private static func validateNode(_ rule: Rule) -> RuleValidationError? {
    switch rule.kind {
    case .group:
      return validateGroup(rule)
    case .cond:
      return validateCondition(rule)
    }
  }

  private static func validateGroup(_ rule: Rule) -> RuleValidationError? {
    // Group metadata must not be mixed with condition metadata. Empty groups
    // are valid and intentionally match every event, as the query builder
    // communicates to the user.
    guard rule.groupOperator != nil,
          let children = rule.children,
          rule.field == nil,
          rule.operatorId == nil,
          rule.value == nil else {
      return .malformedGroup
    }
    for child in children {
      if let error = validateNode(child) { return error }
    }
    return nil
  }

  private static func validateCondition(_ rule: Rule) -> RuleValidationError? {
    // A condition is a leaf. In particular, accepting a condition with
    // children would let malformed persisted data bypass the catalog shape.
    guard rule.groupOperator == nil, rule.children == nil else {
      return .malformedCondition
    }
    guard let fieldId = rule.field,
          let field = FilterCatalog.fields.first(where: { $0.id == fieldId }) else {
      return .unknownField
    }
    guard let operatorId = rule.operatorId,
          let filterOperator = field.operators.first(where: { $0.id == operatorId }) else {
      return .unknownOperator
    }
    guard let value = rule.value else { return .missingValue }
    return validateValue(value, kind: filterOperator.value, operatorId: operatorId)
  }

  private static func validateValue(
    _ value: RuleValue,
    kind: ValueInputKind,
    operatorId: String
  ) -> RuleValidationError? {
    switch kind {
    case .none:
      return validateNone(value)
    case .text:
      return validateText(value, operatorId: operatorId)
    case .number:
      return validateNumber(value)
    case .numberRange:
      return validateNumberRange(value)
    case .select(let choices):
      return validateSelection(value, choices: choices)
    case .multiSelect(let choices):
      return validateMultiSelection(value, choices: choices)
    case .calendars:
      return validateCalendar(value)
    case .multiCalendars:
      guard case .strings = value else { return .wrongValueType }
      return nil
    }
  }

  private static func validateNone(_ value: RuleValue) -> RuleValidationError? {
    guard case .null = value else { return .wrongValueType }
    return nil
  }

  private static func validateText(_ value: RuleValue, operatorId: String) -> RuleValidationError? {
    guard case .string(let string) = value else { return .wrongValueType }
    guard operatorId == "matches" else { return nil }
    // An empty pattern is a valid regex that matches every string. Some
    // Foundation releases reject it during NSRegularExpression creation, so
    // preserve the language's valid empty-text default explicitly.
    if string.isEmpty { return nil }
    do {
      _ = try NSRegularExpression(pattern: string)
      return nil
    } catch {
      return .invalidRegex
    }
  }

  private static func validateNumber(_ value: RuleValue) -> RuleValidationError? {
    guard case .number(let number) = value else { return .wrongValueType }
    return number.isFinite ? nil : .nonFiniteNumber
  }

  private static func validateNumberRange(_ value: RuleValue) -> RuleValidationError? {
    guard case .numbers(let numbers) = value else { return .wrongValueType }
    guard numbers.count == 2,
          numbers.allSatisfy(\.isFinite),
          numbers[0] <= numbers[1] else {
      return .invalidNumberRange
    }
    return nil
  }

  private static func validateSelection(
    _ value: RuleValue,
    choices: [FilterChoice]
  ) -> RuleValidationError? {
    guard case .string(let selected) = value else { return .wrongValueType }
    return choices.contains(where: { $0.value == selected }) ? nil : .invalidChoice
  }

  private static func validateMultiSelection(
    _ value: RuleValue,
    choices: [FilterChoice]
  ) -> RuleValidationError? {
    guard case .strings(let selected) = value else { return .wrongValueType }
    let allowedValues = Set(choices.map(\.value))
    return selected.allSatisfy(allowedValues.contains) ? nil : .invalidChoice
  }

  private static func validateCalendar(_ value: RuleValue) -> RuleValidationError? {
    // Calendar ids come from the Google API and are not statically known to
    // the catalog. An empty string is the query builder's "choose" state,
    // not a persistable calendar selection.
    guard case .string(let calendarId) = value, !calendarId.isEmpty else {
      return .invalidChoice
    }
    return nil
  }
}
