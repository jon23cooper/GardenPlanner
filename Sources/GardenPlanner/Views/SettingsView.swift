import SwiftUI

struct SettingsView: View {
    @Environment(AppData.self) private var appData

    private let monthNames = ["January","February","March","April","May","June","July","August","September","October","November","December"]

    var body: some View {
        @Bindable var data = appData
        Form {
            Section("Frost Dates") {
                Text("These dates are used to calculate sowing windows in the calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Last spring frost") {
                    HStack {
                        Picker("Month", selection: $data.lastFrostMonth) {
                            ForEach(1...12, id: \.self) { Text(monthNames[$0-1]).tag($0) }
                        }
                        .frame(width: 160)
                        Picker("Day", selection: $data.lastFrostDay) {
                            ForEach(1...31, id: \.self) { Text(String($0)).tag($0) }
                        }
                        .frame(width: 80)
                    }
                }

                LabeledContent("First autumn frost") {
                    HStack {
                        Picker("Month", selection: $data.firstFrostMonth) {
                            ForEach(1...12, id: \.self) { Text(monthNames[$0-1]).tag($0) }
                        }
                        .frame(width: 160)
                        Picker("Day", selection: $data.firstFrostDay) {
                            ForEach(1...31, id: \.self) { Text(String($0)).tag($0) }
                        }
                        .frame(width: 80)
                    }
                }
            }

            Section("Data") {
                LabeledContent("Data location") {
                    Text("~/Documents/GardenPlanner/Data/garden.json")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reveal in Finder") {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let dir = docs.appendingPathComponent("GardenPlanner/Data")
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(width: 500, height: 360)
    }
}
