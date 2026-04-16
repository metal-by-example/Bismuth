import GLTFKit2
import ImageIO
import Metal
import MetalKit
import simd

enum GLTFLoadError: Error {
    case missingBufferData
    case missingPositionAttribute
    case unsupportedIndexType
    case bufferCreationFailed
}

class GLTFLoader {
    let device: MTLDevice
    private var textureCache: [ObjectIdentifier: TextureResource] = [:]

    init(context: BismuthContext) {
        self.device = context.device
    }

    func load(from url: URL) throws -> Entity {
        let asset = try GLTFAsset(url: url)
        guard let scene = asset.defaultScene ?? asset.scenes.first else {
            return Entity()
        }

        var materialCache: [ObjectIdentifier: any Material] = [:]
        for mat in asset.materials {
            materialCache[ObjectIdentifier(mat)] = convertMaterial(mat)
        }

        var meshCache: [ObjectIdentifier: [(MeshResource, any Material)]] = [:]
        for mesh in asset.meshes {
            do {
                meshCache[ObjectIdentifier(mesh)] = try convertMesh(mesh, materialCache: materialCache)
            } catch {
                print("GLTFLoader: skipping mesh '\(mesh.name ?? "<unnamed>")': \(error)")
            }
        }

        let root = Entity()
        root.name = scene.name
        root.children = scene.nodes.map { convertNode($0, meshCache: meshCache) }
        return root
    }

    private func convertNode(_ gltfNode: GLTFNode,
                             meshCache: [ObjectIdentifier: [(MeshResource, any Material)]]) -> Entity
    {
        let entity = Entity()
        entity.name = gltfNode.name

        var t = AffineTransform()
        t.position = SIMD3<Float>(gltfNode.translation)
        t.rotation = gltfNode.rotation
        t.scale = SIMD3<Float>(gltfNode.scale)
        entity.baseTransform = t
        entity.transform = t

        var childEntities: [Entity] = []
        if let gltfMesh = gltfNode.mesh,
           let primitives = meshCache[ObjectIdentifier(gltfMesh)]
        {
            for (mesh, material) in primitives {
                childEntities.append(ModelEntity(mesh: mesh, materials: [material]))
            }
        }

        for childNode in gltfNode.childNodes {
            childEntities.append(convertNode(childNode, meshCache: meshCache))
        }

        entity.children = childEntities
        return entity
    }

    private func convertMesh(_ gltfMesh: GLTFMesh,
                             materialCache: [ObjectIdentifier: any Material]) throws -> [(MeshResource, any Material)]
    {
        var results: [(MeshResource, any Material)] = []
        for primitive in gltfMesh.primitives {
            if primitive.primitiveType != .triangles { continue }
            let (meshResource, material) = try convertPrimitive(primitive, materialCache: materialCache)
            results.append((meshResource, material))
        }
        return results
    }

    private func convertPrimitive(_ primitive: GLTFPrimitive,
                                  materialCache: [ObjectIdentifier: any Material]) throws -> (MeshResource, any Material)
    {
        guard let positionAttribute = primitive.attribute(forName: GLTFAttributeSemantic.position.rawValue) else {
            throw GLTFLoadError.missingPositionAttribute
        }

        let positions = try readFloat3Array(from: positionAttribute.accessor)
        let vertexCount = positions.count

        let normals: [SIMD3<Float>]
        if let normalAttribute = primitive.attribute(forName: GLTFAttributeSemantic.normal.rawValue) {
            normals = try readFloat3Array(from: normalAttribute.accessor)
        } else {
            normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: vertexCount)
        }

        let texCoords: [SIMD2<Float>]
        if let texCoordAttribute = primitive.attribute(forName: GLTFAttributeSemantic.texcoord0.rawValue) {
            texCoords = try readFloat2Array(from: texCoordAttribute.accessor)
        } else {
            texCoords = [SIMD2<Float>](repeating: .zero, count: vertexCount)
        }

        var vertices = [Vertex](repeating: Vertex(position: .zero, normal: .zero, texCoords: .zero),
                                count: vertexCount)
        for i in 0..<vertexCount {
            vertices[i].position = positions[i]
            vertices[i].normal = normals[i]
            vertices[i].texCoords = texCoords[i]
        }

        let indices: [UInt32]
        if let indexAccessor = primitive.indices {
            indices = try readUInt32Indices(from: indexAccessor)
        } else {
            // Non-indexed geometry: generate sequential indices
            indices = (0..<UInt32(vertexCount)).map { $0 }
        }

        let meshResource = try MeshResource(vertices: vertices, indices: indices, device: device)

        let material: any Material
        if let gltfMat = primitive.material {
            material = materialCache[ObjectIdentifier(gltfMat)] ?? DefaultMaterial()
        } else {
            material = DefaultMaterial()
        }

