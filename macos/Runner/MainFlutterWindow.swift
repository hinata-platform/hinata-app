import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Hinata: PDF-Anhänge zeigen ihre Formularfelder erst, wenn wir die
    // Annotationen vorher in die Seiten zeichnen (siehe HinataPdfChannel).
    HinataPdfChannel.register(with: flutterViewController.engine.binaryMessenger)

    // Hinata: whether a running timer keeps the app in the menu bar (HIN-101).
    let windowChannel = FlutterMethodChannel(
      name: "hinata/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "setKeepsRunning":
        AppDelegate.keepsRunningInMenuBar = (call.arguments as? Bool) ?? false
        result(nil)
      case "monospaceMenuBarDigits":
        // The menu bar clock in digits of one width, so the icons beside it
        // do not shift every second as 1:11 becomes 1:12.
        MainFlutterWindow.monospaceStatusItemDigits()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Hinata: native Splash-Animation über dem Flutter-View
    HinataSplashView.present(over: flutterViewController.view)

    super.awakeFromNib()
  }

  /// Gives this app's status item (tray_manager's, the only one it has) a font
  /// with tabular digits, at the menu bar's own size. The item lives in a
  /// status bar window of the app — found by AppKit's private class name, so
  /// a missing match is logged rather than silently ignored; its button keeps
  /// the font when the title changes.
  static func monospaceStatusItemDigits() {
    let font = NSFont.monospacedDigitSystemFont(
      ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    var found = false
    defer {
      if !found { NSLog("Hinata: no status bar button found for tabular digits") }
    }
    for window in NSApp.windows where window.className.contains("StatusBarWindow") {
      var views: [NSView] = window.contentView.map { [$0] } ?? []
      while let view = views.popLast() {
        if let button = view as? NSStatusBarButton {
          button.font = font
          found = true
        }
        views.append(contentsOf: view.subviews)
      }
    }
  }
}
