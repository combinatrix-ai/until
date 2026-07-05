import SwiftUI

struct QueryBuilderView: View {
  @Binding var rule: Rule
  var calendars: [CalendarSummary]

  var body: some View {
    RuleGroupView(rule: $rule, calendars: calendars, canDelete: false, onDelete: {})
  }
}

/// A lightweight single-selection dropdown built on `Menu` rather than `Picker`.
///
/// macOS `Picker` (menu style) eagerly materializes an `NSPopUpButton` with its
/// whole menu, and when many of them are nested in the query builder the layout
/// pass becomes pathologically slow (measured at multiple seconds). `Menu`
/// builds its items lazily on open, so the editor lays out near-instantly.
private struct MenuPicker: View {
  var options: [(value: String, label: String)]
  @Binding var selection: String
  var placeholder: String = ""
  var minWidth: CGFloat = 0

  private var currentLabel: String {
    options.first { $0.value == selection }?.label ?? placeholder
  }

  var body: some View {
    Menu {
      ForEach(options, id: \.value) { option in
        Button(option.label) { selection = option.value }
      }
    } label: {
      Text(currentLabel)
        .frame(minWidth: minWidth, alignment: .leading)
    }
    .menuStyle(.button)
    .fixedSize()
  }
}

private struct RuleGroupView: View {
  @Binding var rule: Rule
  var calendars: [CalendarSummary]
  var canDelete: Bool
  var onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(loc("Events where"))
          .foregroundStyle(.secondary)
        Spacer()
        if canDelete {
          Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
          }
          .help(loc("Remove group"))
        }
      }

      if children.isEmpty {
        HStack(alignment: .center, spacing: 8) {
          MenuPicker(
            options: [
              ("include_all", loc("All of")),
              ("include_any", loc("Any of")),
              ("exclude_all", loc("Not all of")),
              ("exclude_any", loc("None of"))
            ],
            selection: groupModeBinding,
            minWidth: 90
          )
          .frame(width: 112, alignment: .leading)

          ParenShape()
            .stroke(
              Color.secondary.opacity(0.45),
              style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 13)

          VStack(alignment: .leading, spacing: 8) {
            Text(loc("No rules yet — this group matches every event."))
              .font(.callout)
              .foregroundStyle(.secondary)
              .padding(.vertical, 4)
            addButtons
          }
        }
        .padding(.leading, 8)
      } else {
        HStack(alignment: .center, spacing: 8) {
          MenuPicker(
            options: [
              ("include_all", loc("All of")),
              ("include_any", loc("Any of")),
              ("exclude_all", loc("Not all of")),
              ("exclude_any", loc("None of"))
            ],
            selection: groupModeBinding,
            minWidth: 90
          )
          .frame(width: 112, alignment: .leading)

          ParenShape()
            .stroke(
              Color.secondary.opacity(0.45),
              style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 13)

          VStack(alignment: .leading, spacing: 8) {
            ForEach(children.indices, id: \.self) { index in
              RuleNodeView(
                rule: childBinding(index),
                calendars: calendars,
                onDelete: { removeChild(at: index) }
              )
            }
            addButtons
          }
        }
        .padding(.leading, 8)
      }
    }
    .card(padding: Theme.Spacing.md)
  }

  private var children: [Rule] {
    rule.children ?? []
  }

  private var groupModeBinding: Binding<String> {
    Binding(
      get: {
        let include = !(rule.negate ?? false)
        let groupOperator = rule.groupOperator ?? .and
        switch (include, groupOperator) {
        case (true, .and): return "include_all"
        case (true, .any): return "include_any"
        case (false, .and): return "exclude_all"
        case (false, .any): return "exclude_any"
        }
      },
      set: { value in
        switch value {
        case "include_any":
          rule.negate = false
          rule.groupOperator = .any
        case "exclude_all":
          rule.negate = true
          rule.groupOperator = .and
        case "exclude_any":
          rule.negate = true
          rule.groupOperator = .any
        default:
          rule.negate = false
          rule.groupOperator = .and
        }
      }
    )
  }

  private var addButtons: some View {
    HStack(spacing: 8) {
      Button {
        addCondition()
      } label: {
        Label(loc("Add rule"), systemImage: "plus")
      }
      Button {
        addGroup()
      } label: {
        Label(loc("Add group"), systemImage: "folder.badge.plus")
      }
    }
  }

  private func childBinding(_ index: Int) -> Binding<Rule> {
    Binding(
      get: { children[index] },
      set: { newValue in
        var next = children
        guard next.indices.contains(index) else { return }
        next[index] = newValue
        rule.children = next
      }
    )
  }

  private func addCondition() {
    var next = children
    next.append(FilterCatalog.defaultRule())
    rule.kind = .group
    rule.children = next
    if rule.groupOperator == nil { rule.groupOperator = .and }
  }

  private func addGroup() {
    var next = children
    next.append(.group(.and, [FilterCatalog.defaultRule()]))
    rule.kind = .group
    rule.children = next
    if rule.groupOperator == nil { rule.groupOperator = .and }
  }

  private func removeChild(at index: Int) {
    var next = children
    guard next.indices.contains(index) else { return }
    next.remove(at: index)
    rule.children = next
  }
}

private struct ParenShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let rightX = rect.maxX
    let left = rect.minX
    let top = rect.minY
    let bottom = rect.maxY

    path.move(to: CGPoint(x: rightX, y: top))
    path.addCurve(
      to: CGPoint(x: rightX, y: bottom),
      control1: CGPoint(x: left, y: top),
      control2: CGPoint(x: left, y: bottom)
    )
    return path
  }
}

private struct RuleNodeView: View {
  @Binding var rule: Rule
  var calendars: [CalendarSummary]
  var onDelete: () -> Void

