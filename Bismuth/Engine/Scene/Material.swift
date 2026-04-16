#if os(macOS)
import AppKit
#endif

import Metal
import simd

#if os(macOS)
    public typealias Color = NSColor
#else
    public typealias Color = UIColor
#endif

public struct SampledTexture {
    public struct Sampler {
        let samplerDescriptor: MTLSamplerDescriptor

        public init() {
            samplerDescriptor = MTLSamplerDescriptor()
        }

        public init(_ desc: MTLSamplerDescriptor) {
            samplerDescriptor = desc
        }
    }

    public var resource: TextureResource
    public var sampler: Sampler

    public init(_ resource: TextureResource, sampler: Sampler) {
        self.resource = resource
        self.sampler = sampler
    }

    public init(_ resource: TextureResource) {
        self.resource = resource
        self.sampler = .init()
    }
}

//public enum MaterialProperty<Value> {
//    case constant(Value)
//    case texture(SampledTexture)
//}

public struct MaterialRenderContext {
    public let device: MTLDevice
    public let workingColorSpace: CGColorSpace
    public let placeholderTexture: MTLTexture

    public func linearColor(from color: Color) -> SIMD4<Float> {
        let converted = color.cgColor.converted(to: workingColorSpace, intent: .defaultIntent, options: nil)!
        let c = converted.components!.map { Float($0) }
        return SIMD4<Float>(c[0], c[1], c[2], c[3])
    }
}

public protocol Material {
    static var vertexFunctionName: String { get }
    static var fragmentFunctionName: String { get }
    func encode(to encoder: MTLRenderCommandEncoder, context: MaterialRenderContext)
}

public extension Material {
    static var vertexFunctionName: String { "vertex_main" }
}

public struct BaseColor : ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = CGFloat

    public static let textureSemantic: TextureResource.Semantic = .color

    public var color: Color
    public var texture: SampledTexture?

    public init(color: Color, texture: SampledTexture? = nil) {
        self.color = color
        self.texture = texture
    }

    public init(arrayLiteral elements: CGFloat...) {
        if elements.count == 3 {
            color = Color(red: elements[0], green: elements[1], blue: elements[2], alpha: 1.0)
        } else if elements.count == 4 {
            color = Color(red: elements[0], green: elements[1], blue: elements[2], alpha: elements[3])
        } else {
            color = .white
        }
    }
}

public extension BaseColor {
    static var black: BaseColor { [0, 0, 0, 1] }
    static var darkGray: BaseColor { [0.333, 0.333, 0.333, 1] }
    static var lightGray: BaseColor { [0.667, 0.667, 0.667, 1 ] }
    static var white: BaseColor { [1, 1, 1, 1 ] }
    static var gray: BaseColor { [0.5, 0.5, 0.5, 1 ] }
    static var red: BaseColor { [ 1, 0, 0, 1] }
    static var green: BaseColor { [0, 1, 0, 1] }
    static var blue: BaseColor { [ 0, 0, 1, 1 ] }
    static var yellow: BaseColor { [ 1, 1, 0, 1 ] }
    static var clear: BaseColor { [0, 0, 0, 0] }
}

public struct Metalness : ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Float

    public static let textureSemantic: TextureResource.Semantic = .scalar

    public var scale: Float
    public var texture: SampledTexture?

    public init(scale: Float = 1.0, texture: SampledTexture? = nil) {
        self.scale = scale
        self.texture = texture
    }

    public init(floatLiteral value: Float) {
        scale = value
    }
}

public struct Roughness : ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Float

    public static let textureSemantic: TextureResource.Semantic = .scalar

    public var scale: Float
    public var texture: SampledTexture?

    public init(scale: Float = 1.0, texture: SampledTexture? = nil) {
        self.scale = scale
        self.texture = texture
    }

    public init(floatLiteral value: Float) {
        self.scale = value
    }
}

public struct Normal {
    public static let textureSemantic: TextureResource.Semantic = .normal

    public var scale: Float
    public var texture: SampledTexture?
}

// Texture flag bits — must match the constants in Shaders.metal
enum TextureFlag {
    static let baseColor: UInt32          = 1
    static let metallicRoughness: UInt32  = 2
    static let normal: UInt32             = 4
}

struct DefaultMaterial: Material {
    static let fragmentFunctionName = "fragment_main"

    func encode(to encoder: MTLRenderCommandEncoder, context: MaterialRenderContext) {
        var mc = MaterialConstants()
        mc.baseColorFactor = SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
        mc.roughnessFactor = 0.5
        mc.metalnessFactor = 0.0
        mc.normalScale = 1.0
        mc.textureFlags = 0
        encoder.setFragmentBytes(&mc, length: MemoryLayout<MaterialConstants>.size, index: 1)
        encoder.setFragmentTexture(context.placeholderTexture, index: 0)
        encoder.setFragmentTexture(context.placeholderTexture, index: 1)
        encoder.setFragmentTexture(context.placeholderTexture, index: 2)
    }
}

public struct BasicMaterial: Material {
    public static let fragmentFunctionName = "fragment_main"

    public var color: BaseColor
    public var roughness: Roughness
    public var metalness: Metalness
    public var normal: Normal?

    public init(color: Color, roughness: Roughness = 0.5, metalness: Metalness = 0.0, normal: Normal? = nil) {
        self.color = .init(color: color)
        self.roughness = roughness
        self.metalness = metalness
        self.normal = normal
    }

    public init(color: BaseColor, roughness: Roughness = 0.5, metalness: Metalness = 0.0, normal: Normal? = nil) {
        self.color = color
        self.roughness = roughness
        self.metalness = metalness
        self.normal = normal
    }

    public func encode(to encoder: MTLRenderCommandEncoder, context: MaterialRenderContext) {
        var flags: UInt32 = 0

        var mc = MaterialConstants()
        mc.baseColorFactor = context.linearColor(from: color.color)
        mc.roughnessFactor = roughness.scale
        mc.metalnessFactor = metalness.scale
        mc.normalScale = normal?.scale ?? 1.0

        // Base color texture
        if let tex = color.texture {
            encoder.setFragmentTexture(tex.resource.texture, index: 0)
            flags |= TextureFlag.baseColor
        } else {
            encoder.setFragmentTexture(context.placeholderTexture, index: 0)
        }

        // Metallic-roughness texture (glTF packs roughness in G, metallic in B)
        // We look at roughness.texture since both roughness and metalness share the same map
        if let tex = roughness.texture {
            encoder.setFragmentTexture(tex.resource.texture, index: 1)
            flags |= TextureFlag.metallicRoughness
        } else if let tex = metalness.texture {
            encoder.setFragmentTexture(tex.resource.texture, index: 1)
            flags |= TextureFlag.metallicRoughness
        } else {
            encoder.setFragmentTexture(context.placeholderTexture, index: 1)
        }

        // Normal map
        if let tex = normal?.texture {
            encoder.setFragmentTexture(tex.resource.texture, index: 2)
            flags |= TextureFlag.normal
        } else {
            encoder.setFragmentTexture(context.placeholderTexture, index: 2)
        }

        mc.textureFlags = flags
        encoder.setFragmentBytes(&mc, length: MemoryLayout<MaterialConstants>.size, index: 1)
    }
}
