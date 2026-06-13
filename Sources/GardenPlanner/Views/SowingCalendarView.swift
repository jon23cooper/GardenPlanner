import SwiftUI

struct SowingCalendarView: View {
    @Environment(AppData.self) private var appData
    @State private var year = Calendar.current.component(.year, from: Date())

    private let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

    struct ResolvedSeed {
        let seed: Seed
        let windows: [(window: SowingWindow, start: Date, end: Date)]
    }

    var resolvedSeeds: [ResolvedSeed] {
        appData.seeds
            .map { ResolvedSeed(seed: $0, windows: appData.resolvedWindows(for: $0, year: year)) }
            .filter { !$0.windows.isEmpty }
            .sorted { $0.seed.displayName < $1.seed.displayName }
    }

    func weekStartDate(month: Int, week: Int) -> Date {
        let first = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
        return Calendar.current.date(byAdding: .day, value: (week - 1) * 7, to: first)!
    }

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
        let weekW: CGFloat = 16
        let gap: CGFloat = 1
        let monthGap: CGFloat = 5

        return VStack(alignment: .leading, spacing: 0) {
            // Month header
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

            ForEach(resolvedSeeds, id: \.seed.id) { rs in
                // One row per sowing window
                ForEach(rs.windows.indices, id: \.self) { i in
                    let rw = rs.windows[i]
                    HStack(spacing: 0) {
                        // Seed name only on first window row
                        if i == 0 {
                            Text(rs.seed.displayName)
                                .font(.callout).lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                        } else {
                            Spacer().frame(width: 120)
                        }
                        // Window label
                        Text(rw.window.label)
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)
                            .padding(.trailing, 10)

                        ForEach(1...12, id: \.self) { m in
                            HStack(spacing: gap) {
                                ForEach(1...4, id: \.self) { w in
                                    RangeWeekCell(
                                        weekStart: weekStartDate(month: m, week: w),
                                        weekEnd: weekEndDate(month: m, week: w),
                                        windowStart: rw.start,
                                        windowEnd: rw.end,
                                        colorHex: rw.window.colorHex,
                                        width: weekW
                                    )
                                }
                            }
                            if m < 12 { Spacer().frame(width: monthGap) }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if rs.seed.id != resolvedSeeds.last?.seed.id {
                    Divider().opacity(0.4).padding(.vertical, 2)
                }
            }
        }
    }
}

struct RangeWeekCell: View {
    let weekStart: Date
    let weekEnd: Date
    let windowStart: Date
    let windowEnd: Date
    let colorHex: String
    let width: CGFloat

    @State private var isHovered = false

    // Does this week slot overlap the sowing window?
    var overlap: Overlap {
        // No overlap
        if weekEnd <= windowStart || weekStart >= windowEnd { return .none }
        // Leading edge of window starts in this slot
        let startsHere = windowStart >= weekStart && windowStart < weekEnd
        // Trailing edge ends in this slot
        let endsHere = windowEnd > weekStart && windowEnd <= weekEnd
        if startsHere && endsHere { return .full }
        if startsHere { return .start }
        if endsHere { return .end }
        return .middle
    }

    enum Overlap { case none, start, middle, end, full }

    var tooltipText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: windowStart)) – \(fmt.string(from: windowEnd))"
    }

    var body: some View {
        let color = Color(hex: colorHex)
        let alpha: Double = isHovered ? 0.65 : 0.35

        ZStack {
            switch overlap {
            case .none:
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.05))
            case .full:
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(alpha))
            case .start:
                // Fill right half with flat edge on right
                HStack(spacing: 0) {
                    Spacer()
                    color.opacity(alpha)
                }
                .clipShape(
                    UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 0, topTrailingRadius: 0)
                )
            case .end:
                HStack(spacing: 0) {
                    color.opacity(alpha)
                    Spacer()
                }
                .clipShape(
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 3, topTrailingRadius: 3)
                )
            case .middle:
                color.opacity(alpha)
            }
        }
        .frame(width: width, height: 20)
        .help(overlap == .none ? "" : tooltipText)
        .onHover { isHovered = $0 && overlap != .none }
    }
}
