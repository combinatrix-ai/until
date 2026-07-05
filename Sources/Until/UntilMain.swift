import AppKit

@main
struct UntilMain {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate(options: .fromProcess())
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }
}
