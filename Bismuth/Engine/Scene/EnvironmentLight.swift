/*
    Copyright 2026 Warren Moore

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

import Foundation
import Metal
import simd

public enum ImageBasedLightError: Error {
    case missingShaderLibrary
    case missingShaderFunction
    case invalidImageFormat
    case imageLoadingFailed
    case resourceAllocationFailure
}

public class EnvironmentLight {
    public let diffuseIrradianceTexture: MTLTexture
    public let specularIrradianceTexture: MTLTexture
    public let scaleAndBiasLookupTexture: MTLTexture

    public let mipLevelCount: Int

    public var rotation: simd_float3x3 = matrix_identity_float3x3
    public var intensity: Float = 1.0

    class func makeImageBasedLight(from texture: MTLTexture) throws -> EnvironmentLight {
        return try ImageBasedLightGenerator.shared.makeLight(from: texture)
    }

    class func makeImageBasedLight(withContentsOfURL fileURL: URL) throws -> EnvironmentLight {
        return try ImageBasedLightGenerator.shared.makeLight(withContentsOfURL:fileURL)
    }

    fileprivate init(diffuseTexture: MTLTexture,
                     specularTexture: MTLTexture,
                     scaleAndBiasLookupTexture: MTLTexture)
    {
        self.diffuseIrradianceTexture = diffuseTexture
        self.specularIrradianceTexture = specularTexture
        self.scaleAndBiasLookupTexture = scaleAndBiasLookupTexture
        self.mipLevelCount = Int(log2(Float(specularTexture.width))) + 1
    }
}

fileprivate class ImageBasedLightGenerator: @unchecked Sendable {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let equirectToCubePipelineState: MTLComputePipelineState
    let lookupTablePipelineState: MTLComputePipelineState
    let prefilteringPipelineState: MTLComputePipelineState

    // Tunable parameters for IBL generation. These values have worked
    // well for a variety of environment maps over time for me, but you
    // could try changing them for performance and fidelity.
    private let diffuseCubeSize = 32
    private let lookupTableSize = 512
    private let specularSampleCount = 1024
    private let diffuseSampleCount = 2048
    private let lutSampleCount = 512

    static let shared: ImageBasedLightGenerator = {
        let context = BismuthContext.shared
        do {
            let instance = try ImageBasedLightGenerator(context)
            return instance
        } catch {
            fatalError("Failed to create image-based light generator: \(error)")
        }
    }()

    init(_ context: BismuthContext) throws {
        self.device = context.device
        self.commandQueue = context.commandQueue

        let library = context.shaderLibrary

        guard let equirectToCubeFunction = library.makeFunction(name: "CubeFromEquirectangular") else {
            throw ImageBasedLightError.missingShaderFunction
        }
        equirectToCubePipelineState = try device.makeComputePipelineState(function:equirectToCubeFunction)

        guard let lutIntegration = library.makeFunction(name: "F0OffsetAndBiasLUT") else {
            throw ImageBasedLightError.missingShaderFunction
        }
        lookupTablePipelineState = try device.makeComputePipelineState(function:lutIntegration)

        guard let prefilterFunction = library.makeFunction(name: "PrefilterEnvironmentMap") else {
            throw ImageBasedLightError.missingShaderFunction
        }
        prefilteringPipelineState = try device.makeComputePipelineState(function:prefilterFunction)
    }

    func makeLight(withContentsOfURL fileURL: URL) throws -> EnvironmentLight {
        guard fileURL.pathExtension.lowercased() == "hdr" else {
            throw ImageBasedLightError.invalidImageFormat
        }

        let texture = try HDRLoader.loadHDR(from: fileURL, device: device)
        return try makeLight(from: texture)
    }

    func makeLight(from equirectTexture: MTLTexture) throws -> EnvironmentLight {
        let sourceHeight = equirectTexture.height

        var workingPixelFormat: MTLPixelFormat = .rgba32Float

        let sourceCubeSize = min(512, sourceHeight / 2)
        let specularCubeSize = sourceCubeSize

        // Mobile processors prior to A17 Pro don't have filterable 32-bpp textures
        if !device.supportsFamily(.mac2) && !device.supportsFamily(.apple9) {
            print("Switching to half-precision pixel format for prefiltered environment maps. Image-based lighting accuracy may suffer.")
            workingPixelFormat = MTLPixelFormat.rgba16Float;
        }

        let sourceCubeDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: workingPixelFormat,
                                                                              size:specularCubeSize,
                                                                              mipmapped:true)
        sourceCubeDescriptor.storageMode = .shared
        sourceCubeDescriptor.usage = [.shaderRead, .shaderWrite]

        guard let sourceCubeTexture = device.makeTexture(descriptor: sourceCubeDescriptor) else {
            throw ImageBasedLightError.resourceAllocationFailure
        }
        sourceCubeTexture.label = "Environment Map (Cube)"

        let cubePixelFormat: MTLPixelFormat = .rgba16Float

        let specularCubeDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat:cubePixelFormat,
                                                                                size:specularCubeSize,
                                                                                mipmapped:true)
        specularCubeDescriptor.usage = [.shaderRead, .shaderWrite]
        specularCubeDescriptor.storageMode = .private

        guard let specularCubeTexture = device.makeTexture(descriptor: specularCubeDescriptor) else {
            throw ImageBasedLightError.resourceAllocationFailure
        }
        specularCubeTexture.label = "Prefiltered Environment (GGX)"

        let diffuseCubeDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat:cubePixelFormat,
                                                                               size:diffuseCubeSize,
                                                                               mipmapped:false)
        diffuseCubeDescriptor.usage = [.shaderRead, .shaderWrite]
        diffuseCubeDescriptor.storageMode = .private

        guard let diffuseCubeTexture = device.makeTexture(descriptor:diffuseCubeDescriptor) else {
            throw ImageBasedLightError.resourceAllocationFailure
        }
        diffuseCubeTexture.label = "Prefiltered Environment (Lambertian)"

        let lookupTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                                               width:lookupTableSize,
                                                                               height:lookupTableSize,
                                                                               mipmapped:false)
        lookupTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        lookupTextureDescriptor.storageMode = .private

        guard let lookupTexture = device.makeTexture(descriptor:lookupTextureDescriptor) else {
            throw ImageBasedLightError.resourceAllocationFailure
        }

        lookupTexture.label = "DFG Lookup Table (GGX)"

        var commandBuffer = commandQueue.makeCommandBuffer()!

        var computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()!

        computeCommandEncoder.setComputePipelineState(equirectToCubePipelineState)
        computeCommandEncoder.setTexture(equirectTexture, index:1)
        computeCommandEncoder.setTexture(sourceCubeTexture, index:0)
        computeCommandEncoder.dispatchThreads(MTLSizeMake(sourceCubeSize, sourceCubeSize, 6),
                                              threadsPerThreadgroup:MTLSizeMake(32, 32, 1))

        computeCommandEncoder.endEncoding()

        commandBuffer.commit()

        commandBuffer = commandQueue.makeCommandBuffer()!

        let mipmapCommandEncoder = commandBuffer.makeBlitCommandEncoder()!
        mipmapCommandEncoder.generateMipmaps(for: sourceCubeTexture)
        mipmapCommandEncoder.endEncoding()

        computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()!

        let mipLevelCount = Int(log2(Float(specularCubeSize))) + 1
        var levelSize = specularCubeSize
        for mipLevel in 0..<mipLevelCount {
            let levelView = specularCubeTexture.makeTextureView(pixelFormat: specularCubeTexture.pixelFormat,
                                                                textureType: .typeCube,
                                                                levels: mipLevel..<(mipLevel + 1),
                                                                slices:0..<6)
            var specularPrefilteringParams = SpecularPrefilteringParams(distribution: 1,
                                                                        sampleCount: UInt32(specularSampleCount),
                                                                        roughness: Float(mipLevel) / Float(mipLevelCount - 1),
                                                                        lodBias: 0.0,
                                                                        cubemapSize: Float(sourceCubeSize))
            computeCommandEncoder.setComputePipelineState(prefilteringPipelineState)
            computeCommandEncoder.setBytes(&specularPrefilteringParams, length:MemoryLayout<SpecularPrefilteringParams>.stride, index:0)
            computeCommandEncoder.setTexture(sourceCubeTexture, index:0)
            computeCommandEncoder.setTexture(levelView, index:1)
            computeCommandEncoder.dispatchThreads(MTLSizeMake(levelSize, levelSize, 6),
                                                  threadsPerThreadgroup:MTLSizeMake(32, 32, 1))
            levelSize >>= 1
        }

        var diffusePrefilteringParams = DiffusePrefilteringParams(distribution: 0,
                                                                  sampleCount: UInt32(diffuseSampleCount),
                                                                  roughness: 0.0, // Ignored by shader
                                                                  lodBias: 0.0,
                                                                  cubemapSize: Float(sourceCubeSize))  // Ignored by shader

        computeCommandEncoder.setComputePipelineState(prefilteringPipelineState)
        computeCommandEncoder.setBytes(&diffusePrefilteringParams, length:MemoryLayout<DiffusePrefilteringParams>.stride, index:0)
        computeCommandEncoder.setTexture(sourceCubeTexture, index:0)
        computeCommandEncoder.setTexture(diffuseCubeTexture, index:1)
        computeCommandEncoder.dispatchThreads(MTLSizeMake(diffuseCubeSize, diffuseCubeSize, 6),
                                              threadsPerThreadgroup:MTLSizeMake(32, 32, 1))

        var sampleCount: UInt32 = UInt32(lutSampleCount)
        computeCommandEncoder.setComputePipelineState(lookupTablePipelineState)
        computeCommandEncoder.setBytes(&sampleCount, length: MemoryLayout<UInt32>.stride, index:0)
        computeCommandEncoder.setTexture(lookupTexture, index:0)
        computeCommandEncoder.dispatchThreads(MTLSizeMake(lookupTableSize, lookupTableSize, 1),
                                              threadsPerThreadgroup:MTLSizeMake(32, 32, 1))

        computeCommandEncoder.endEncoding()

        commandBuffer.commit()

        return EnvironmentLight(diffuseTexture:diffuseCubeTexture,
                                specularTexture:specularCubeTexture,
                                scaleAndBiasLookupTexture:lookupTexture)
    }
}