  var body: some View {
    switch rule.kind {
    case .group:
      RuleGroupView(rule: $rule, calendars: calendars, canDelete: true, onDelete: onDelete)
    case .cond:
      ConditionRuleView(rule: $rule, calendars: calendars, onDelete: onDelete)
    }
  }
}

private struct ConditionRuleView: View {
  @Binding var rule: Rule
  var calendars: [CalendarSummary]
  var onDelete: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      MenuPicker(
        options: FilterCatalog.fields.map { ($0.id, $0.label) },
        selection: fieldBinding,
        minWidth: 130
      )

      MenuPicker(
        options: currentField.operators.map { ($0.id, $0.label) },
        selection: operatorBinding,
        minWidth: 115
      )

      ValueEditor(value: valueBinding, kind: currentOperator.value, calendars: calendars)
        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

      Button(role: .destructive, action: onDelete) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help(loc("Remove rule"))
    }
    .card(.inset, padding: Theme.Spacing.sm)
  }

  private var currentField: FilterField {
    FilterCatalog.field(rule.field)
  }

  private var currentOperator: FilterOperator {
    FilterCatalog.operatorFor(field: rule.field, operator: rule.operatorId)
  }

  private var fieldBinding: Binding<String> {
    Binding(
      get: { currentField.id },
      set: { fieldId in
        let field = FilterCatalog.field(fieldId)
        let filterOperator = field.operators[0]
        rule.kind = .cond
        rule.field = field.id
        rule.operatorId = filterOperator.id
        rule.value = FilterCatalog.defaultValue(for: filterOperator.value)
      }
    )
  }

  private var operatorBinding: Binding<String> {
    Binding(
      get: { currentOperator.id },
      set: { operatorId in
        let filterOperator = currentField.operators.first { $0.id == operatorId } ?? currentField.operators[0]
        rule.operatorId = filterOperator.id
        rule.value = FilterCatalog.defaultValue(for: filterOperator.value)
      }
    )
  }

  private var valueBinding: Binding<RuleValue> {
    Binding(
      get: { rule.value ?? FilterCatalog.defaultValue(for: currentOperator.value) },
      set: { rule.value = $0 }
    )
  }
}

private struct ValueEditor: View {
  @Binding var value: RuleValue
  var kind: ValueInputKind
  var calendars: [CalendarSummary]

  var body: some View {
    switch kind {
    case .none:
      EmptyView()
    case .text:
      TextField(loc("Value"), text: stringBinding)
        .textFieldStyle(.roundedBorder)
    case .number(let unit):
      HStack(spacing: 6) {
        TextField("0", value: numberBinding, format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 84)
        if let unit {
          Text(unit)
            .foregroundStyle(.secondary)
        }
      }
    case .numberRange(let unit):
      HStack(spacing: 6) {
        TextField(loc("Min"), value: rangeBinding(0), format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 72)
        Text(loc("to"))
          .foregroundStyle(.secondary)
        TextField(loc("Max"), value: rangeBinding(1), format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 72)
        if let unit {
          Text(unit)
            .foregroundStyle(.secondary)
        }
      }
    case .select(let choices):
      MenuPicker(
        options: choices.map { ($0.value, $0.label) },
        selection: stringBinding
      )
    case .multiSelect(let choices):
      MultiChoiceMenu(title: loc("Select values"), choices: choices, selection: stringSetBinding)
    case .calendars:
      calendarPicker(multiple: false)
    case .multiCalendars:
      calendarPicker(multiple: true)
    }
  }

  private var stringBinding: Binding<String> {
    Binding(
      get: { value.string },
      set: { value = .string($0) }
    )
  }

  private var numberBinding: Binding<Double> {
    Binding(
      get: { value.number },
      set: { value = .number($0) }
    )
  }

  private func rangeBinding(_ index: Int) -> Binding<Double> {
    Binding(
      get: {
        let values = normalizedRange
        return values[index]
      },
      set: { newValue in
        var values = normalizedRange
        values[index] = newValue
        value = .numbers(values)
      }
    )
  }

  private var normalizedRange: [Double] {
    let values = value.numberArray
    if values.count >= 2 { return Array(values.prefix(2)) }
    if values.count == 1 { return [values[0], values[0]] }
    return [0, 0]
  }

  private var stringSetBinding: Binding<Set<String>> {
    Binding(
      get: { Set(value.stringArray) },
      set: { value = .strings(Array($0).sorted()) }
    )
  }

  @ViewBuilder
  private func calendarPicker(multiple: Bool) -> some View {
    if calendars.isEmpty {
      Text(loc("No calendars loaded"))
        .foregroundStyle(.secondary)
    } else if multiple {
      MultiChoiceMenu(
        title: loc("Select calendars"),
        choices: calendars.map { FilterChoice(value: $0.id, label: $0.name) },
        selection: stringSetBinding
      )
    } else {
      MenuPicker(
        options: [("", loc("Choose calendar"))] + calendars.map { ($0.id, $0.name) },
        selection: stringBinding,
        placeholder: loc("Choose calendar")
      )
    }
  }
}

private struct MultiChoiceMenu: View {
  var title: String
  var choices: [FilterChoice]
  @Binding var selection: Set<String>

  var body: some View {
    Menu(summary) {
      ForEach(choices) { choice in
        Toggle(choice.label, isOn: Binding(
          get: { selection.contains(choice.value) },
          set: { isOn in
            if isOn {
              selection.insert(choice.value)
            } else {
              selection.remove(choice.value)
            }
          }
        ))
      }
    }
  }

  private var summary: String {
    if selection.isEmpty { return title }
    if selection.count == 1,
       let selected = choices.first(where: { selection.contains($0.value) }) {
      return selected.label
    }
    return loc("%d selected", selection.count)
  }
}
