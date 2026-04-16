import simd

public struct DirectionalLight: SceneContent {
    public var name: String?
    public var direction: SIMD3<Float>
    public var color: Color
    public var intensity: Float

    public init(name: String? = nil, direction: SIMD3<Float> = [0, 0, 1], color: Color, intensity: Float) {
        self.name = name
        self.direction = direction
        self.color = color
        self.intensity = intensity
    }

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let entity = LightEntity(lightType: .directional, color: color, intensity: intensity)
        // TODO: Derive light direction from its entity's transform,
        // to allow lights to be "attached" to entities in a hierarchy.
        entity.light.direction = normalize(direction)
        entity.name = name
        return [entity]
    }
}
