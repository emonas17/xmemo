import Foundation

enum SchedulingTime {
    private static var calendar: Calendar {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "lt_LT")
        return cal
    }

    /// Ta pati valanda ir minutės kaip `timeAnchor`, ant n-tosios dienos nuo šiandien (skaičiuojant nuo šios paros pradžios).
    /// - Parameters:
    ///   - offsetDays: 1 = rytoj, 2 = poryt, 3 = užporyt
    ///   - timeAnchor: paprastai įrašymo pabaigos laikas
    ///   - today: pagal kurią „šiandien“ skaičiuojamos dienos (dažniausiai paspaudimo momentas)
    static func sameClockOnNthDayFromToday(
        offsetDays: Int,
        timeAnchor: Date,
        today: Date = Date()
    ) -> Date? {
        guard offsetDays >= 1 else { return nil }
        let cal = calendar
        let dayStart = cal.startOfDay(for: today)
        guard let targetDayStart = cal.date(byAdding: .day, value: offsetDays, to: dayStart) else { return nil }
        let hour = cal.component(.hour, from: timeAnchor)
        let minute = cal.component(.minute, from: timeAnchor)
        let second = cal.component(.second, from: timeAnchor)
        return cal.date(bySettingHour: hour, minute: minute, second: second, of: targetDayStart)
    }

    static func onNthDayFromToday(
        offsetDays: Int,
        hour: Int,
        minute: Int,
        today: Date = Date()
    ) -> Date? {
        guard offsetDays >= 1 else { return nil }
        let cal = calendar
        let dayStart = cal.startOfDay(for: today)
        guard let targetDayStart = cal.date(byAdding: .day, value: offsetDays, to: dayStart) else { return nil }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: targetDayStart)
    }
}
