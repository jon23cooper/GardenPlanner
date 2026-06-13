import SwiftUI

struct SowingCalendarView: View {
    @Environment(AppData.self) private var appData
    private let year = Calendar.current.component(.year, from: Date())
    @State private var nameColumnWidth: CGFloat = 160
    @State private var filterDate: Date? = nil
    @State private var showingDatePicker = false

    private let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

    let labelW: CGFloat = 80
    let monthGap: CGFloat = 4
    let innerGap: CGFloat = 1
    let rowH: CGFloat = 22
    let gridPadding: CGFloat = 16

    struct ResolvedSeed {
        let seed: Seed
        let windows: [(window: SowingWindow, start: Date, end: Date)]
    }

    var resolvedSeeds: [ResolvedSeed] {
        appData.seeds
            .map { ResolvedSeed(seed: $0, windows: appData.resolvedWindows(for: $0, year: year)) }
            .filter { rs in
                guard !rs.windows.isEmpty else { return false }
                guard let date = filterDate else { return true }
                return rs.windows.contains { _, start, end in date >= start && date <= end }
            }
            .sorted { $0.seed.displayName < $1.seed.displayName }
    }

    func weekStartDate(month: Int, week: Int) -> Date {
        let first = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
        return Calendar.current.date(byAdding: .day, value: (week - 1) * 7, to: first)!
    }

    func weekEndDate(month: Int, week: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: weekStartDate(month: month, week: week))!
    }

    func weekW(availableWidth: CGFloat) -> CGFloat {
        let fixed = nameColumnWidth + labelW + (11 * monthGap) + (12 * 3 * innerGap) + (gridPadding * 2)
        return max(10, (availableWidth - fixed) / 48)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    filterDate = Date()
                } label: {
                    Text("Today")
                }
                .buttonStyle(.bordered)

                Button {
                    showingDatePicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        if let date = filterDate {
                            Text(date, format: .dateTime.day().month())
                        } else {
                            Text("Filter by date")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingDatePicker, arrowEdge: .bottom) {
                    VStack(spacing: 12) {
                        DatePicker(
                            "Select date",
                            selection: Binding(
                                get: { filterDate ?? Date() },
                                set: { filterDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(width: 300)
                    }
                    .padding()
                }

                if filterDate != nil {
                    Button {
                        filterDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear date filter")
                }

                Spacer()

                if filterDate != nil {
                    Text("\(resolvedSeeds.count) seed\(resolvedSeeds.count == 1 ? "" : "s") sowable on this date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            if appData.seeds.isEmpty {
                ContentUnavailableView("No Seeds", systemImage: "leaf", description: Text("Add seeds to the catalogue to see your sowing calendar."))
            } else {
                GeometryReader { geo in
                    ScrollView(.vertical) {
                        calendarGrid(weekW: weekW(availableWidth: geo.size.width))
                            .padding(gridPadding)
                    }
                }

                Divider()
                Text("Drag the column edge to resize the plant name column")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, gridPadding)
                    .padding(.vertical, 6)
            }
        }
        .navigationTitle("Sowing Calendar")
    }

    func calendarGrid(weekW: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Month header
            HStack(spacing: 0) {
                // Resizable name column header with drag handle
                HStack(spacing: 0) {
                    Text("Plant")
                        .font(.caption).fontWeight(.semibold)
                        .frame(width: nameColumnWidth - 8, alignment: .leading)
                    // Drag handle
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 3, height: 16)
                        .cornerRadius(1.5)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    nameColumnWidth = max(80, nameColumnWidth + val.translation.width)
                                }
                        )
                        .cursor(.resizeLeftRight)
                        .padding(.trailing, 5)
                }
                .frame(width: nameColumnWidth)

                Text("Window")
                    .font(.caption).fontWeight(.semibold)
                    .frame(width: labelW, alignment: .leading)

                ForEach(1...12, id: \.self) { m in
                    Text(months[m - 1])
                        .font(.caption).fontWeight(.semibold)
                        .frame(width: weekW * 4 + innerGap * 3, alignment: .center)
                    if m < 12 { Spacer().frame(width: monthGap) }
                }
            }
            .padding(.bottom, 4)

            Divider()

            ForEach(resolvedSeeds, id: \.seed.id) { rs in
                ForEach(rs.windows.indices, id: \.self) { i in
                    let rw = rs.windows[i]
                    HStack(spacing: 0) {
                        if i == 0 {
                            Text(rs.seed.displayName)
                                .font(.callout).lineLimit(1)
                                .frame(width: nameColumnWidth, alignment: .leading)
                        } else {
                            Spacer().frame(width: nameColumnWidth)
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: rw.window.colorHex))
                                .frame(width: 7, height: 7)
                            Text(rw.window.label)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: labelW, alignment: .leading)

                        ForEach(1...12, id: \.self) { m in
                            HStack(spacing: innerGap) {
                                ForEach(1...4, id: \.self) { w in
                                    RangeWeekCell(
                                        weekStart: weekStartDate(month: m, week: w),
                                        weekEnd: weekEndDate(month: m, week: w),
                                        windowStart: rw.start,
                                        windowEnd: rw.end,
                                        colorHex: rw.window.colorHex,
                                        width: weekW,
                                        height: rowH
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

// MARK: -

struct RangeWeekCell: View {
    let weekStart: Date
    let weekEnd: Date
    let windowStart: Date
    let windowEnd: Date
    let colorHex: String
    let width: CGFloat
    let height: CGFloat
    var onHover: (String?) -> Void = { _ in }

    @State private var isHovered = false
    @State private var showTooltip = false
    @State private var tooltipTask: DispatchWorkItem?

    var overlap: Overlap {
        if weekEnd <= windowStart || weekStart >= windowEnd { return .none }
        let startsHere = windowStart >= weekStart && windowStart < weekEnd
        let endsHere   = windowEnd   >  weekStart && windowEnd   <= weekEnd
        if startsHere && endsHere { return .full }
        if startsHere { return .start }
        if endsHere   { return .end }
        return .middle
    }

    enum Overlap { case none, start, middle, end, full }

    var dateRangeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: windowStart)) – \(fmt.string(from: windowEnd))"
    }

    var body: some View {
        let color = Color(hex: colorHex)
        let alpha: Double = isHovered ? 0.7 : 0.35

        ZStack {
            switch overlap {
            case .none:
                RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.05))
            case .full:
                RoundedRectangle(cornerRadius: 3).fill(color.opacity(alpha))
            case .start:
                HStack(spacing: 0) {
                    Spacer()
                    color.opacity(alpha)
                }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 3, bottomLeadingRadius: 3,
                    bottomTrailingRadius: 0, topTrailingRadius: 0))
            case .end:
                HStack(spacing: 0) {
                    color.opacity(alpha)
                    Spacer()
                }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 3, topTrailingRadius: 3))
            case .middle:
                color.opacity(alpha)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showTooltip && overlap != .none {
                Text(dateRangeText)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 3)
                    .fixedSize()
                    .offset(y: -height - 4)
                    .zIndex(999)
                    .allowsHitTesting(false)
            }
        }
        .onHover { inside in
            isHovered = inside && overlap != .none
            tooltipTask?.cancel()
            if inside && overlap != .none {
                let task = DispatchWorkItem { showTooltip = true }
                tooltipTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
            } else {
                showTooltip = false
            }
        }
    }
}

// Cursor extension already defined in GardenBedPlannerView.swift — reuse NSCursor directly
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
