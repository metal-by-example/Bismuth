import Foundation
import simd

public protocol Animation {
    func apply(to entity: Entity, time: TimeInterval, deltaTime: TimeInterval)
}

public struct SpinAnimation: Animation {
    public let axis: SIMD3<Float>
    public let speed: Float // radians per second

    public func apply(to entity: Entity, time: TimeInterval, deltaTime: TimeInterval) {
        let angle = Float(time) * speed
        entity.transform.rotation = simd_quatf(angle: angle, axis: axis) * entity.baseTransform.rotation
    }
}

public struct OscillateAnimation: Animation {
    public let offset: SIMD3<Float>
    public let frequency: Float // cycles per second

    public func apply(to entity: Entity, time: TimeInterval, deltaTime: TimeInterval) {
        let t = sin(Float(time) * frequency * 2 * .pi)
        entity.transform.position = entity.baseTransform.position + offset * t
    }
}
