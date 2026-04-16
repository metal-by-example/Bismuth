import simd
import Spatial

public struct CameraComponent: Component {
    public var fovY: Angle2D
    public var nearZ: Float

    public init(fovYDegrees: Double = 65, nearZ: Float = 0.01) {
        self.fovY = .degrees(fovYDegrees)
        self.nearZ = nearZ
    }

    public func projectionMatrix(aspectRatio: Double) -> float4x4 {
        float4x4(reverseZPerspectiveFovY: fovY.radians, aspectRatio: aspectRatio, near: nearZ)
    }
}

public protocol HasCamera {
    var camera: CameraComponent { get }
}

public class CameraEntity: Entity, HasCamera {
    public var camera: CameraComponent {
        get {
            return self.components[CameraComponent.self] as! CameraComponent
        }
        set {
            self.components[CameraComponent.self] = newValue
        }
    }

    public init(fovYDegrees: Double = 65, nearZ: Float = 0.01) {
        super.init()
        self.camera = CameraComponent(fovYDegrees: fovYDegrees, nearZ: nearZ)
    }
}
