import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct DisplayPlanTests {
    static func main() throws {
        expect((try? selectedMode(requested: "toggle", mirrored: false)) == .mirror, "Extended display should switch to mirror")
        expect((try? selectedMode(requested: "toggle", mirrored: true)) == .extend, "Mirrored display should switch to extend")
        expect((try? selectedMode(requested: "mirror", mirrored: true)) == .mirror, "Explicit mirror should stay mirror")
        expect((try? selectedMode(requested: "extend", mirrored: false)) == .extend, "Explicit extend should stay extend")
        do {
            _ = try selectedMode(requested: "invalid", mirrored: false)
            fatalError("Invalid modes must be rejected")
        } catch { }
        let placements = try leftPlacements(mainX: 0, mainY: 120, widths: [1920, 1280])
        expect(placements == [DisplayPlacement(x: -1920, y: 120), DisplayPlacement(x: -3200, y: 120)], "Extended displays should be adjacent on the left, aligned to the main display")
        expect((try? leftPlacements(mainX: 100, mainY: -20, widths: [800])) == [DisplayPlacement(x: -700, y: -20)], "Nonzero origins should be preserved")
        for widths in [[0.0], [-10.0], [Double.nan], [Double.infinity], [Double(Int32.max) * 2]] {
            do {
                _ = try leftPlacements(mainX: 0, mainY: 0, widths: widths)
                fatalError("Invalid display geometry must be rejected")
            } catch { }
        }
        print("Display planning tests passed (12 checks).")
    }
}
