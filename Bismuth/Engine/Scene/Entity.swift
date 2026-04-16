import Foundation
import simd

public protocol Component {
}

public extension Entity {
    struct ComponentSet {
        public subscript<T>(componentType: T.Type) -> T? where T : Component {
            return self[componentType] as? T
        }

        public subscript(componentType: any Component.Type) -> (any Component)? {
            get {
                return components[ObjectIdentifier(componentType)]
            }
            set {
                components[ObjectIdentifier(componentType.self)] = newValue
            }
        }

        public mutating func set<T>(_ component: T) where T : Component {
            components[ObjectIdentifier(T.self)] = component
        }
        
        public func has(_ componentType: any Component.Type) -> Bool {
            return components.keys.contains(ObjectIdentifier(componentType))
        }

        public mutating func remove(_ componentType: any Component.Type) {
            components[ObjectIdentifier(componentType)] = nil
        }

        private var components: [ObjectIdentifier : any Component] = [:]
    }
}

public class Entity {
    public var name: String?

    //public var boundingBox: BoundingBox = .init()

    // Base transform — set by DSL, stable across frames
    public var baseTransform = AffineTransform()

    // Live transform — reset to base each frame, then modified by animations/update
    public var transform = AffineTransform()

    public weak var parent: Entity?
    public var _children: [Entity] = []

    public var children: [Entity] {
        get { _children }
        set {
            for child in _children { child.parent = nil }
            _children = newValue
            for child in _children { child.parent = self }
        }
    }

    public var animations: [any Animation] = []

    public var components = ComponentSet()

    public var localMatrix: simd_float4x4 {
        return transform.matrix
    }

    public var worldMatrix: simd_float4x4 {
        if let parent {
            return parent.worldMatrix * localMatrix
        }
        return localMatrix
    }

    func resetToBase() {
        transform = baseTransform
        for child in children {
            child.resetToBase()
        }
    }

    public func lookAt(_ target: SIMD3<Float>, from position: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) {
        let z = normalize(target - position)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        let TRS = simd_float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, target), -dot(y, target), -dot(z, target), 1)
        )
        self.baseTransform = AffineTransform(matrix: TRS)
    }

    func applyAnimations(time: TimeInterval, deltaTime: TimeInterval) {
        for animation in animations {
            animation.apply(to: self, time: time, deltaTime: deltaTime)
        }
        for child in children {
            child.applyAnimations(time: time, deltaTime: deltaTime)
        }
    }

    func flatten(parentTransform: simd_float4x4 = matrix_identity_float4x4) -> [RenderInstanceGroup] {
        let worldTransform = parentTransform * localMatrix
        var result: [RenderInstanceGroup] = []

        if let model = self.components[ModelComponent.self] as? ModelComponent {
            result.append(RenderInstanceGroup(mesh: model.mesh, materials: model.materials, worldTransform: worldTransform))
        }

        for child in children {
            result.append(contentsOf: child.flatten(parentTransform: worldTransform))
        }

        return result
    }
}
