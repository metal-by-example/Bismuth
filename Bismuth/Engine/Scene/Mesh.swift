import Metal
import ModelIO
import simd

public struct Vertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var texCoords: SIMD2<Float>
}

extension MeshResource {
    static var defaultVertexDescriptor: MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        (descriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (descriptor.attributes[0] as! MDLVertexAttribute).format = .float3
        (descriptor.attributes[0] as! MDLVertexAttribute).offset = MemoryLayout<Vertex>.offset(of: \.position)!
        (descriptor.attributes[0] as! MDLVertexAttribute).bufferIndex = 0
        (descriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (descriptor.attributes[1] as! MDLVertexAttribute).format = .float3
        (descriptor.attributes[1] as! MDLVertexAttribute).offset = MemoryLayout<Vertex>.offset(of: \.normal)!
        (descriptor.attributes[1] as! MDLVertexAttribute).bufferIndex = 0
        (descriptor.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (descriptor.attributes[2] as! MDLVertexAttribute).format = .float2
        (descriptor.attributes[2] as! MDLVertexAttribute).offset = MemoryLayout<Vertex>.offset(of: \.texCoords)!
        (descriptor.attributes[2] as! MDLVertexAttribute).bufferIndex = 0
        (descriptor.layouts[0] as! MDLVertexBufferLayout).stride = MemoryLayout<Vertex>.stride
        return descriptor
    }
}

public struct BufferView {
    public let buffer: MTLBuffer
    public let offset: Int
    public let length: Int

    public init(buffer: MTLBuffer, offset: Int = 0, length: Int? = nil) {
        self.buffer = buffer
        self.offset = offset
        if let length {
            self.length = length
        } else {
            self.length = buffer.length - offset
        }
    }
}

public class MeshResource {
    public struct Part {
        let indexBufferOffset: Int
        let indexCount: Int
        let indexType: MTLIndexType
        let materialIndex: Int = 0
    }

    public var bounds: BoundingBox
    public let vertexDescriptor: MDLVertexDescriptor
    public let vertexBuffers: [BufferView]
    public let vertexCount: Int
    public let indexBuffer: BufferView
    public let parts: [Part]

    public init(vertexBuffers: [BufferView],
                vertexDescriptor: MDLVertexDescriptor,
                vertexCount: Int,
                indexBuffer: BufferView,
                parts: [Part])
    {
        self.bounds = BoundingBox()
        self.vertexDescriptor = vertexDescriptor
        self.vertexBuffers = vertexBuffers
        self.vertexCount = vertexCount
        self.indexBuffer = indexBuffer
        self.parts = parts
    }
}

public extension MeshResource {
    convenience init(vertices: [Vertex], indices: [UInt32], device: MTLDevice) throws {
        let vertexBuffer = device.makeBuffer(bytes: vertices,
                                             length: MemoryLayout<Vertex>.stride * vertices.count,
                                             options: .storageModeShared)!
        let vertexCount = vertices.count
        let indexBuffer = device.makeBuffer(bytes: indices,
                                            length: MemoryLayout<UInt32>.stride * indices.count,
                                            options: .storageModeShared)!
        let indexCount = indices.count
        let part = Part(indexBufferOffset: 0, indexCount: indexCount, indexType: .uint32)

        self.init(vertexBuffers: [BufferView(buffer: vertexBuffer)],
                  vertexDescriptor: Self.defaultVertexDescriptor,
                  vertexCount: vertexCount,
                  indexBuffer: BufferView(buffer: indexBuffer),
                  parts: [part])
    }
}

public extension MeshResource {
    static func generateBox(width: Float, height: Float, depth: Float, device: MTLDevice) throws -> MeshResource {
        let (vertices, indices) = BoxGeometry.generate(width: width, height: height, depth: depth)
        return try .init(vertices: vertices, indices: indices, device: device)
    }

    static func generateSphere(radius: Float, segmentCount: Int, device: MTLDevice) throws -> MeshResource {
        let (vertices, indices) = SphereGeometry.generate(radius: radius, segments: segmentCount)
        return try .init(vertices: vertices, indices: indices, device: device)
    }
}

public struct ModelComponent : Component {
    public var mesh: MeshResource
    public var materials: [any Material]

    public init(mesh: MeshResource, materials: [any Material]) {
        self.mesh = mesh
        self.materials = materials
    }
}

public protocol HasModel {
    var model: ModelComponent { get }
}

public class ModelEntity: Entity, HasModel {
    public var model: ModelComponent {
        get {
            self.components[ModelComponent.self] as! ModelComponent
        }
        set {
            self.components[ModelComponent.self] = newValue
        }
    }

    public init(mesh: MeshResource, materials: [any Material]) {
        super.init()
        self.model = ModelComponent(mesh: mesh, materials: materials)
    }
}
