import SwiftUI

/// Shared design tokens. Every magic number for spacing, corner radius, and
/// surface color lives here so the popover and all settings tabs read as one
/// consistent visual language.
enum Theme {
  enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
  }

  enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
  }

  /// Hairline border used to separate a surface from its background.
  static let hairline = Color.primary.opacity(0.1)

  /// Soft backdrop behind a hovered borderless control (`IconButton`,
  /// `QuietButton`).
  static let hoverFill = Color.primary.opacity(0.07)

  /// One shared duration for hover-driven fades — control backdrops and the
  /// `revealOnHover` reveal — so every hover response moves at the same speed.
  static let hoverFadeDuration: Double = 0.12
}

/// The two nesting levels a card can have. `panel` is the outer container,
/// `inset` is a row or field sitting inside a panel.
enum Surface {
  case panel
  case inset

  var background: Color {
    switch self {
    case .panel: return Color(nsColor: .controlBackgroundColor)
    case .inset: return Color(nsColor: .textBackgroundColor)
    }
  }

  var radius: CGFloat {
    switch self {
    case .panel: return Theme.Radius.md
    case .inset: return Theme.Radius.sm
    }
  }
}

private struct CardModifier: ViewModifier {
  var surface: Surface
  var padding: CGFloat

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(surface.background, in: RoundedRectangle(cornerRadius: surface.radius))
      .overlay(
        RoundedRectangle(cornerRadius: surface.radius)
          .strokeBorder(Theme.hairline)
      )
  }
}

extension View {
  /// Wraps the view in a consistent card surface.
  func card(_ surface: Surface = .panel, padding: CGFloat = Theme.Spacing.lg) -> some View {
    modifier(CardModifier(surface: surface, padding: padding))
  }
}

/// A titled section header with an optional trailing accessory (button, etc.).
struct SectionHeader<Accessory: View>: View {
  var title: String
  var subtitle: String?
  @ViewBuilder var accessory: () -> Accessory

  init(_ title: String, subtitle: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
    self.title = title
    self.subtitle = subtitle
    self.accessory = accessory
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: Theme.Spacing.sm)
      accessory()
    }
  }
}

/// A flat settings group: a section header above stacked content, separated
/// from neighbors by whitespace alone — no card surface, border, or shadow.
/// Figure/ground comes from the sidebar layout and the bold header, so the
/// content area reads as one clean white plane.
struct SettingsCard<Accessory: View, Content: View>: View {
  var title: String
  var subtitle: String?
  @ViewBuilder var accessory: () -> Accessory
  @ViewBuilder var content: () -> Content

  init(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder accessory: @escaping () -> Accessory,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.accessory = accessory
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
      SectionHeader(title, subtitle: subtitle, accessory: accessory)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension SettingsCard where Accessory == EmptyView {
  init(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
  }
}

/// A single labeled settings row: title (with optional subtitle) on the left,
/// a control on the right.
struct SettingRow<Control: View>: View {
  var title: String
  var subtitle: String?
  @ViewBuilder var control: () -> Control

  init(_ title: String, subtitle: String? = nil, @ViewBuilder control: @escaping () -> Control) {
    self.title = title
    self.subtitle = subtitle
    self.control = control
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: Theme.Spacing.md)
      control()
    }
  }
}

/// Centered empty / placeholder state, optionally with a call-to-action.
struct EmptyStateView<Action: View>: View {
  var systemImage: String
  var title: String
  var detail: String?
  @ViewBuilder var action: () -> Action

  init(
    systemImage: String,
    title: String,
    detail: String? = nil,
    @ViewBuilder action: @escaping () -> Action
  ) {
    self.systemImage = systemImage
    self.title = title
    self.detail = detail
    self.action = action
  }

  var body: some View {
    VStack(spacing: Theme.Spacing.md) {
      Image(systemName: systemImage)
        .font(.system(size: 32))
        .foregroundStyle(.secondary)
      VStack(spacing: Theme.Spacing.xs) {
        Text(title)
          .font(.headline)
        if let detail {
          Text(detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
        }
      }
      action()
        .padding(.top, Theme.Spacing.xs)
    }
    .frame(maxWidth: .infinity)
    .padding(Theme.Spacing.xl)
  }
}

extension EmptyStateView where Action == EmptyView {
  init(systemImage: String, title: String, detail: String? = nil) {
    self.init(systemImage: systemImage, title: title, detail: detail, action: { EmptyView() })
  }
}

/// Inline error banner used across panels.
struct InlineErrorView: View {
  var message: String

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }
    .font(.callout)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Circular icon-only control shared by list rows, the NOW strip, and the
/// footer: a fixed 22×22pt hit area, monochrome `.secondary` at rest,
/// `Color.accentColor` over a soft circular backdrop on hover. Accent color
/// is something hover reveals now, not a resting state — the one deliberate
/// exception is the hero's loud `.borderedProminent` Join button, which isn't
/// built from this component. Callers attach `.help`/`.accessibilityLabel`/
/// `.disabled` the same way they would on a plain `Button`.
struct IconButton: View {
  var systemImage: String
  /// Swaps the symbol for a spinner without resizing the chrome around it —
  /// used while a note is being created or a Meet link is being added.
  var isBusy: Bool = false
  var action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .fill(isHovered ? Theme.hoverFill : Color.clear)
        if isBusy {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
        }
      }
      .frame(width: 22, height: 22)
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    // Non-text views default their baseline to the bottom edge, which would
    // hang the whole 22pt chrome from a `firstTextBaseline` row (NOW strip)
    // and float the glyph above the neighboring text. Expose the symbol's
    // approximate baseline instead: glyph center + half a 12pt symbol's cap
    // height, which optically centers the icon on adjacent text.
    .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 4.3 }
    .animation(.easeInOut(duration: Theme.hoverFadeDuration), value: isHovered)
    .onHover { isHovered = $0 }
  }
}

/// Borderless text+icon button for an action that shouldn't outrank a
/// screen's one loud `.borderedProminent` control: no chrome at rest, a soft
/// backdrop and full-strength label on hover. Sits in the hero's action row.
struct QuietButton: View {
  var systemImage: String
  var label: String
  var action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: Theme.Spacing.xs) {
        Image(systemName: systemImage)
        Text(label)
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(isHovered ? Color.primary : Color.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        isHovered ? Theme.hoverFill : Color.clear,
        in: RoundedRectangle(cornerRadius: Theme.Radius.sm)
      )
    }
    .buttonStyle(.borderless)
    .animation(.easeInOut(duration: Theme.hoverFadeDuration), value: isHovered)
    .onHover { isHovered = $0 }
  }
}

extension View {
  /// Fades a hover-revealed action in and out. Hidden means opacity 0 rather
  /// than removal, so the control keeps its footprint and neighbors don't
  /// shift when it appears.
  func revealOnHover(_ isVisible: Bool) -> some View {
    opacity(isVisible ? 1 : 0)
      .animation(.easeInOut(duration: Theme.hoverFadeDuration), value: isVisible)
  }
}

extension Color {
  init?(hex: String) {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6, let intValue = Int(value, radix: 16) else {
      return nil
    }
    let red = Double((intValue >> 16) & 0xff) / 255.0
    let green = Double((intValue >> 8) & 0xff) / 255.0
    let blue = Double(intValue & 0xff) / 255.0
    self.init(red: red, green: green, blue: blue)
  }
}
