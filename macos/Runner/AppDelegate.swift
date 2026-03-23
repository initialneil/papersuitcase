import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var sparklePlugin: SparklePlugin?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.papersuitecase/sparkle",
      binaryMessenger: controller.engine.binaryMessenger
    )
    sparklePlugin = SparklePlugin(channel: channel)
    channel.setMethodCallHandler(sparklePlugin!.handle)
    sparklePlugin!.start()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
