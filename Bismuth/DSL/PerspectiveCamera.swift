import simd
import Spatial

public struct PerspectiveCamera: SceneContent {
    public var name: String?
    public var fovY: Angle2D
    public var nearZ: Float
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float>

    public init(name: String? = nil,
         position: SIMD3<Float> = [0, 0, 5],
         target: SIMD3<Float> = .zero,
         up: SIMD3<Float> = [0, 1, 0],
         fovYDegrees: Double = 65,
         nearZ: Float = 0.01)
    {
        self.name = name
        self.position = position
        self.target = target
        self.up = up
        self.fovY = .degrees(fovYDegrees)
        self.nearZ = nearZ
    }

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let entity = CameraEntity(fovYDegrees: fovY.degrees, nearZ: nearZ)
        entity.name = name

        let z = normalize(position - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        entity.baseTransform.position = position
        entity.baseTransform.rotation = simd_quatf(simd_float3x3(x, y, z))
        entity.transform = entity.baseTransform

        return [entity]
    }
}
