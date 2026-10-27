import GameKit
import UIKit

/// Game Center: signs the player in quietly at launch and posts scores to three leaderboards.
/// Everything is optional: without Game Center (or before the leaderboards exist) the calls do
/// nothing and the game plays the same.
@MainActor
enum GameCenter {
    /// Leaderboard ids (created in App Store Connect by tools/asc_game_center.py).
    static let totalStars = "parkrift.stars"
    static let bestDrift = "parkrift.drift"
    static let totalWins = "parkrift.wins"

    private static var started = false

    static var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }

    static func authenticate() {
        guard !started else { return }
        started = true
        GKLocalPlayer.local.authenticateHandler = { controller, _ in
            guard let controller = controller else { return }
            // Shown once by Game Center itself when the player is not signed in yet
            topController()?.present(controller, animated: true)
        }
    }

    static func submit(_ score: Int, to leaderboard: String) {
        guard isSignedIn, score > 0 else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [leaderboard]) { _ in }
    }

    /// Game Center's own leaderboard screen.
    static func showLeaderboards() {
        guard isSignedIn else {
            authenticate()
            return
        }
        let controller = GKGameCenterViewController(state: .leaderboards)
        controller.gameCenterDelegate = Dismisser.shared
        topController()?.present(controller, animated: true)
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class Dismisser: NSObject, GKGameCenterControllerDelegate {
        static let shared = Dismisser()
        func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
            controller.dismiss(animated: true)
        }
    }
}
