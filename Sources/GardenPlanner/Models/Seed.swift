import Foundation

struct Seed: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var variety: String = ""
    var supplier: String = ""
    var quantityPackets: Int = 1

    var sowingWindows: [SowingWindow] = []

    var spacingCm: Double?
    var rowSpacingCm: Double?
    var depthCm: Double?
    var heightCm: Double?
    var daysToGermination: ClosedRange<Int>?
    var daysToHarvest: ClosedRange<Int>?

    var url: String = ""

    var companions: [String] = []
    var antagonists: [String] = []
    var sunRequirement: SunRequirement = .fullSun
    var notes: String = ""
    var tags: [String] = []

    var displayName: String {
        variety.isEmpty ? name : "\(name) (\(variety))"
    }

    var colorHex: String = "#4CAF50"
}

// MARK: - Sowing window model

struct SowingWindow: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String = "Outdoors"
    var colorHex: String = "#4CAF50"
    var start: SowDateSpec = SowDateSpec()
    var end: SowDateSpec = SowDateSpec(month: 4, day: 1)
}

struct SowDateSpec: Codable, Hashable {
    enum Kind: String, Codable { case fixed, frostRelative }
    var kind: Kind = .fixed
    var month: Int = 3          // used when kind == .fixed
    var day: Int = 1            // used when kind == .fixed
    var weeksFromFrost: Int = 0 // used when kind == .frostRelative (negative = before)
}

// MARK: - Other enums

enum SunRequirement: String, Codable, CaseIterable {
    case fullSun = "Full Sun"
    case partialShade = "Partial Shade"
    case fullShade = "Full Shade"
}

// MARK: - Custom coding (handles ClosedRange and legacy fields)

extension Seed {
    enum CodingKeys: String, CodingKey {
        case id, name, variety, supplier, quantityPackets
        case sowingWindows
        // Legacy keys — decoded only for migration
        case sowIndoorsWeeksBeforeFrost, sowOutdoorsWeeksFromFrost, transplantWeeksAfterIndoorSow
        case spacingCm, rowSpacingCm, depthCm, heightCm
        case daysToGerminationMin, daysToGerminationMax
        case daysToHarvestMin, daysToHarvestMax
        case url
        case companions, antagonists, sunRequirement, notes, tags, colorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        variety = try c.decodeIfPresent(String.self, forKey: .variety) ?? ""
        supplier = try c.decodeIfPresent(String.self, forKey: .supplier) ?? ""
        quantityPackets = try c.decodeIfPresent(Int.self, forKey: .quantityPackets) ?? 1
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#4CAF50"

        // New field
        var windows = try c.decodeIfPresent([SowingWindow].self, forKey: .sowingWindows) ?? []

        // Migrate legacy frost-relative fields into SowingWindows if no windows saved yet
        if windows.isEmpty {
            if let weeks = try c.decodeIfPresent(Int.self, forKey: .sowIndoorsWeeksBeforeFrost) {
                let transplant = try c.decodeIfPresent(Int.self, forKey: .transplantWeeksAfterIndoorSow) ?? 6
                windows.append(SowingWindow(
                    label: "Indoors",
                    colorHex: "#2196F3",
                    start: SowDateSpec(kind: .frostRelative, weeksFromFrost: -weeks),
                    end: SowDateSpec(kind: .frostRelative, weeksFromFrost: -weeks + transplant)
                ))
            }
            if let weeks = try c.decodeIfPresent(Int.self, forKey: .sowOutdoorsWeeksFromFrost) {
                windows.append(SowingWindow(
                    label: "Outdoors",
                    colorHex: "#4CAF50",
                    start: SowDateSpec(kind: .frostRelative, weeksFromFrost: weeks),
                    end: SowDateSpec(kind: .frostRelative, weeksFromFrost: weeks + 2)
                ))
            }
        }
        sowingWindows = windows

        spacingCm = try c.decodeIfPresent(Double.self, forKey: .spacingCm)
        rowSpacingCm = try c.decodeIfPresent(Double.self, forKey: .rowSpacingCm)
        depthCm = try c.decodeIfPresent(Double.self, forKey: .depthCm)
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm)
        if let lo = try c.decodeIfPresent(Int.self, forKey: .daysToGerminationMin),
           let hi = try c.decodeIfPresent(Int.self, forKey: .daysToGerminationMax) {
            daysToGermination = lo...hi
        }
        if let lo = try c.decodeIfPresent(Int.self, forKey: .daysToHarvestMin),
           let hi = try c.decodeIfPresent(Int.self, forKey: .daysToHarvestMax) {
            daysToHarvest = lo...hi
        }
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        companions = try c.decodeIfPresent([String].self, forKey: .companions) ?? []
        antagonists = try c.decodeIfPresent([String].self, forKey: .antagonists) ?? []
        sunRequirement = try c.decodeIfPresent(SunRequirement.self, forKey: .sunRequirement) ?? .fullSun
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(variety, forKey: .variety)
        try c.encode(supplier, forKey: .supplier)
        try c.encode(quantityPackets, forKey: .quantityPackets)
        try c.encode(sowingWindows, forKey: .sowingWindows)
        try c.encodeIfPresent(spacingCm, forKey: .spacingCm)
        try c.encodeIfPresent(rowSpacingCm, forKey: .rowSpacingCm)
        try c.encodeIfPresent(depthCm, forKey: .depthCm)
        try c.encodeIfPresent(heightCm, forKey: .heightCm)
        try c.encodeIfPresent(daysToGermination?.lowerBound, forKey: .daysToGerminationMin)
        try c.encodeIfPresent(daysToGermination?.upperBound, forKey: .daysToGerminationMax)
        try c.encodeIfPresent(daysToHarvest?.lowerBound, forKey: .daysToHarvestMin)
        try c.encodeIfPresent(daysToHarvest?.upperBound, forKey: .daysToHarvestMax)
        try c.encode(url, forKey: .url)
        try c.encode(companions, forKey: .companions)
        try c.encode(antagonists, forKey: .antagonists)
        try c.encode(sunRequirement, forKey: .sunRequirement)
        try c.encode(notes, forKey: .notes)
        try c.encode(tags, forKey: .tags)
        try c.encode(colorHex, forKey: .colorHex)
    }
}
