import AppKit
import Carbon.HIToolbox

/// Registers one global hotkey via the Carbon HotKey API. This works on
/// modern macOS without Accessibility/Input-Monitoring permissions, unlike a
/// global `NSEvent` monitor. The Carbon event handler is a C function pointer,
/// so we route the callback through a stored closure keyed off the hotkey id.
/// Each manager owns one id, so the popover and join shortcuts can coexist.
@MainActor
final class HotkeyManager {
  /// Named modifier + key-code combinations offered in Settings. The raw string
  /// is what's persisted in `AppConfig.hotkeyPreset`.
  struct Preset: Identifiable, Hashable {
    var id: String
    var label: String
    var keyCode: UInt32
    var modifiers: UInt32
  }

  static let presets: [Preset] = [
    Preset(id: "ctrl-opt-u", label: "⌃⌥U",
           keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(controlKey | optionKey)),
    Preset(id: "ctrl-opt-space", label: "⌃⌥Space",
           keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
    Preset(id: "ctrl-opt-n", label: "⌃⌥N",
           keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey)),
    Preset(id: "ctrl-shift-space", label: "⌃⇧Space",
           keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey)),
    Preset(id: "ctrl-opt-j", label: "⌃⌥J",
           keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey)),
    Preset(id: "cmd-shift-j", label: "⌘⇧J",
           keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey)),
    Preset(id: "ctrl-opt-m", label: "⌃⌥M",
           keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))
  ]

  static func preset(for id: String) -> Preset {
    presets.first { $0.id == id } ?? presets[0]
  }

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var handler: (() -> Void)?
  private var currentPresetId: String?

  /// The Carbon hotkey signature shared by all of Until's hotkeys.
  nonisolated fileprivate static let signature: OSType = {
    // 'UNTL'
    let chars: [UInt8] = [0x55, 0x4E, 0x54, 0x4C]
    return chars.reduce(0) { ($0 << 8) | OSType($1) }
  }()
  nonisolated fileprivate let hotKeyID: UInt32

  init(id: UInt32 = 1, handler: @escaping () -> Void) {
    hotKeyID = id
    self.handler = handler
  }

  /// (Re)registers the hotkey for `presetId`. No-ops when the preset hasn't
  /// changed, so redundant config updates don't churn the registration.
  func register(presetId: String) {
    guard currentPresetId != presetId || hotKeyRef == nil else { return }
    unregister()
    let preset = Self.preset(for: presetId)

    installEventHandlerIfNeeded()

    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: Self.signature, id: self.hotKeyID)
    let status = RegisterEventHotKey(
      preset.keyCode,
      preset.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &ref
    )
    if status == noErr {
      hotKeyRef = ref
      currentPresetId = presetId
    }
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    currentPresetId = nil
  }

  private func installEventHandlerIfNeeded() {
    guard eventHandler == nil else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      hotkeyEventCallback,
      1,
      &eventType,
      selfPtr,
      &eventHandler
    )
  }

  fileprivate func fire() {
    handler?()
  }

  deinit {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }
    if let eventHandler {
      RemoveEventHandler(eventHandler)
    }
  }
}

/// C-compatible Carbon event callback. Recovers the `HotkeyManager` from
/// `userData` and hops to the main actor to run the stored handler. Every
/// manager's handler sees every Until hotkey, so one that isn't ours is passed
/// on to the next handler.
private func hotkeyEventCallback(
  _: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let userData else { return noErr }
  let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
  var pressed = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &pressed
  )
  guard status == noErr,
        pressed.signature == HotkeyManager.signature,
        pressed.id == manager.hotKeyID
  else { return OSStatus(eventNotHandledErr) }
  DispatchQueue.main.async {
    MainActor.assumeIsolated {
      manager.fire()
    }
  }
  return noErr
}
