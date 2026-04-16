import Foundation
import Metal

enum ResourceError: Error {
    case bufferCreationFailed
    case stagingBufferCreationFailed
    case textureCreationFailed
    case assetNotFound
}

enum HDRLoadError: Error {
    case unsupportedFormat
    case invalidFormat
}

class HDRLoader {
    static func loadHDR(from url: URL, device: MTLDevice, mipmapped: Bool = false) throws -> MTLTexture {
        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "hdr" {
            return try loadRadianceRGBE(from: url, device: device, mipmapped: mipmapped)
        } else {
            throw HDRLoadError.unsupportedFormat
        }
    }

    private static func loadRadianceRGBE(from url: URL, device: MTLDevice, mipmapped: Bool) throws -> MTLTexture {
        var w: Int32 = 0, h: Int32 = 0, c: Int32 = 0
        let sourceImageBytes = stbi_loadf(url.path(), &w, &h, &c, 4)

        guard let sourceImageBytes else {
            throw ImageBasedLightError.imageLoadingFailed
        }
        defer {
            free(sourceImageBytes)
        }

        let sourceWidth = Int(w)
        let sourceHeight = Int(h)
        let sourceBitsPerComponent = 32
        let workingBytesPerPixel = (sourceBitsPerComponent / 8) * 4

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,
                                                                         width:sourceWidth,
                                                                         height:sourceHeight,
                                                                         mipmapped:mipmapped)
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = mipmapped ? [.shaderRead, .shaderWrite] : .shaderRead

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw ResourceError.textureCreationFailed
        }
        texture.label = url.lastPathComponent
        texture.replace(region: MTLRegionMake2D(0, 0, sourceWidth, sourceHeight),
                        mipmapLevel:0,
                        withBytes:sourceImageBytes,
                        bytesPerRow:workingBytesPerPixel * sourceWidth)

        if mipmapped {
            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let blitEncoder = commandBuffer.makeBlitCommandEncoder() else
            {
                throw ResourceError.bufferCreationFailed
            }
            blitEncoder.generateMipmaps(for: texture)
            blitEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        return texture
    }
}
