import Foundation
import GLTFKit2

public struct Box: SceneContent {
    public var name: String?

    public let width: Float
    public let height: Float
    public let depth: Float

    public init(name: String? = nil, width: Float = 1, height: Float = 1, depth: Float = 1) {
        self.name = name
        self.width = width
        self.height = height
        self.depth = depth
    }

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let mesh = try MeshResource.generateBox(width: width, height: height, depth: depth, device: context.device)
        let entity = ModelEntity(mesh: mesh, materials: [])
        entity.name = name
        return [entity]
    }
}

public struct Sphere: SceneContent {
    public var name: String?

    public let radius: Float
    public let segmentCount: Int

    public init(name: String? = nil, radius: Float = 0.5, segmentCount: Int = 24) {
        self.name = name
        self.radius = radius
        self.segmentCount = segmentCount
    }

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let mesh = try MeshResource.generateSphere(radius: radius, segmentCount: segmentCount, device: context.device)
        let entity = ModelEntity(mesh: mesh, materials: [])
        entity.name = name
        return [entity]
    }
}

public struct Model3D: SceneContent {
    public var name: String?
    
    public let assetURL: URL?

    public init(named name: String) {
        self.assetURL = Bundle.main.url(forResource: name, withExtension: "gltf") ??
                        Bundle.main.url(forResource: name, withExtension: "glb")
        self.name = name
    }

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        if let url = assetURL {
            let loader = GLTFLoader(context: context)
            let rootEntity = try loader.load(from: url)
            rootEntity.name = name
            return [rootEntity]
        } else {
            throw ResourceError.assetNotFound
        }
    }
}
