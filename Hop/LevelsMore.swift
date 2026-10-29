import Foundation
import CoreGraphics

/// The 50 parking levels, read from Hop/levels.json (made by tools/design_levels.py on a measured
/// difficulty curve: every level is solved by a planner driving the game's car). Kept as data:
/// as a Swift array literal of 3,000 obstacles the compiler gave up.
extension Levels {
    private static let designed: (levels: [LevelDef], spanish: [String: String]) = {
        guard let url = Bundle.main.url(forResource: "levels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["levels"] as? [[String: Any]] else { return ([], [:]) }
        func numbers(_ value: Any?) -> [[CGFloat]] {
            (value as? [[Any]] ?? []).map { row in row.compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } } }
        }
        var spanish: [String: String] = [:]
        var levels: [LevelDef] = []
        for entry in list {
            let name = entry["name"] as? [String] ?? ["", "", ""]
            if name.count == 3 { spanish[name[1]] = name[2] }
            let starts = numbers(entry["starts"]).map { start($0[0], $0[1], $0[2]) }
            let spots = numbers(entry["spots"]).map { spot($0[0], $0[1], $0[2], $0[3], $0[4]) }
            var obstacles: [ObstacleDef] = []
            for item in entry["obstacles"] as? [[Any]] ?? [] {
                guard let kind = item.first as? String else { continue }
                let v = item.dropFirst().compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } }
                switch kind {
                case "c" where v.count >= 4: obstacles.append(car(v[0], v[1], v[2], Int(v[3])))
                case "o" where v.count >= 2: obstacles.append(cone(v[0], v[1]))
                case "w" where v.count >= 4: obstacles.append(wall(v[0], v[1], v[2], v[3]))
                default: break
                }
            }
            levels.append(LevelDef(nameTR: name.first ?? "", nameEN: name.count > 1 ? name[1] : "",
                                   starts: starts, spots: spots, obstacles: obstacles))
        }
        return (levels, spanish)
    }()

    static var moreSpanishNames: [String: String] { designed.spanish }

    static var more: [LevelDef] { designed.levels }
}
