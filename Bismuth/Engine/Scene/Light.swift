import simd
#if os(macOS)
import AppKit
#endif

public enum LightType {
    case directional
}

public struct LightComponent: Component {
    public var type: LightType = .directional
    public var color: Color
    public var intensity: Float
    public var direction: SIMD3<Float> = SIMD3<Float>(0, -1, 0)

    public init(type: LightType, color: Color, intensity: Float, direction: SIMD3<Float> = [0, -1, 0]) {
        self.type = type
        self.color = color
        self.intensity = intensity
        self.direction = direction
    }
}

protocol HasLight {
    var light: LightComponent { get }
}

public class LightEntity: Entity, HasLight {
    public var light: LightComponent {
        get {
            return self.components[LightComponent.self] as! LightComponent
        }
        set {
            self.components[LightComponent.self] = newValue
        }
    }

    init(lightType: LightType, color: Color, intensity: Float) {
        super.init()
        self.light = LightComponent(type: lightType, color: color, intensity: intensity)
    }
}
