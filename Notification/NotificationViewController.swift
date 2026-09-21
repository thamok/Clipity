import UIKit
import UserNotifications
import UserNotificationsUI

/// Expanding the notification gives this UI a chance to read the clipboard,
/// while keeping the main app closed.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var saveTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        preferredContentSize = CGSize(width: 320, height: 150)
    }

    func didReceive(_ notification: UNNotification) {
        loadViewIfNeeded()
        guard saveTask == nil else { return }
        statusLabel.text = "Saving the current clipboard…"
        spinner.startAnimating()
        let token = notification.request.content.userInfo[ClipityNotifications.tokenKey] as? String
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                spinner.stopAnimating()
                saveTask = nil
            }
            do {
                let result = try await ClipboardCapture.save(expectedToken: token)
                statusLabel.text =
                    result.isNew ? "Saved to Clipity history." : "This clipboard is already in Clipity history."
                // Keep the expanded result visible as confirmation. The main app
                // clears the delivered prompt when it next handles this clipboard.
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
                    ClipityNotifications.pendingID
                ])
            } catch {
                statusLabel.text = "\(error.localizedDescription) Open Clipity to try again."
            }
        }
    }
}
