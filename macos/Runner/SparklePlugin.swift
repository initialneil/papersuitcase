import Cocoa
import FlutterMacOS
import Sparkle

class SparklePlugin: NSObject, SPUUpdaterDelegate {
    private let channel: FlutterMethodChannel
    private var updaterController: SPUStandardUpdaterController?
    private var latestVersion: String?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        // Pass self as updaterDelegate so we get silent callbacks
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func start() {
        do {
            try updaterController?.updater.start()
        } catch {
            print("Sparkle updater failed to start: \(error)")
        }
    }

    // MARK: - MethodChannel Handler

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkForUpdates":
            updaterController?.checkForUpdates(nil)
            result(nil)
        case "getUpdateStatus":
            result([
                "available": latestVersion != nil,
                "version": latestVersion as Any
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        latestVersion = version
        channel.invokeMethod("onUpdateAvailable", arguments: ["version": version])
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        latestVersion = nil
        channel.invokeMethod("onNoUpdateAvailable", arguments: nil)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        channel.invokeMethod("onUpdateCheckError", arguments: ["error": error.localizedDescription])
    }
}
