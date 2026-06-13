import Foundation

struct Seed: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var variety: String = ""
    var supplier: String = ""
    var quantityPackets: Int = 1

    // Sowing windows relative to last frost (negative = before, positive = after)
    var sowIndoorsWeeksBeforeFrost: Int? // nil = not recommended indoors
    var sowOutdoorsWeeksFromFrost: Int?  // nil = not recommended outdoors
    var transplantWeeksAfterIndoorSow: Int = 6

    var spacingCm: Double?
    var rowSpacingCm: Double?
    var depthCm: Double?
    var daysToGermination: ClosedRange<Int>?
    var daysToHarvest: ClosedRange<Int>?

    var companions: [String] = []
    var antagonists: [String] = []
    var sunRequirement: SunRequirement = .fullSun
    var notes: String = ""
    var tags: [String] = []

    // Computed display name
    var displayName: String {
        variety.isEmpty ? name : "\(name) (\(variety))"
    }

    // Colour used in calendar/grid (stored as hex string)
    var colorHex: String = "#4CAF50"
}

enum SunRequirement: String, Codable, CaseIterable {
    case fullSun = "Full Sun"
    case partialShade = "Partial Shade"
    case fullShade = "Full Shade"
}

// Custom coding for ClosedRange<Int>
extension Seed {
    enum CodingKeys: String, CodingKey {
        case id, name, variety, supplier, quantityPackets
        case sowIndoorsWeeksBeforeFrost, sowOutdoorsWeeksFromFrost, transplantWeeksAfterIndoorSow
        case spacingCm, rowSpacingCm, depthCm
        case daysToGerminationMin, daysToGerminationMax
        case daysToHarvestMin, daysToHarvestMax
        case companions, antagonists, sunRequirement, notes, tags, colorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        variety = try c.decodeIfPresent(String.self, forKey: .variety) ?? ""
        supplier = try c.decodeIfPresent(String.self, forKey: .supplier) ?? ""
        quantityPackets = try c.decodeIfPresent(Int.self, forKey: .quantityPackets) ?? 1
        sowIndoorsWeeksBeforeFrost = try c.decodeIfPresent(Int.self, forKey: .sowIndoorsWeeksBeforeFrost)
        sowOutdoorsWeeksFromFrost = try c.decodeIfPresent(Int.self, forKey: .sowOutdoorsWeeksFromFrost)
        transplantWeeksAfterIndoorSow = try c.decodeIfPresent(Int.self, forKey: .transplantWeeksAfterIndoorSow) ?? 6
        spacingCm = try c.decodeIfPresent(Double.self, forKey: .spacingCm)
        rowSpacingCm = try c.decodeIfPresent(Double.self, forKey: .rowSpacingCm)
        depthCm = try c.decodeIfPresent(Double.self, forKey: .depthCm)
        if let dMin = try c.decodeIfPresent(Int.self, forKey: .daysToGerminationMin),
           let dMax = try c.decodeIfPresent(Int.self, forKey: .daysToGerminationMax) {
            daysToGermination = dMin...dMax
        }
        if let hMin = try c.decodeIfPresent(Int.self, forKey: .daysToHarvestMin),
           let hMax = try c.decodeIfPresent(Int.self, forKey: .daysToHarvestMax) {
            daysToHarvest = hMin...hMax
        }
        companions = try c.decodeIfPresent([String].self, forKey: .companions) ?? []
        antagonists = try c.decodeIfPresent([String].self, forKey: .antagonists) ?? []
        sunRequirement = try c.decodeIfPresent(SunRequirement.self, forKey: .sunRequirement) ?? .fullSun
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#4CAF50"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(variety, forKey: .variety)
        try c.encode(supplier, forKey: .supplier)
        try c.encode(quantityPackets, forKey: .quantityPackets)
        try c.encodeIfPresent(sowIndoorsWeeksBeforeFrost, forKey: .sowIndoorsWeeksBeforeFrost)
        try c.encodeIfPresent(sowOutdoorsWeeksFromFrost, forKey: .sowOutdoorsWeeksFromFrost)
        try c.encode(transplantWeeksAfterIndoorSow, forKey: .transplantWeeksAfterIndoorSow)
        try c.encodeIfPresent(spacingCm, forKey: .spacingCm)
        try c.encodeIfPresent(rowSpacingCm, forKey: .rowSpacingCm)
        try c.encodeIfPresent(depthCm, forKey: .depthCm)
        try c.encodeIfPresent(daysToGermination?.lowerBound, forKey: .daysToGerminationMin)
        try c.encodeIfPresent(daysToGermination?.upperBound, forKey: .daysToGerminationMax)
        try c.encodeIfPresent(daysToHarvest?.lowerBound, forKey: .daysToHarvestMin)
        try c.encodeIfPresent(daysToHarvest?.upperBound, forKey: .daysToHarvestMax)
        try c.encode(companions, forKey: .companions)
        try c.encode(antagonists, forKey: .antagonists)
        try c.encode(sunRequirement, forKey: .sunRequirement)
        try c.encode(notes, forKey: .notes)
        try c.encode(tags, forKey: .tags)
        try c.encode(colorHex, forKey: .colorHex)
    }
}
