import SwiftUI
import Darwin

struct SettingsView: View {
    @Environment(AppData.self) private var appData
    @State private var copiedURL = false

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

            Section("Mobile Web Access") {
                Text("Serves a mobile-friendly page on your local network. Access it from your phone's browser via Tailscale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable web server", isOn: $data.webServerEnabled)

                if appData.webServerEnabled {
                    LabeledContent("Port") {
                        TextField("8080", value: $data.webServerPort, format: .number)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appData.webServerRunning ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(appData.webServerRunning ? "Running" : "Stopped")
                                .foregroundStyle(appData.webServerRunning ? .primary : .secondary)
                        }
                    }

                    if appData.webServerRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Access URLs — open one of these in your phone's browser:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(serverURLs(), id: \.self) { url in
                                HStack {
                                    Text(url)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.blue)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url, forType: .string)
                                        copiedURL = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedURL = false }
                                    } label: {
                                        Image(systemName: copiedURL ? "checkmark" : "doc.on.doc")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
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
        .frame(width: 540, height: 520)
    }

    func serverURLs() -> [String] {
        localIPAddresses().map { "http://\($0):\(appData.webServerPort)" }
    }

    func localIPAddresses() -> [String] {
        var results: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return results }
        defer { freeifaddrs(first) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            if ifa.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ifa.pointee.ifa_addr, socklen_t(ifa.pointee.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let addr = String(cString: hostname)
                if !addr.hasPrefix("127.") && !addr.hasPrefix("169.254.") {
                    // Prioritise Tailscale addresses (100.x.x.x range)
                    if addr.hasPrefix("100.") { results.insert(addr, at: 0) }
                    else { results.append(addr) }
                }
            }
            ptr = ifa.pointee.ifa_next
        }
        return results
    }
}
