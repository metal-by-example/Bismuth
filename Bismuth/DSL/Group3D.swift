public struct Group3D: SceneContent {
    public var name: String? { "Group3D" }

    public let children: [any SceneContent]

    public init(@SceneContentBuilder content: () -> [any SceneContent]) {
        self.children = content()
    }

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        let parent = Entity()
        var childEntities: [Entity] = []
        for child in children {
            childEntities.append(contentsOf: try await child.resolve(context))
        }
        parent.children = childEntities
        return [parent]
    }
}
