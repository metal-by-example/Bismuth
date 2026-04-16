import SwiftUI
import Bismuth

struct ContentView: View {
    var body: some View {
        SceneView {
            Model3D(named: "DamagedHelmet")
                .spin(speed: 1, axis: [0, 1, 0])
                .scale(1.2)

            Group3D {
                for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 8) {
                    Sphere(radius: 0.3)
                        .position(x: Float(cos(angle)) * 2.0,
                                  y: Float(sin(angle) * 2.0))
                        .material(BasicMaterial(color: .init(hue: angle / (2 * .pi),
                                                             saturation: 1.0,
                                                             brightness: 1.0,
                                                             alpha: 1.0),
                                                roughness: 0.1))
                }
            }
            .spin(speed: .pi / 4, axis: [0, 0, 1])

            DirectionalLight(direction: [-0.5, -1, -0.5],
                             color: .white,
                             intensity: 3.0)
            PerspectiveCamera(name: "camera",
                              position: [0, 0, 4],
                              target: .zero)
        } update: { scene in
            if let helmet = scene.entity(named: "DamagedHelmet") {
                helmet.transform.position.y = sin(Float(scene.elapsedTime) * 2) * 0.5
            }
        }
        .pointOfView("camera")
        .environmentLight(named: "metro_noord_2k")
    }
}

#Preview {
    ContentView()
}
