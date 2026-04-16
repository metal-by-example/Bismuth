import Foundation
import Metal
import simd
import ImageIO
import CoreGraphics

class Skybox {
    var environmentTexture: MTLTexture

    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private let indexCount: Int
    private let renderPipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState

    init(device: MTLDevice, library: MTLLibrary, texture: MTLTexture,
         colorPixelFormat: MTLPixelFormat, sampleCount: Int) throws
    {
        self.environmentTexture = texture

        (self.vertexBuffer, self.indexBuffer, self.indexCount) = try Self.makeMesh(device: device)

        renderPipeline = try Self.makePipeline(device: device, library: library,
                                               colorPixelFormat: colorPixelFormat,
                                               sampleCount: sampleCount)

        // Reverse-Z: skybox at z=0 (far plane). Pass where depth >= stored (i.e., 0 >= 0 at clear,
        // but fail where geometry wrote depth > 0). No depth writes.
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .greaterEqual
        depthStencilDescriptor.isDepthWriteEnabled = false
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
    }

    private static func makeMesh(device: MTLDevice) throws -> (MTLBuffer, MTLBuffer, Int) {
        let vertices: [SIMD3<Float>] = [
            [-1, -1,  1], [ 1, -1,  1], [ 1,  1,  1], [-1,  1,  1], // Front
            [-1, -1, -1], [-1,  1, -1], [ 1,  1, -1], [ 1, -1, -1], // Back
            [-1,  1, -1], [-1,  1,  1], [ 1,  1,  1], [ 1,  1, -1], // Top
            [-1, -1, -1], [ 1, -1, -1], [ 1, -1,  1], [-1, -1,  1], // Bottom
            [ 1, -1, -1], [ 1,  1, -1], [ 1,  1,  1], [ 1, -1,  1], // Right
            [-1, -1, -1], [-1, -1,  1], [-1,  1,  1], [-1,  1, -1]  // Left
        ]

        let indices: [UInt16] = [
             0,  2,  1,  2,  0,  3, // Front
             4,  6,  5,  6,  4,  7, // Back
             8, 10,  9, 10,  8, 11, // Top
            12, 14, 13, 14, 12, 15, // Bottom
            16, 18, 17, 18, 16, 19, // Right
            20, 22, 21, 22, 20, 23  // Left
        ]

        let indexCount = indices.count

        guard let vertexBuffer = device.makeBuffer(bytes: vertices,
                                                   length: vertices.count * MemoryLayout<SIMD3<Float>>.stride,
                                                   options: .storageModeShared) else
        {
            throw ResourceError.bufferCreationFailed
        }

        guard let indexBuffer = device.makeBuffer(bytes: indices,
                                                  length: indices.count * MemoryLayout<UInt16>.stride,
                                                  options: .storageModeShared) else
        {
            throw ResourceError.bufferCreationFailed
        }

        vertexBuffer.label = "Skybox Vertices"
        indexBuffer.label = "Skybox Indices"

        return (vertexBuffer, indexBuffer, indexCount)
    }

    private static func makePipeline(device: MTLDevice, library: MTLLibrary,
                                     colorPixelFormat: MTLPixelFormat,
                                     sampleCount: Int) throws -> MTLRenderPipelineState
    {
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Skybox Pipeline"
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "skybox_vertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "skybox_fragment")
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.rasterSampleCount = sampleCount

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    func draw(encoder: MTLRenderCommandEncoder) {
        encoder.pushDebugGroup("Skybox")
        defer { encoder.popDebugGroup() }

        encoder.setRenderPipelineState(renderPipeline)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setCullMode(.back)

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        // ViewConstants at vertex buffer 1 and SceneConstants at vertex buffer 2
        // are expected to be already bound by the caller.

        encoder.setFragmentTexture(environmentTexture, index: 0)

        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: indexCount,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer,
                                      indexBufferOffset: 0)
    }
}
