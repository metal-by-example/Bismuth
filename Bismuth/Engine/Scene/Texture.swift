import Metal
import MetalKit

public class TextureResource : Resource, @unchecked Sendable {
    public enum Semantic {
        case raw
        case scalar
        case color
        case normal
    }

    public let texture: MTLTexture
    public let sourceURL: URL?

    public let semantic: TextureResource.Semantic?

    public var width: Int {
        return texture.width
    }

    public var height: Int {
        texture.height
    }

    public var depth: Int {
        texture.depth
    }

    public var mipmapLevelCount: Int {
        texture.mipmapLevelCount
    }

    public var pixelFormat: MTLPixelFormat {
        texture.pixelFormat
    }

    public var textureType: MTLTextureType {
        texture.textureType
    }

    public var arrayLength: Int {
        texture.arrayLength
    }

    init(texture: MTLTexture, sourceURL: URL? = nil, semantic: Semantic? = nil) {
        self.texture = texture
        self.sourceURL = sourceURL
        self.semantic = semantic
    }

    convenience init(url: URL, sRGB: Bool = true, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: sRGB,
        ]
        let mtlTexture = try loader.newTexture(URL: url, options: options)
        mtlTexture.label = url.lastPathComponent
        self.init(texture: mtlTexture, sourceURL: url)
    }

    convenience init(cgImage: CGImage, sRGB: Bool = true, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: sRGB,
            .generateMipmaps: true,
        ]
        let mtlTexture = try loader.newTexture(cgImage: cgImage, options: options)
        self.init(texture: mtlTexture)
    }

    convenience init(named name: String, in bundle: Bundle = .main, sRGB: Bool = true, device: MTLDevice) async throws {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: sRGB,
        ]
        let mtlTexture = try await loader.newTexture(name: name, scaleFactor: 1.0, bundle: bundle, options: options)
        mtlTexture.label = name
        self.init(texture: mtlTexture, sourceURL: nil)
    }
}
