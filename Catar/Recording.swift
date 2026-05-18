import Foundation

struct Recording: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let date: Date
    let duration: TimeInterval
    var customName: String?

    var displayName: String {
        if let n = customName, !n.isEmpty { return n }
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date)
    }

    var durationString: String {
        formatTime(duration)
    }

    func formatTime(_ t: TimeInterval) -> String {
        let m = Int(max(0, t)) / 60
        let s = Int(max(0, t)) % 60
        return String(format: "%d:%02d", m, s)
    }
}
