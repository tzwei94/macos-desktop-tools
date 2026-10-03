import CoreGraphics
import Foundation

func check(_ result: CGError, _ operation: String) throws {
    guard result == .success else {
        throw DisplayProblem(message: "\(operation) failed (CoreGraphics error \(result.rawValue)).")
    }
}

func onlineDisplays() throws -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    try check(CGGetOnlineDisplayList(0, nil, &count), "Reading displays")
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    try check(CGGetOnlineDisplayList(count, &displays, &count), "Reading displays")
    return Array(displays.prefix(Int(count)))
}

func configure(_ persistence: CGConfigureOption, changes: (CGDisplayConfigRef) throws -> Void) throws {
    var reference: CGDisplayConfigRef?
    try check(CGBeginDisplayConfiguration(&reference), "Starting display change")
    guard let reference else { throw DisplayProblem(message: "Could not create a display configuration.") }
    do {
        try changes(reference)
    } catch {
        CGCancelDisplayConfiguration(reference)
        throw error
    }
    // CoreGraphics invalidates the transaction on return, including failure.
    try check(CGCompleteDisplayConfiguration(reference, persistence), "Applying display change")
}

struct OriginalDisplay {
    let id: CGDirectDisplayID
    let mirrorOf: CGDirectDisplayID
    let position: DisplayPlacement
}

func switchDisplays(to mode: DisplayMode, main: CGDirectDisplayID, secondaries: [CGDirectDisplayID]) throws {
    guard !secondaries.isEmpty else { throw DisplayProblem(message: "No second display is connected.") }
    if mode == .mirror {
        try configure(.permanently) { configuration in
            for display in secondaries {
                try check(CGConfigureDisplayMirrorOfDisplay(configuration, display, main), "Configuring mirror mode")
            }
        }
        return
    }
    let originals = try secondaries.map { display -> OriginalDisplay in
        let bounds = CGDisplayBounds(display)
        let position = try leftPlacements(mainX: bounds.minX, mainY: bounds.minY, widths: [])
        _ = position // Validate coordinates before converting them.
        return OriginalDisplay(id: display, mirrorOf: CGDisplayMirrorsDisplay(display),
                               position: DisplayPlacement(x: Int32(bounds.minX.rounded()), y: Int32(bounds.minY.rounded())))
    }
    // Unmirror first, then query the displays' actual extended-mode widths.
    try configure(.forSession) { configuration in
        for display in secondaries {
            try check(CGConfigureDisplayMirrorOfDisplay(configuration, display, kCGNullDirectDisplay), "Disabling mirror mode")
        }
    }
    do {
        let refreshed = try onlineDisplays().filter { $0 != main }
        guard Set(refreshed) == Set(secondaries) else {
            throw DisplayProblem(message: "The connected displays changed during the operation. Try again.")
        }
        let mainBounds = CGDisplayBounds(main)
        let positions = try leftPlacements(mainX: mainBounds.minX, mainY: mainBounds.minY,
                                           widths: refreshed.map { CGDisplayBounds($0).width })
        try configure(.permanently) { configuration in
            for (display, position) in zip(refreshed, positions) {
                try check(CGConfigureDisplayOrigin(configuration, display, position.x, position.y), "Positioning display on the left")
            }
        }
    } catch {
        let failure = error.localizedDescription
        do {
            try configure(.forSession) { configuration in
                for original in originals {
                    try check(CGConfigureDisplayMirrorOfDisplay(configuration, original.id, original.mirrorOf), "Restoring previous mirror state")
                    if original.mirrorOf == kCGNullDirectDisplay {
                        try check(CGConfigureDisplayOrigin(configuration, original.id, original.position.x, original.position.y), "Restoring previous position")
                    }
                }
            }
        } catch {
            throw DisplayProblem(message: "\(failure) Recovery also failed: \(error.localizedDescription) Use System Settings > Displays to restore the arrangement.")
        }
        throw DisplayProblem(message: "\(failure) The previous session arrangement was restored.")
    }
}

@main
struct DisplayModeCommand {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count <= 1 else { throw DisplayProblem(message: "Usage: display-mode [toggle|mirror|extend|status]") }
            let requested = arguments.first?.lowercased() ?? "toggle"
            if requested != "status" { _ = try selectedMode(requested: requested, mirrored: false) }
            let main = CGMainDisplayID()
            let secondaries = try onlineDisplays().filter { $0 != main }
            let mirrored = secondaries.contains { CGDisplayIsInMirrorSet($0) != 0 }
            if requested == "status" {
                let output: [String: Any] = ["secondaryDisplays": secondaries.count, "mode": mirrored ? "mirror" : "extend", "canToggle": !secondaries.isEmpty]
                let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                return
            }
            let mode = try selectedMode(requested: requested, mirrored: mirrored)
            try switchDisplays(to: mode, main: main, secondaries: secondaries)
            print(mode == .mirror ? "mirror" : "extend-left")
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
