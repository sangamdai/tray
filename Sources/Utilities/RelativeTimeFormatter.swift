import Foundation

enum RelativeTimeFormatter {
    static func string(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 5 {
            return "now"
        } else if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 172800 {
            return "1d"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}
