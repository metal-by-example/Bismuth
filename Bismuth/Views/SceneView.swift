import SwiftUI
import MetalKit

public class BismuthMTKView: MTKView {
    public override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        isPaused = true
        enableSetNeedsDisplay = true
    }

    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        enableSetNeedsDisplay = false
        isPaused = false
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if inLiveResize {
            needsDisplay = true
        }
    }
}

public enum MSAAMode: Int {
    case none = 1
    case x2 = 2
    case x4 = 4
}

fileprivate let defaultCameraName = "_defaultPerspectiveCamera"

public class BismuthContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let shaderLibrary: MTLLibrary

    static var shared: BismuthContext = .init()

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        do {
            self.shaderLibrary = try device.makeDefaultLibrary(bundle: Bundle(for: BismuthContext.self))
        } catch {
            fatalError("Failed to load Metal shader library from framework bundle: \(error)")
        }
    }

    convenience init() {
        let metalDevice = MTLCreateSystemDefaultDevice()!
        self.init(device: metalDevice)
    }
}

public struct SceneView: NSViewRepresentable {
    public let bismuthContext = BismuthContext()

    public let contentBuilder: () -> [any SceneContent]
    public var updateHandler: ((SceneGraph) -> Void)?

    private var msaa: MSAAMode = .none
    private var pointOfViewName: String?
    private var environmentLightName: String?
    private var environmentIntensity: Float = 1.0
    private var backgroundName: String?
    private var backgroundLOD: Float = 0.0

    public init(@SceneContentBuilder content: @escaping () -> [any SceneContent]) {
        self.contentBuilder = content
    }

    public init(@SceneContentBuilder content: @escaping () -> [any SceneContent],
         update: @escaping (SceneGraph) -> Void) {
        self.contentBuilder = content
        self.updateHandler = update
    }

    public func makeNSView(context: Context) -> BismuthMTKView {
        let metalView = BismuthMTKView()
        metalView.device = bismuthContext.device
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.colorPixelFormat = .bgra8Unorm_srgb
        metalView.sampleCount = msaa.rawValue
        metalView.colorspace = CGColorSpace(name: CGColorSpace.sRGB)

        // Start with an empty scene; content will be resolved asynchronously
        let scene = SceneGraph()

        let cameraNode = CameraEntity()
        cameraNode.name = defaultCameraName

        let renderer = Renderer(metalView: metalView, scene: scene, context: bismuthContext)
        renderer.pointOfView = cameraNode
        renderer.updateHandler = updateHandler
        context.coordinator.renderer = renderer
        context.coordinator.scene = scene
        context.coordinator.activeMSAA = msaa

        // Build the content descriptor tree synchronously, then resolve asynchronously
        let contentItems = contentBuilder()
        let povName = pointOfViewName
        Task {
            do {
                var entities: [Entity] = []
                for item in contentItems {
                    entities.append(contentsOf: try await item.resolve(bismuthContext))
                }
                scene.rootEntities = entities

                if let name = povName,
                   let cam = scene.entity(named: name),
                   cam.components.has(CameraComponent.self)
                {
                    renderer.pointOfView = cam
                    context.coordinator.pointOfViewName = name
                }
            } catch {
                print("Failed to resolve Bismuth content: \(error)")
            }
        }

        return metalView
    }

    public func updateNSView(_ nsView: BismuthMTKView, context: Context) {
        let scene = context.coordinator.scene ?? SceneGraph()

        if msaa != context.coordinator.activeMSAA {
            nsView.sampleCount = msaa.rawValue
            let renderer = Renderer(metalView: nsView, scene: scene, context: bismuthContext)
            renderer.updateHandler = updateHandler
            context.coordinator.renderer = renderer
            context.coordinator.activeMSAA = msaa
        }

        if pointOfViewName != context.coordinator.pointOfViewName {
            if let name = pointOfViewName, let node = scene.entity(named: name), node.components.has(CameraComponent.self) {
                context.coordinator.renderer?.pointOfView = node
                context.coordinator.pointOfViewName = pointOfViewName
            }
        }

        if environmentLightName != context.coordinator.environmentLightName {
            if let name = environmentLightName {
                if let url = Bundle.main.url(forResource: name, withExtension: "hdr") {
                    do {
                        let ibl = try EnvironmentLight.makeImageBasedLight(withContentsOfURL: url)
                        context.coordinator.renderer?.scene.environmentLight = ibl
                    } catch {
                        print("Failed to load environment light: \(error)")
                    }
                }
            } else {
                context.coordinator.renderer?.scene.environmentLight = nil
            }
        }

        if backgroundName != context.coordinator.backgroundName {
            if let name = backgroundName {
                if let url = Bundle.main.url(forResource: name, withExtension: "hdr") {
                    do {
                        context.coordinator.renderer?.scene.skyboxTexture = try HDRLoader.loadHDR(from: url,
                                                                                                  device: bismuthContext.device,
                                                                                                  mipmapped: true)
                    } catch {
                        print("Failed to load background image: \(error)")
                    }
                }
            }
            context.coordinator.backgroundName = backgroundName
        }

        context.coordinator.renderer?.scene.backgroundLOD = backgroundLOD

        // During live resize, the internal display link is paused, so we
        // trigger a redraw through AppKit's display cycle instead.
        if nsView.enableSetNeedsDisplay {
            nsView.needsDisplay = true
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator {
        var renderer: Renderer?
        var scene: SceneGraph?
        var activeMSAA: MSAAMode = .x4
        var pointOfViewName: String? = defaultCameraName
        var environmentLightName: String?
        var backgroundName: String?
    }

    public func pointOfView(_ name: String) -> SceneView {
        var view = self
        view.pointOfViewName = name
        return view
    }

    public func msaaMode(_ mode: MSAAMode) -> SceneView {
        var view = self
        view.msaa = mode
        return view
    }

    public func environmentLight(named name: String, intensity: Float = 1.0) -> SceneView {
        var view = self
        view.environmentLightName = name
        view.environmentIntensity = intensity
        return view
    }

    public func background(named name: String, lod: Float = 0.0) -> SceneView {
        var view = self
        view.backgroundName = name
        view.backgroundLOD = lod
        return view
    }
}
