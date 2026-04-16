import simd

extension simd_float4 {
    var xyz: simd_float3 {
        return simd_float3(x, y, z)
    }
}

extension float4x4 {
    static let identity = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))

    var upperLeft3x3: float3x3 {
        float3x3(
            SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z),
            SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z),
            SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
        )
    }

    init(translation t: SIMD3<Float>) {
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        ))
    }

    init(rotation angle: Float, axis: SIMD3<Float>) {
        let a = normalize(axis)
        let c = cos(angle)
        let s = sin(angle)
        let t = 1 - c

        self.init(columns: (
            SIMD4<Float>(t * a.x * a.x + c,       t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y, 0),
            SIMD4<Float>(t * a.x * a.y - s * a.z, t * a.y * a.y + c,       t * a.y * a.z + s * a.x, 0),
            SIMD4<Float>(t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c,       0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    init(scale s: SIMD3<Float>) {
        self.init(diagonal: SIMD4<Float>(s.x, s.y, s.z, 1))
    }

    init(perspectiveFovY fovYRadians: Double, aspectRatio: Double, near: Float, far: Float) {
        let y = 1 / tan(Float(fovYRadians) * 0.5)
        let x = y / Float(aspectRatio)
        let z = far / (near - far)
        self.init(
            SIMD4<Float>(x, 0, 0,  0),
            SIMD4<Float>(0, y, 0,  0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, z * near, 0)
        )
    }

    /// Reverse-Z perspective projection with an infinite far plane.
    /// Near maps to z_ndc = 1, infinity maps to z_ndc = 0.
    init(reverseZPerspectiveFovY fovYRadians: Double, aspectRatio: Double, near: Float) {
        let y = 1 / tan(Float(fovYRadians) * 0.5)
        let x = y / Float(aspectRatio)
        self.init(
            SIMD4<Float>(x, 0, 0,    0),
            SIMD4<Float>(0, y, 0,    0),
            SIMD4<Float>(0, 0, 0,   -1),
            SIMD4<Float>(0, 0, near, 0)
        )
    }

    init(lookAt eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        self.init(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        )
    }
}

public struct AffineTransform {
    public var position: SIMD3<Float> = .zero
    public var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
    public var scale: SIMD3<Float> = .one

    public var matrix: simd_float4x4 {
        let T = float4x4(translation: position)
        let R = simd_float4x4(rotation)
        let S = float4x4(scale: scale)
        return T * R * S
    }

    public init() {
    }

    public init(matrix: simd_float4x4) {
        self.position = matrix.columns.3.xyz
        self.scale = [
            simd_length(matrix.columns.0.xyz),
            simd_length(matrix.columns.1.xyz),
            simd_length(matrix.columns.2.xyz),
        ]
        let R = simd_float3x3(
            simd_normalize(matrix.columns.0.xyz),
            simd_normalize(matrix.columns.1.xyz),
            simd_normalize(matrix.columns.2.xyz))
        rotation = simd_quatf(R)
    }
}

public struct BoundingBox : Hashable, Sendable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init() {
        min = .init(repeating: .infinity)
        max = .init(repeating: -.infinity)
    }

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public init(points: [SIMD3<Float>]) {
        var minX: Float = .infinity, minY: Float = .infinity, minZ: Float = .infinity
        var maxX: Float = -.infinity, maxY: Float = -.infinity, maxZ: Float = -.infinity
        for point in points {
            if point.x < minX { minX = point.x }
            if point.y < minY { minY = point.y }
            if point.z < minZ { minZ = point.z }
            if point.x > maxX { maxX = point.x }
            if point.y > maxY { maxY = point.y }
            if point.z > maxZ { maxZ = point.z }
        }
        self.min = SIMD3<Float>(minX, minY, minZ)
        self.max = SIMD3<Float>(maxX, maxY, maxZ)
    }

    public var center: SIMD3<Float> {
        return (min + max) * 0.5
    }

    public var extents: SIMD3<Float> {
        return max - min
    }

    public var boundingRadius: Float {
        let s = extents
        let diag = sqrtf(s.x * s.x + s.y * s.y + s.z * s.z)
        return diag * 0.5
    }

    public var isEmpty: Bool {
        let s = extents
        return s.x > 0 && s.y > 0 && s.z > 0
    }

    //public func union(_ point: SIMD3<Float>) -> BoundingBox
    //public func union(_ other: BoundingBox) -> BoundingBox
    //public func contains(_ point: SIMD3<Float>) -> Bool
    //public func contains(_ boundingBox: BoundingBox) -> Bool
    //public func intersects(_ boundingBox: BoundingBox) -> Bool

    public func transformed(by transform: float4x4) -> BoundingBox {
        let corners: [SIMD3<Float>] = [
            [min.x, min.y, min.z],
            [min.x, min.y, max.z],
            [min.x, max.y, min.z],
            [min.x, max.y, max.z],
            [max.x, min.y, min.z],
            [max.x, min.y, max.z],
            [max.x, max.y, min.z],
            [max.x, max.y, max.z]
        ]
        return BoundingBox(points: corners)
    }
}
