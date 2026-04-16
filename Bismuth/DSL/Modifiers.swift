import simd

public struct PositionModifier: SceneContent {
    public var name: String? { "PositionModifier" }

    public let content: any SceneContent
    public let offset: SIMD3<Float>

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let entities = try await content.resolve(context)
        for entity in entities {
            entity.baseTransform.position = offset
            entity.transform.position = offset
        }
        return entities
    }
}

public struct RotationModifier: SceneContent {
    public var name: String? { "RotationModifier" }

    public let content: any SceneContent
    public let angle: Float
    public let axis: SIMD3<Float>

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let entities = try await content.resolve(context)
        for entity in entities {
            entity.baseTransform.rotation = simd_quatf(angle: angle, axis: axis)
            entity.transform.rotation = simd_quatf(angle: angle, axis: axis)
        }
        return entities
    }
}

public struct ScaleModifier: SceneContent {
    public var name: String? { "ScaleModifier" }

    public let content: any SceneContent
    public let scale: SIMD3<Float>

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let entities = try await content.resolve(context)
        for entity in entities {
            entity.baseTransform.scale = scale
            entity.transform.scale = scale
        }
        return entities
    }
}

public struct MaterialModifier: SceneContent {
    public var name: String? { "MaterialModifier" }

    public let content: any SceneContent
    public let materials: [any Material]

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let entities = try await content.resolve(context)
        for entity in entities {
            if var model = entity.components[ModelComponent.self] as? ModelComponent {
                model.materials = materials
                entity.components[ModelComponent.self] = model
            }
        }
        return entities
    }
}

public struct SpinModifier: SceneContent {
    public var name: String? { "SpinModifier" }

    public let content: any SceneContent
    public let speed: Float
    public let axis: SIMD3<Float>

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let entities = try await content.resolve(context)
        for entity in entities {
            entity.animations.append(SpinAnimation(axis: axis, speed: speed))
        }
        return entities
    }
}

public struct OscillateModifier: SceneContent {
    public var name: String? { "OscillateModifier" }

    public let content: any SceneContent
    public let offset: SIMD3<Float>
    public let frequency: Float

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let entities = try await content.resolve(context)
        for entity in entities {
            entity.animations.append(OscillateAnimation(offset: offset, frequency: frequency))
        }
        return entities
    }
}

public extension SceneContent {
    func position(x: Float = 0, y: Float = 0, z: Float = 0) -> some SceneContent {
        PositionModifier(content: self, offset: SIMD3<Float>(x, y, z))
    }

    func rotation(angle: Float, axis: SIMD3<Float>) -> some SceneContent {
        RotationModifier(content: self, angle: angle, axis: axis)
    }

    func scale(x: Float = 1, y: Float = 1, z: Float = 1) -> some SceneContent {
        ScaleModifier(content: self, scale: [x, y, z])
    }

    func scale(_ scale: Float) -> some SceneContent {
        ScaleModifier(content: self, scale: .init(repeating: scale))
    }
}

public extension SceneContent {
    func material(_ material: any Material) -> some SceneContent {
        MaterialModifier(content: self, materials: [material])
    }

    func materials(_ materials: [any Material]) -> some SceneContent {
        MaterialModifier(content: self, materials: materials)
    }
}

public extension SceneContent {
    func spin(speed: Float, axis: SIMD3<Float>) -> some SceneContent {
        SpinModifier(content: self, speed: speed, axis: axis)
    }

    func oscillate(offset: SIMD3<Float>, frequency: Float) -> some SceneContent {
        OscillateModifier(content: self, offset: offset, frequency: frequency)
    }
}
