import SwiftUI
import SpriteKit

@main
struct HopApp: App {
    var body: some Scene {
        WindowGroup {
            GameContainerView()
        }
    }
}

struct GameContainerView: View {
    @State private var scene: GameScene = {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
    }
}
