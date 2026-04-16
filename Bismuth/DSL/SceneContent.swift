public protocol SceneContent {
    var name: String? { get }
    func resolve(_ context: BismuthContext) async throws -> [Entity]
}

@resultBuilder
public struct SceneContentBuilder {
    public static func buildBlock(_ components: any SceneContent...) -> [any SceneContent] {
        Array(components)
    }

    public static func buildOptional(_ component: [any SceneContent]?) -> [any SceneContent] {
        component ?? []
    }

    public static func buildEither(first component: [any SceneContent]) -> [any SceneContent] {
        component
    }

    public static func buildEither(second component: [any SceneContent]) -> [any SceneContent] {
        component
    }

    public static func buildArray(_ components: [[any SceneContent]]) -> [any SceneContent] {
        components.flatMap { $0 }
    }
}

extension Array: SceneContent where Element == any SceneContent {
    public var name: String? { "Array<SceneContent>" }

    public func resolve(_ context: BismuthContext) async throws -> [Entity] {
        var result: [Entity] = []
        for element in self {
            result.append(contentsOf: try await element.resolve(context))
        }
        return result
    }
}
