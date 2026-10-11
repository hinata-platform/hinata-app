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

    // Hinata: ob ein laufender Timer die App in der Menüleiste hält (HIN-101).
    let windowChannel = FlutterMethodChannel(
      name: "hinata/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { call, result in
      guard call.method == "setKeepsRunning" else {
        result(FlutterMethodNotImplemented)
        return
      }
      AppDelegate.keepsRunningInMenuBar = (call.arguments as? Bool) ?? false
      result(nil)
    }

    // Hinata: native Splash-Animation über dem Flutter-View
    HinataSplashView.present(over: flutterViewController.view)

    super.awakeFromNib()
  }
}
