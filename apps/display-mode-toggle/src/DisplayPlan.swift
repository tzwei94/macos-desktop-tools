import Foundation

enum DisplayMode: String {
    case mirror, extend
}

struct DisplayProblem: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct DisplayPlacement: Equatable {
    let x: Int32
    let y: Int32
}

func selectedMode(requested: String, mirrored: Bool) throws -> DisplayMode {
    if requested == "toggle" { return mirrored ? .extend : .mirror }
    guard let mode = DisplayMode(rawValue: requested) else {
        throw DisplayProblem(message: "Usage: display-mode [toggle|mirror|extend|status]")
    }
    return mode
}

func leftPlacements(mainX: Double, mainY: Double, widths: [Double]) throws -> [DisplayPlacement] {
    let limits = Double(Int32.min)...Double(Int32.max)
    guard mainX.isFinite, mainY.isFinite, limits.contains(mainX.rounded()), limits.contains(mainY.rounded()) else {
        throw DisplayProblem(message: "The main display has invalid coordinates.")
    }
    var edge = mainX.rounded()
    return try widths.map { width in
        guard width.isFinite, width.rounded() > 0 else {
            throw DisplayProblem(message: "A display has an invalid width.")
        }
        edge -= width.rounded()
        guard limits.contains(edge) else {
            throw DisplayProblem(message: "The display arrangement exceeds supported coordinates.")
        }
        return DisplayPlacement(x: Int32(edge), y: Int32(mainY.rounded()))
    }
}
