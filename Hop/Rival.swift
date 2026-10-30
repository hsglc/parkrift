import Foundation
import UIKit

/// Rövanş: a finished run (who drove it, the level, the time and the path the car took)
/// that a friend can race against as a ghost. Shared as a link; the server keeps it 30 days.
struct RivalRun: Codable, Equatable {
    var code: String?
    let name: String
    let title: String
    let level: Int
    let time: Double
    /// What decides who wins (lower is better): the time, or the race score with crash penalties.
    let score: Double
    let hits: Int
    let precision: Int?
    /// x, y (world units) and heading (milliradians) every 0.1 s.
    let ghost: [Int]

    /// The path as the scene plays it back: x, y, heading per sample.
    var path: [Float] {
        var result: [Float] = []
        result.reserveCapacity(ghost.count)
        for index in stride(from: 0, to: ghost.count - 2, by: 3) {
            result += [Float(ghost[index]), Float(ghost[index + 1]), Float(ghost[index + 2]) / 1000]
        }
        return result
    }

    /// From a recording of x, y, heading samples.
    static func pack(_ samples: [Float]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(samples.count)
        for index in stride(from: 0, to: samples.count - 2, by: 3) {
            result += [Int(samples[index].rounded()), Int(samples[index + 1].rounded()), Int((samples[index + 2] * 1000).rounded())]
        }
        return result
    }
}

enum RivalService {
    static let site = "https://parkrift.huseyinglc0-946.workers.dev"

    enum Failure: Error { case server, gone }

    /// Stores a run; returns its code.
    static func upload(_ run: RivalRun) async throws -> String {
        var request = URLRequest(url: URL(string: site + "/challenge")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(run)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? String else { throw Failure.server }
        return code
    }

    static func fetch(code: String) async throws -> RivalRun {
        var request = URLRequest(url: URL(string: site + "/challenge/" + code)!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw status == 404 ? Failure.gone : Failure.server }
        var run = try JSONDecoder().decode(RivalRun.self, from: data)
        run.code = code
        return run
    }

    static func link(_ code: String) -> URL { URL(string: site + "/c/" + code)! }

    /// The code in a link: parkrift://c/CODE or https://…/c/CODE.
    static func code(in url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let candidates = url.scheme == "parkrift" ? [url.host ?? ""] + parts : parts
        guard let index = candidates.firstIndex(of: "c"), index + 1 < candidates.count else { return nil }
        let code = candidates[index + 1].uppercased()
        return code.count == 6 ? code : nil
    }
}

/// The nickname shown to friends on Rövanş links (chosen once, kept on the phone).
enum PlayerName {
    static var nick: String? {
        get {
            let value = UserDefaults.standard.string(forKey: "pp.nick")?.trimmingCharacters(in: .whitespaces)
            return value?.isEmpty == false ? value : nil
        }
        set { UserDefaults.standard.set(newValue.map { String($0.prefix(16)) }, forKey: "pp.nick") }
    }
}

/// The share sheet over whatever is on screen.
enum SharePresenter {
    @MainActor
    static func share(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(sheet, animated: true)
    }
}
