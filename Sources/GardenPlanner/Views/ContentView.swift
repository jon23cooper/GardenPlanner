import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case catalog = "Seed Catalogue"
    case calendar = "Sowing Calendar"
    case log = "Planting Log"
    case beds = "Garden Beds"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .catalog: return "leaf.fill"
        case .calendar: return "calendar"
        case .log: return "list.clipboard.fill"
        case .beds: return "square.grid.3x3.fill"
        }
    }
}

struct ContentView: View {
    @Environment(AppData.self) private var appData
    @State private var selection: AppSection? = .catalog

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .listStyle(.sidebar)
        } detail: {
            switch selection {
            case .catalog:
                SeedCatalogView()
            case .calendar:
                SowingCalendarView()
            case .log:
                PlantingLogView()
            case .beds:
                GardenBedPlannerView()
            case nil:
                Text("Select a section")
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: appData.pendingBedNavigation) { _, id in
            if id != nil { selection = .beds }
        }
    }
}
