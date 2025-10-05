import Foundation
#if os(macOS)
import UserNotifications
import AppKit
import EventKit
#else
import UIKit
#endif

public class NotificationService {
    public static let shared = NotificationService()
    private let config = AppConfig.shared
    private let eventStore = EKEventStore()
    private var remindersList: EKCalendar?

    private init() {
        requestAuthorization()
    }

    // Request notification and reminders authorization
    private func requestAuthorization() {
        #if os(macOS)
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification authorization granted")
            } else if let error = error {
                print("Notification authorization error: \(error)")
            }
        }

        // Request reminders permissions with new API
        Task {
            do {
                let granted = try await eventStore.requestFullAccessToReminders()
                if granted {
                    print("Reminders authorization granted")
                    setupRemindersList()
                } else {
                    print("Reminders authorization denied")
                }
            } catch {
                print("Reminders authorization error: \(error)")
            }
        }
        #endif
    }

    // Setup reminders list
    private func setupRemindersList() {
        #if os(macOS)
        Task {
            // Get app name from bundle (either "Scan Organizer" or "Scan Organizer (Dev)")
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Scan Organizer"

            // Check for existing list
            let calendars = eventStore.calendars(for: .reminder)
            remindersList = calendars.first { $0.title == appName }

            // Create list if it doesn't exist
            if remindersList == nil {
                let newList = EKCalendar(for: .reminder, eventStore: eventStore)
                newList.title = appName
                newList.source = eventStore.defaultCalendarForNewReminders()?.source

                if newList.source != nil {
                    do {
                        try eventStore.saveCalendar(newList, commit: true)
                        remindersList = newList
                        print("Created '\(appName)' reminders list")
                    } catch {
                        print("Failed to create reminders list: \(error)")
                    }
                }
            }
        }
        #endif
    }

    // Send reminder for completed document
    public func sendCompletionReminder(for document: Document) {
        guard config.remindersEnabled else { return }

        #if os(macOS)
        // Create reminder in Reminders app with alarm
        Task {
            await createReminder(for: document)
        }

        // Also send immediate notification
        sendImmediateNotification(for: document)
        #endif
    }

    // Create reminder in macOS Reminders app
    private func createReminder(for document: Document) async {
        #if os(macOS)
        guard let remindersList = remindersList else {
            print("Reminders list not available")
            return
        }

        do {
            // Create reminder
            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = remindersList

            // Set title
            let fileName = document.processedPath?.lastPathComponent ?? document.originalPath.lastPathComponent
            reminder.title = "Prüfen: \(fileName)"

            // Build notes/body
            var bodyParts: [String] = []

            if document.documentType != .unknown {
                bodyParts.append("Typ: \(document.documentType.displayName)")
            } else if let aiType = document.aiType {
                bodyParts.append("Typ: \(aiType)")
            }

            if let vendor = document.vendor, !vendor.isEmpty {
                bodyParts.append("Firma: \(vendor)")
            }

            if document.confidence > 0 {
                bodyParts.append("Confidence: \(Int(document.confidence * 100))%")
            }

            if let amount = document.amount, amount > 0 {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = Locale(identifier: "de_DE")
                let doubleAmount = NSDecimalNumber(decimal: amount).doubleValue
                if let formattedAmount = formatter.string(from: NSNumber(value: doubleAmount)) {
                    bodyParts.append("Betrag: \(formattedAmount)")
                }
            }

            if let date = document.date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.locale = Locale(identifier: "de_DE")
                bodyParts.append("Datum: \(formatter.string(from: date))")
            }

            // Add file link
            if let processedPath = document.processedPath {
                bodyParts.append("Link: file://\(processedPath.path)")
            }

            bodyParts.append("→ Abhaken wenn korrekt!")
            reminder.notes = bodyParts.joined(separator: "\n")

            // Set priority (1 = high)
            reminder.priority = 1

            // Set alarm with configured delay in seconds
            let reminderDelaySeconds = Double(config.reminderDelaySeconds)
            let alarmDate = Date().addingTimeInterval(reminderDelaySeconds)
            let alarm = EKAlarm(absoluteDate: alarmDate)
            reminder.addAlarm(alarm)

            // Save reminder
            try eventStore.save(reminder, commit: true)
            print("Reminder created for: \(fileName) with alarm at: \(alarmDate)")

            // Open Reminders app briefly to ensure notification (like Python version)
            if let remindersURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                Task {
                    try? await NSWorkspace.shared.openApplication(at: remindersURL, configuration: NSWorkspace.OpenConfiguration())
                }
            }

        } catch {
            print("Failed to create reminder: \(error)")
        }
        #endif
    }

    // Send immediate notification
    private func sendImmediateNotification(for document: Document) {
        #if os(macOS)
        // Create notification content
        let content = UNMutableNotificationContent()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Scan Organizer"
        content.title = appName

        let fileName = document.processedPath?.lastPathComponent ?? document.originalPath.lastPathComponent
        content.subtitle = "PDF verarbeitet: \(fileName)"

        // Build body
        var bodyText = ""
        if document.documentType != .unknown {
            bodyText = document.documentType.displayName
        } else if let aiType = document.aiType {
            bodyText = aiType
        }

        if document.confidence > 0 {
            bodyText += " (\(Int(document.confidence * 100))%)"
        }

        bodyText += " - Erinnerung in \(config.reminderDelaySeconds) Sek."
        content.body = bodyText

        // Add sound if enabled
        if config.reminderSound {
            content.sound = .default
        }

        // Add category for actions
        content.categoryIdentifier = "PDF_COMPLETE"

        // Add file URL for quick access
        if let processedPath = document.processedPath {
            content.userInfo = ["fileURL": processedPath.absoluteString]
        }

        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        // Schedule notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }

        // Also show in-app notification if app is active
        if config.showNotificationBanner {
            showInAppNotification(for: document)
        }
        #endif
    }

    // Send error notification
    public func sendErrorNotification(fileName: String, error: String) {
        guard config.remindersEnabled else { return }

        #if os(macOS)
        let content = UNMutableNotificationContent()
        content.title = "PDF Processing Failed"
        content.subtitle = fileName
        content.body = error

        if config.reminderSound {
            content.sound = .defaultCritical
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        #endif
    }

    // Show in-app notification banner
    private func showInAppNotification(for document: Document) {
        #if os(macOS)
        DispatchQueue.main.async {
            // Post a notification that the UI can listen to
            NotificationCenter.default.post(
                name: .documentProcessingComplete,
                object: nil,
                userInfo: ["document": document]
            )
        }
        #endif
    }

    // Setup notification categories with actions
    public func setupNotificationCategories() {
        #if os(macOS)
        let showAction = UNNotificationAction(
            identifier: "SHOW_FILE",
            title: "Show in Finder",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )

        let category = UNNotificationCategory(
            identifier: "PDF_COMPLETE",
            actions: [showAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
        #endif
    }
}

// Notification extension
public extension Notification.Name {
    static let documentProcessingComplete = Notification.Name("documentProcessingComplete")
    static let documentProcessingFailed = Notification.Name("documentProcessingFailed")
}

// Handle notification actions
#if os(macOS)
public class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                      didReceive response: UNNotificationResponse,
                                      withCompletionHandler completionHandler: @escaping () -> Void) {

        switch response.actionIdentifier {
        case "SHOW_FILE":
            if let urlString = response.notification.request.content.userInfo["fileURL"] as? String,
               let url = URL(string: urlString) {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
        default:
            break
        }

        completionHandler()
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                      willPresent notification: UNNotification,
                                      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}
#endif