import Combine
import CoreLocation
import SwiftUI
import UserNotifications

private func libraryDidChange(
    _ center: CFNotificationCenter?, _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?, _ object: UnsafeRawPointer?, _ userInfo: CFDictionary?
) {
    Task { @MainActor in
        await PasteboardMonitor.shared.reloadSettings()
        NotificationCenter.default.post(name: .clipLibraryChanged, object: nil)
    }
}

/// The private hook is isolated here; persistence and integrations use public APIs.
@MainActor @Observable
final class PasteboardMonitor: NSObject, @preconcurrency CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    static let shared = PasteboardMonitor()
    var status = "Starting clipboard listener…"
    var backgroundStatus = "Background monitoring is off"
    var notificationStatus = "Notifications have not been enabled"
    var lastError: String?
    private var settings = ClipSettings()
    private var started = false
    private var subscriptions: Set<AnyCancellable> = []
    private var polling: Task<Void, Never>?
    private var lastAttemptedToken: String?
    private var captureCount = 0
    private var pendingChange = false
    private var pendingBackgroundSignal = false
    private var lastBackgroundSignal = Date.distantPast
    private var pendingNotificationSave = false
    private var notificationToken: String?
    private var location: CLLocationManager?
    private var backgroundSession: CLBackgroundActivitySession?
    private var serviceSession: CLServiceSession?
    private var privateListenerAvailable = false
    private var editingCount = 0

    func beginEditing() { editingCount += 1 }
    func endEditing() {
        editingCount = max(0, editingCount - 1)
        if editingCount == 0 { Task { await changed() } }
    }

    func start() async {
        guard !started else {
            await reloadSettings()
            return
        }
        started = true
        ClipityNotifications.register()
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)
            .sink { @Sendable _ in Task { @MainActor in await Self.shared.changed() } }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { @Sendable _ in Task { @MainActor in await Self.shared.becameActive() } }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .sink { @Sendable _ in Task { @MainActor in await Self.shared.becameActive() } }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Notification.Name("com.apple.pasteboard.changed"))
            .sink { @Sendable _ in Task { @MainActor in await Self.shared.changed(backgroundSignal: true) } }.store(
                in: &subscriptions)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil, libraryDidChange,
            LibraryEvents.darwinName as CFString, nil, .deliverImmediately)
        // Public foreground notification delivery can be coalesced. A lightweight
        // counter check catches missed changes without repeatedly reading contents.
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.changed()
            }
        }
        await reloadSettings()
        await changed()
    }

    func reloadSettings() async {
        do {
            settings = try await ClipStore.shared.snapshot().settings
            if !settings.captureNotifications { ClipityNotifications.clearPending() }
            configureBackground()
            status = settings.automaticCapture ? "Listening for clipboard changes" : "Automatic capture is paused"
            await refreshNotificationStatus()
        } catch {
            lastError = error.localizedDescription
            status = "Library unavailable — unlock and reopen Clipity"
        }
    }

    func requestNotifications() async {
        do {
            _ = try await ClipityNotifications.requestPermission()
            await refreshNotificationStatus()
        } catch { lastError = error.localizedDescription }
    }

    private func refreshNotificationStatus() async {
        let authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch authorization {
        case .authorized, .provisional, .ephemeral: notificationStatus = "Notifications enabled"
        case .denied: notificationStatus = "Notifications disabled in iOS Settings"
        case .notDetermined: notificationStatus = "Tap Enable Notifications to allow alerts"
        @unknown default: notificationStatus = "Notification permission unavailable"
        }
    }

    func becameActive() async {
        await reloadSettings()
        // Retry a previously inaccessible clipboard after permission/unlock changes.
        lastAttemptedToken = nil
        if pendingNotificationSave {
            pendingNotificationSave = false
            do { _ = try await capture(expectedToken: notificationToken) } catch {
                lastError = error.localizedDescription
            }
            notificationToken = nil
        } else {
            await changed()
        }
    }

    private func changed(backgroundSignal: Bool = false) async {
        guard settings.automaticCapture else { return }
        let background = UIApplication.shared.applicationState == .background
        guard !background || (settings.backgroundMonitoring && backgroundSession != nil) else { return }
        // A paste-permission alert can steal keyboard focus and drop keystrokes.
        // Defer foreground reads until the editor closes; background listening
        // continues if the user switches to another app with an editor open.
        guard background || editingCount == 0 else { return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            status = "Waiting for device unlock"
            return
        }
        let token = ClipboardCapture.currentToken
        if captureCount > 0 {
            pendingChange = true
            pendingBackgroundSignal = pendingBackgroundSignal || (backgroundSignal && background)
            return
        }
        if backgroundSignal && background {
            // Several OS notifications can describe one change. Do not flood alerts.
            guard Date().timeIntervalSince(lastBackgroundSignal) > 0.3 else { return }
            lastBackgroundSignal = Date()
        } else if ClipboardCapture.currentToken == lastAttemptedToken {
            return
        }
        // Resuming after a paste-permission alert must not re-read the same event.
        // In the background the counter may be stale, so only trust this shortcut
        // in the foreground; a private change signal still needs handling.
        if !background, let library = try? await ClipStore.shared.snapshot(),
            library.captureReceipts?.contains(where: { $0.token == token }) == true
        {
            lastAttemptedToken = token
            return
        }
        do {
            _ = try await capture(automatic: true)
        } catch {
            status = error.localizedDescription
            guard background, settings.automaticCapture, settings.captureNotifications,
                (error as? ClipError) != .sensitive, (error as? ClipError) != .unsupported
            else { return }
            do {
                // iOS can hide both the contents and the counter in the background.
                // The extension explicitly saves the CURRENT clipboard in that case.
                if try await ClipStore.shared.markPendingClipboardSignal(token: token) {
                    try await ClipityNotifications.pending(token: nil)
                    status = "Clipboard changed — expand the notification to save"
                }
            } catch { lastError = "Could not send clipboard notification: \(error.localizedDescription)" }
        }
    }

    @discardableResult
    func capture(
        automatic: Bool = false, expectedToken: String? = nil,
        title: String? = nil, folderID: UUID? = nil, keep: Bool = false
    ) async throws -> CaptureResult {
        guard UIApplication.shared.isProtectedDataAvailable else { throw ClipError.storage }
        // Manual actions can arrive while an automatic provider read is suspended.
        // They use the same durable receipt; don't silently drop the user's action.
        if automatic && captureCount > 0 {
            pendingChange = true
            return CaptureResult(clips: [], isNew: false, contentChanged: false)
        }
        captureCount += 1
        let token = ClipboardCapture.currentToken
        lastAttemptedToken = token
        defer {
            captureCount -= 1
            if captureCount == 0 && (pendingChange || ClipboardCapture.currentToken != token) {
                let backgroundSignal = pendingBackgroundSignal
                pendingChange = false
                pendingBackgroundSignal = false
                Task { await self.changed(backgroundSignal: backgroundSignal) }
            }
        }
        let result = try await ClipboardCapture.save(
            expectedToken: expectedToken, title: title, folderID: folderID, keep: keep, automatic: automatic)
        status = result.isNew ? "Saved to history" : "Clipboard already in history"
        ClipityNotifications.clearPending()
        if automatic && settings.captureNotifications && result.contentChanged {
            do { try await ClipityNotifications.saved(count: result.clips.count) } catch {
                lastError = "Clipping saved, but its notification failed: \(error.localizedDescription)"
            }
        }
        return result
    }

    private func configureBackground() {
        guard settings.automaticCapture && settings.backgroundMonitoring else {
            stopBackground()
            return
        }
        if location == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = CLLocationDistanceMax
            manager.pausesLocationUpdatesAutomatically = false
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            location = manager
        }
        guard let location else { return }
        switch location.authorizationStatus {
        case .denied, .restricted:
            stopBackground()
            backgroundStatus = "Location access denied — enable it in iOS Settings"
        case .notDetermined:
            backgroundStatus = "Waiting for location permission"
            if UIApplication.shared.applicationState == .active && serviceSession == nil {
                serviceSession = CLServiceSession(authorization: .always)
                location.requestAlwaysAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            if backgroundSession == nil {
                guard UIApplication.shared.applicationState == .active else {
                    backgroundStatus = "Open Clipity to resume background monitoring"
                    return
                }
                serviceSession = CLServiceSession(authorization: .always)
                backgroundSession = CLBackgroundActivitySession()
                location.startUpdatingLocation()
                privateListenerAvailable = PrivatePasteboardListener.begin()
            }
            backgroundStatus =
                privateListenerAvailable
                ? "Background listener running — iOS may require notification interaction to save"
                : "Private listener unavailable on this iOS version; checking the clipboard while running"
        @unknown default: backgroundStatus = "Location authorization unavailable"
        }
    }

    private func stopBackground() {
        location?.stopUpdatingLocation()
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
        backgroundStatus = "Background monitoring is off"
        ClipityNotifications.clearPending()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { configureBackground() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location is only used to sustain this user-enabled activity. Never retain coordinates.
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        backgroundStatus = "Background activity error: \(error.localizedDescription)"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Foreground captures already update the visible history/status. Keep the
        // confirmation in Notification Center without covering app controls.
        notification.request.content.categoryIdentifier == ClipityNotifications.category ? [.banner, .sound] : [.list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.categoryIdentifier == ClipityNotifications.category,
            response.actionIdentifier != UNNotificationDismissActionIdentifier
        else { return }
        let token = response.notification.request.content.userInfo[ClipityNotifications.tokenKey] as? String
        await queueNotificationSave(token: token)
    }

    private func queueNotificationSave(token: String?) async {
        notificationToken = token
        pendingNotificationSave = true
        if UIApplication.shared.applicationState == .active { await becameActive() }
    }
}

/// Original Clipity's private runtime hook, deliberately unobfuscated and availability checked.
/// This personal-use build does not assume the selector exists on every OS release.
@MainActor
private enum PrivatePasteboardListener {
    static func begin() -> Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            guard let connection = NSClassFromString("PBServerConnection") as? NSObject.Type else { return false }
            let selector = NSSelectorFromString("beginListeningToPasteboardChangeNotifications")
            guard connection.responds(to: selector) else { return false }
            _ = connection.perform(selector)
            return true
        #endif
    }
}

final class ClipAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register synchronously, before a cold-launch notification response arrives.
        ClipityNotifications.register()
        UNUserNotificationCenter.current().delegate = PasteboardMonitor.shared
        ClipQuickAction.register()
        Task { await PasteboardMonitor.shared.start() }
        return true
    }

    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ClipSceneDelegate.self
        return configuration
    }
}