        return (meshResource, material)
    }

    // MARK: - Material Conversion

    private func convertMaterial(_ gltfMat: GLTFMaterial) -> any Material {
        let pbr = gltfMat.metallicRoughness

        let baseColorFactor = pbr?.baseColorFactor ?? [1, 1, 1, 1]
        let r = CGFloat(baseColorFactor[0])
        let g = CGFloat(baseColorFactor[1])
        let b = CGFloat(baseColorFactor[2])
        let a = CGFloat(baseColorFactor[3])

        let baseColorTexture = loadSampledTexture(from: pbr?.baseColorTexture, sRGB: true)
        let color = BaseColor(color: Color(red: r, green: g, blue: b, alpha: a), texture: baseColorTexture)

        // Metallic-roughness texture (linear; G=roughness, B=metallic)
        let mrTexture = loadSampledTexture(from: pbr?.metallicRoughnessTexture, sRGB: false)
        let roughness = Roughness(scale: pbr?.roughnessFactor ?? 1.0, texture: mrTexture)
        let metalness = Metalness(scale: pbr?.metallicFactor ?? 0.0, texture: mrTexture)

        var normal: Normal? = nil
        if let normalInfo = gltfMat.normalTexture {
            let normalTexture = loadSampledTexture(from: normalInfo, sRGB: false)
            if normalTexture != nil {
                normal = Normal(scale: normalInfo.scale, texture: normalTexture)
            }
        }

        return BasicMaterial(color: color, roughness: roughness, metalness: metalness, normal: normal)
    }

    private func loadSampledTexture(from textureParams: GLTFTextureParams?, sRGB: Bool) -> SampledTexture? {
        guard let textureParams else { return nil }
        let gltfTexture = textureParams.texture
        guard let gltfImage = gltfTexture.source else { return nil }

        let resource = loadTextureResource(from: gltfImage, sRGB: sRGB)
        guard let resource else { return nil }
        return SampledTexture(resource)
    }

    private func loadTextureResource(from gltfImage: GLTFImage, sRGB: Bool) -> TextureResource? {
        let key = ObjectIdentifier(gltfImage)
        if let cached = textureCache[key] {
            return cached
        }

        guard let cgImage = createCGImage(from: gltfImage) else {
            print("GLTFLoader: could not decode image '\(gltfImage.name ?? "<unnamed>")'")
            return nil
        }

        do {
            let resource = try TextureResource(cgImage: cgImage, sRGB: sRGB, device: device)
            textureCache[key] = resource
            return resource
        } catch {
            print("GLTFLoader: failed to create texture from image '\(gltfImage.name ?? "<unnamed>")': \(error)")
            return nil
        }
    }

    private func createCGImage(from gltfImage: GLTFImage) -> CGImage? {
        // Try URI-based image first
        if let uri = gltfImage.uri {
            guard let source = CGImageSourceCreateWithURL(uri as CFURL, nil),
                  CGImageSourceGetCount(source) > 0 else
            {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        // Fall back to buffer-view-based image
        if let bufferView = gltfImage.bufferView,
           let bufferData = bufferView.buffer.data
        {
            let offset = bufferView.offset
            let length = bufferView.length
            let imageData = bufferData[offset..<(offset + length)] as CFData
            guard let source = CGImageSourceCreateWithData(imageData, nil),
                  CGImageSourceGetCount(source) > 0 else
            {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        return nil
    }

    // MARK: - Accessor Data Reading

    private func readFloat3Array(from accessor: GLTFAccessor) throws -> [SIMD3<Float>] {
        guard let bufferView = accessor.bufferView,
              let data = bufferView.buffer.data else
        {
            throw GLTFLoadError.missingBufferData
        }

        let componentSize = MemoryLayout<Float>.size
        let tightStride = componentSize * 3
        let stride = bufferView.stride > 0 ? bufferView.stride : tightStride
        let baseOffset = bufferView.offset + accessor.offset

        var result = [SIMD3<Float>](repeating: .zero, count: accessor.count)
        data.withUnsafeBytes { rawBuffer in
            for i in 0..<accessor.count {
                let offset = baseOffset + i * stride
                let ptr = rawBuffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Float.self)
                result[i] = SIMD3<Float>(ptr[0], ptr[1], ptr[2])
            }
        }
        return result
    }

    private func readFloat2Array(from accessor: GLTFAccessor) throws -> [SIMD2<Float>] {
        guard let bufferView = accessor.bufferView,
              let data = bufferView.buffer.data else
        {
            throw GLTFLoadError.missingBufferData
        }

        let componentSize = MemoryLayout<Float>.size
        let tightStride = componentSize * 2
        let stride = bufferView.stride > 0 ? bufferView.stride : tightStride
        let baseOffset = bufferView.offset + accessor.offset

        var result = [SIMD2<Float>](repeating: .zero, count: accessor.count)
        data.withUnsafeBytes { rawBuffer in
            for i in 0..<accessor.count {
                let offset = baseOffset + i * stride
                let ptr = rawBuffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Float.self)
                result[i] = SIMD2<Float>(ptr[0], ptr[1])
            }
        }
        return result
    }

    private func readUInt32Indices(from accessor: GLTFAccessor) throws -> [UInt32] {
        guard let bufferView = accessor.bufferView,
              let data = bufferView.buffer.data else
        {
            throw GLTFLoadError.missingBufferData
        }

        let baseOffset = bufferView.offset + accessor.offset

        return data.withUnsafeBytes { rawBuffer -> [UInt32] in
            var result = [UInt32](repeating: 0, count: accessor.count)

            switch accessor.componentType {
            case .unsignedByte:
                let stride = bufferView.stride > 0 ? bufferView.stride : 1
                for i in 0..<accessor.count {
                    let ptr = rawBuffer.baseAddress!.advanced(by: baseOffset + i * stride)
                        .assumingMemoryBound(to: UInt8.self)
                    result[i] = UInt32(ptr.pointee)
                }
            case .unsignedShort:
                let stride = bufferView.stride > 0 ? bufferView.stride : 2
                for i in 0..<accessor.count {
                    let ptr = rawBuffer.baseAddress!.advanced(by: baseOffset + i * stride)
                        .assumingMemoryBound(to: UInt16.self)
                    result[i] = UInt32(ptr.pointee)
                }
            case .unsignedInt:
                let stride = bufferView.stride > 0 ? bufferView.stride : 4
                for i in 0..<accessor.count {
                    let ptr = rawBuffer.baseAddress!.advanced(by: baseOffset + i * stride)
                        .assumingMemoryBound(to: UInt32.self)
                    result[i] = ptr.pointee
                }
            default:
                break
            }

            return result
        }
    }
}
