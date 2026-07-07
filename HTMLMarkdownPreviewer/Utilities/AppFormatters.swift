import Foundation

enum AppFormatters {
    private static var appLocale: Locale {
        if let identifier = Bundle.main.preferredLocalizations.first {
            return Locale(identifier: identifier)
        }

        return .current
    }

    static func byteCount(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file).locale(appLocale))
    }

    static func relativeDate(_ date: Date, relativeTo referenceDate: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = appLocale
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
