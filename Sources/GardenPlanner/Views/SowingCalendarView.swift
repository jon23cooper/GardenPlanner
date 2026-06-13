import SwiftUI

struct SowingCalendarView: View {
    @Environment(AppData.self) private var appData
    @State private var year = Calendar.current.component(.year, from: Date())

    private let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

    struct SeedWindow {
        let seed: Seed
        let indoorDate: Date?
        let outdoorDate: Date?
        let transplantDate: Date?
    }

    var seedWindows: [SeedWindow] {
        appData.seeds.compactMap { seed in
            let indoorDate = appData.indoorSowDate(for: seed, year: year)
            let outdoorDate = appData.outdoorSowDate(for: seed, year: year)
            var transplantDate: Date?
            if let indoor = indoorDate {
                transplantDate = Calendar.current.date(byAdding: .weekOfYear, value: seed.transplantWeeksAfterIndoorSow, to: indoor)
            }
            guard indoorDate != nil || outdoorDate != nil else { return nil }
            return SeedWindow(seed: seed, indoorDate: indoorDate, outdoorDate: outdoorDate, transplantDate: transplantDate)
        }
        .sorted { $0.seed.displayName < $1.seed.displayName }
    }

    // Returns the start date of week `week` (1–4) within `month`
    func weekStartDate(month: Int, week: Int) -> Date {
        let firstOfMonth = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
        return Calendar.current.date(byAdding: .day, value: (week - 1) * 7, to: firstOfMonth)!
    }

    // Returns the end date (exclusive) of a week slot
    func weekEndDate(month: Int, week: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: weekStartDate(month: month, week: week))!
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                Text(String(year)).font(.title2).fontWeight(.semibold).frame(width: 60)
                Button { year += 1 } label: { Image(systemName: "chevron.right") }
                Spacer()
                HStack(spacing: 16) {
                    legend(color: .blue, label: "Sow indoors")
                    legend(color: .green, label: "Sow outdoors")
                    legend(color: .orange, label: "Transplant")
                }
                .font(.caption)
            }
            .padding()

            Divider()

            if appData.seeds.isEmpty {
                ContentUnavailableView("No Seeds", systemImage: "leaf", description: Text("Add seeds to the catalogue to see your sowing calendar."))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    calendarGrid
                        .padding()
                }
            }
        }
        .navigationTitle("Sowing Calendar")
    }

    var calendarGrid: some View {
        // Each month = 4 week columns; seed name column fixed at left
        let weekW: CGFloat = 18
        let gap: CGFloat = 1
        let monthGap: CGFloat = 6

        return VStack(alignment: .leading, spacing: 0) {
            // Month header row
            HStack(spacing: 0) {
                Spacer().frame(width: 170)
                ForEach(1...12, id: \.self) { m in
                    Text(months[m - 1])
                        .font(.caption).fontWeight(.semibold)
                        .frame(width: weekW * 4 + gap * 3, alignment: .center)
                    if m < 12 { Spacer().frame(width: monthGap) }
                }
            }
            .padding(.bottom, 3)

            Divider()

            // Seed rows
            ForEach(seedWindows, id: \.seed.id) { sw in
                HStack(spacing: 0) {
                    Text(sw.seed.displayName)
                        .font(.callout).lineLimit(1)
                        .frame(width: 160, alignment: .leading)
                        .padding(.trailing, 10)

                    ForEach(1...12, id: \.self) { m in
                        HStack(spacing: gap) {
                            ForEach(1...4, id: \.self) { w in
                                WeekCell(
                                    weekStart: weekStartDate(month: m, week: w),
                                    weekEnd: weekEndDate(month: m, week: w),
                                    indoorDate: sw.indoorDate,
                                    outdoorDate: sw.outdoorDate,
                                    transplantDate: sw.transplantDate,
                                    width: weekW
                                )
                            }
                        }
                        if m < 12 { Spacer().frame(width: monthGap) }
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.7))
                .frame(width: 16, height: 10)
            Text(label)
        }
    }
}

struct WeekCell: View {
    let weekStart: Date
    let weekEnd: Date
    let indoorDate: Date?
    let outdoorDate: Date?
    let transplantDate: Date?
    let width: CGFloat

    @State private var isHovered = false

    var matchedDate: Date? {
        if let d = indoorDate, d >= weekStart && d < weekEnd { return d }
        if let d = outdoorDate, d >= weekStart && d < weekEnd { return d }
        if let d = transplantDate, d >= weekStart && d < weekEnd { return d }
        return nil
    }

    var cellColor: Color? {
        if let d = indoorDate, d >= weekStart && d < weekEnd { return .blue }
        if let d = outdoorDate, d >= weekStart && d < weekEnd { return .green }
        if let d = transplantDate, d >= weekStart && d < weekEnd { return .orange }
        return nil
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(cellColor.map { $0.opacity(isHovered ? 0.55 : 0.30) } ?? Color.primary.opacity(0.05))
            .frame(width: width, height: 22)
            .help(matchedDate.map { helpText(date: $0) } ?? "")
            .onHover { isHovered = $0 }
    }

    func helpText(date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        let ds = fmt.string(from: date)
        if let _ = indoorDate, date == indoorDate { return "Sow indoors: \(ds)" }
        if let _ = outdoorDate, date == outdoorDate { return "Sow outdoors: \(ds)" }
        return "Transplant: \(ds)"
    }
}
