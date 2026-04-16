import MetalKit
import QuartzCore
import simd

public protocol Resource : Sendable {
}

struct RenderInstanceGroup {
    var mesh: MeshResource
    var materials: [any Material]
    var worldTransform: simd_float4x4
}

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let depthStencilState: MTLDepthStencilState
    let samplerState: MTLSamplerState
    let placeholderTexture: MTLTexture
    let placeholderCubemap: MTLTexture
    let placeholderBRDFLUT: MTLTexture
    let materialRenderContext: MaterialRenderContext

    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var colorPixelFormat: MTLPixelFormat
    private var rasterSampleCount: Int

    var scene: SceneGraph
    var pointOfView = Entity()
    var updateHandler: ((SceneGraph) -> Void)?

    private var skybox: Skybox?
    private var currentSkyboxTextureID: ObjectIdentifier?

    private static let defaultMaterial = DefaultMaterial()

    init(metalView: MTKView, scene: SceneGraph, context: BismuthContext) {
        self.scene = scene

        self.device = context.device
        self.commandQueue = context.commandQueue
        self.library = context.shaderLibrary

        colorPixelFormat = metalView.colorPixelFormat
        rasterSampleCount = metalView.sampleCount

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .greater
        depthDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)!

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)!

        // 1×1 white placeholder 2D texture
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        texDesc.usage = .shaderRead
        texDesc.storageMode = .shared
        placeholderTexture = device.makeTexture(descriptor: texDesc)!
        var white: UInt32 = 0xFFFFFFFF
        placeholderTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white, bytesPerRow: 4)

        // 1×1 black placeholder cubemap for when IBL is not active
        let cubeDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba8Unorm, size: 1, mipmapped: false)
        cubeDesc.usage = .shaderRead
        cubeDesc.storageMode = .shared
        placeholderCubemap = device.makeTexture(descriptor: cubeDesc)!
        var black: UInt32 = 0xFF000000
        for face in 0..<6 {
            placeholderCubemap.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, slice: face,
                                       withBytes: &black, bytesPerRow: 4, bytesPerImage: 4)
        }

        // 1×1 placeholder BRDF LUT (zero scale/bias)
        let lutDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        lutDesc.usage = .shaderRead
        lutDesc.storageMode = .shared
        placeholderBRDFLUT = device.makeTexture(descriptor: lutDesc)!
        placeholderBRDFLUT.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)

        let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        materialRenderContext = MaterialRenderContext(
            device: device,
            workingColorSpace: workingColorSpace,
            placeholderTexture: placeholderTexture
        )

        super.init()

        metalView.depthStencilPixelFormat = .depth32Float
        metalView.clearDepth = 0.0
        metalView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        metalView.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func pipelineState(for material: any Material) -> MTLRenderPipelineState {
        let key = "\(type(of: material).vertexFunctionName)/\(type(of: material).fragmentFunctionName)/\(colorPixelFormat.rawValue)/\(rasterSampleCount)"

        if let cached = pipelineCache[key] {
            return cached
        }

        let vertexFunction = library.makeFunction(name: type(of: material).vertexFunctionName)!
        let fragmentFunction = library.makeFunction(name: type(of: material).fragmentFunctionName)!

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(MeshResource.defaultVertexDescriptor)
        descriptor.rasterSampleCount = rasterSampleCount

        let state = try! device.makeRenderPipelineState(descriptor: descriptor)
        pipelineCache[key] = state
        return state
    }

    private func updateSkyboxIfNeeded() {
        guard let skyboxTexture = scene.skyboxTexture else {
            skybox = nil
            currentSkyboxTextureID = nil
            return
        }

        let textureID = ObjectIdentifier(skyboxTexture)
        if currentSkyboxTextureID == textureID { return }

        do {
            skybox = try Skybox(device: device, library: library, texture: skyboxTexture,
                                colorPixelFormat: colorPixelFormat, sampleCount: rasterSampleCount)
            currentSkyboxTextureID = textureID
        } catch {
            print("Failed to create skybox: \(error)")
            skybox = nil
            currentSkyboxTextureID = nil
        }
    }

    private func collectLights(from entities: [Entity]) -> [LightConstants] {
        var result: [LightConstants] = []
        for entity in entities {
            if let light = entity.components[LightComponent.self] as? LightComponent {
                var lc = LightConstants()
                lc.direction = simd_float3(light.direction)
                let colorVec = materialRenderContext.linearColor(from: light.color).xyz
                lc.color = colorVec * light.intensity
                lc.position = entity.transform.position
                result.append(lc)
            }
            result.append(contentsOf: collectLights(from: entity.children))
        }
        return result
    }

    func draw(in view: MTKView) {
        // Flush pipeline cache if formats or MSAA config has changed
        if colorPixelFormat != view.colorPixelFormat || rasterSampleCount != view.sampleCount {
            colorPixelFormat = view.colorPixelFormat
            rasterSampleCount = view.sampleCount
            pipelineCache.removeAll()
            currentSkyboxTextureID = nil // Force skybox pipeline rebuild
        }

        updateSkyboxIfNeeded()

        scene.update(currentTime: CACurrentMediaTime())

        updateHandler?(scene)

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        encoder.setDepthStencilState(depthStencilState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)

        let drawableSize = view.drawableSize
        let aspectRatio = drawableSize.width / drawableSize.height

        let viewMatrix = pointOfView.worldMatrix.inverse
        let projectionMatrix = (pointOfView.components[CameraComponent.self] as? CameraComponent)?
            .projectionMatrix(aspectRatio: aspectRatio)
            ?? float4x4(reverseZPerspectiveFovY: 1.13, aspectRatio: aspectRatio, near: 0.01)

        var viewConstants = ViewConstants()
        viewConstants.viewMatrix = viewMatrix
        viewConstants.projectionMatrix = projectionMatrix
        encoder.setVertexBytes(&viewConstants, length: MemoryLayout<ViewConstants>.size, index: 1)

        let envRotationMatrix = simd_float3x3(scene.environmentRotation)

        let cameraPos = pointOfView.transform.position
        var lights = collectLights(from: scene.rootEntities)
        var sceneConstants = SceneConstants()
        sceneConstants.environmentTransform = envRotationMatrix
        sceneConstants.cameraPosition = SIMD4<Float>(cameraPos.x, cameraPos.y, cameraPos.z, 1.0)
        sceneConstants.ambientIntensity = SIMD3<Float>(0.1, 0.1, 0.1)
        sceneConstants.lightCount = UInt32(lights.count)
        sceneConstants.environmentIntensity = scene.environmentLight != nil ? scene.environmentLight!.intensity : 0.0
        sceneConstants.backgroundLOD = scene.backgroundLOD
        encoder.setFragmentBytes(&sceneConstants, length: MemoryLayout<SceneConstants>.size, index: 0)

        encoder.setFragmentBytes(&lights, length: MemoryLayout<LightConstants>.stride * max(lights.count, 1), index: 2)

        encoder.setFragmentSamplerState(samplerState, index: 0)

        // Bind IBL textures (or placeholders when no environment light is present)
        if let envLight = scene.environmentLight {
            encoder.setFragmentTexture(envLight.diffuseIrradianceTexture, index: 3)
            encoder.setFragmentTexture(envLight.specularIrradianceTexture, index: 4)
            encoder.setFragmentTexture(envLight.scaleAndBiasLookupTexture, index: 5)
        } else {
            encoder.setFragmentTexture(placeholderCubemap, index: 3)
            encoder.setFragmentTexture(placeholderCubemap, index: 4)
            encoder.setFragmentTexture(placeholderBRDFLUT, index: 5)
        }

        let instanceGroups = scene.flattenedNodes()

        for instanceGroup in instanceGroups {
            let mesh = instanceGroup.mesh
            let material = instanceGroup.materials.first ?? Self.defaultMaterial

            let pipeline = pipelineState(for: material)
            encoder.setRenderPipelineState(pipeline)

            let modelMatrix = instanceGroup.worldTransform
            let normalMatrix = modelMatrix.upperLeft3x3.inverse.transpose
            var instanceConstants = InstanceConstants()
            instanceConstants.modelMatrix = modelMatrix
            instanceConstants.normalMatrix = normalMatrix
            encoder.setVertexBytes(&instanceConstants, length: MemoryLayout<InstanceConstants>.size, index: 2)

            material.encode(to: encoder, context: materialRenderContext)

            guard let vertexBufferView = mesh.vertexBuffers.first else { continue }
            encoder.setVertexBuffer(vertexBufferView.buffer, offset: vertexBufferView.offset, index: 0)

            // Draw each mesh part
            for part in mesh.parts {
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: part.indexCount,
                    indexType: part.indexType,
                    indexBuffer: mesh.indexBuffer.buffer,
                    indexBufferOffset: mesh.indexBuffer.offset + part.indexBufferOffset,
                    instanceCount: 1
                )
            }
        }

        if let skybox {
            encoder.setVertexBytes(&sceneConstants, length: MemoryLayout<SceneConstants>.size, index: 2)
            encoder.setFragmentBytes(&sceneConstants, length: MemoryLayout<SceneConstants>.size, index: 0)
            skybox.draw(encoder: encoder)
            // Restore main pass state
            encoder.setDepthStencilState(depthStencilState)
            encoder.setCullMode(.back)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
