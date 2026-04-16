import Foundation
import Metal
import simd

public class SceneGraph {
    public var rootEntities: [Entity] = []
    public var environmentLight: EnvironmentLight?
    public var skyboxTexture: MTLTexture?
    public var environmentRotation: simd_quatf = simd_quatf(angle: 0.0, axis: [0, 1, 0])
    public var backgroundLOD: Float = 0.0

    public private(set) var elapsedTime: TimeInterval = 0
    private var lastFrameTime: TimeInterval?

    public func update(currentTime: TimeInterval) {
        let deltaTime: TimeInterval
        if let last = lastFrameTime {
            deltaTime = currentTime - last
        } else {
            deltaTime = 0
        }
        lastFrameTime = currentTime
        elapsedTime += deltaTime

        // Reset all nodes to their base transforms
        for entity in rootEntities {
            entity.resetToBase()
        }

        // Apply declarative animations
        for entity in rootEntities {
            entity.applyAnimations(time: elapsedTime, deltaTime: deltaTime)
        }
    }

    func flattenedNodes() -> [RenderInstanceGroup] {
        rootEntities.flatMap { $0.flatten() }
    }

    public func entity(named name: String) -> Entity? {
        func find(in entities: [Entity]) -> Entity? {
            for entity in entities {
                if entity.name == name { return entity }
                if let found = find(in: entity.children) { return found }
            }
            return nil
        }
        return find(in: rootEntities)
    }
}
