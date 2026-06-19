import Metal
import os

private let visualizationLogger = Logger(subsystem: "com.winamp.macos", category: "Visualization")

/// Shared Metal device, command queue, and compiled pipeline states for all visualizers.
final class MetalVisualizationEngine: @unchecked Sendable {
    static let shared: MetalVisualizationEngine = {
        guard let engine = MetalVisualizationEngine() else {
            preconditionFailure("Metal is required for visualization")
        }
        return engine
    }()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private let pipelineLock = OSAllocatedUnfairLock()

    private var _spectrumPipeline: MTLRenderPipelineState?
    private var _spectrumPeakPipeline: MTLRenderPipelineState?
    private var _spectrumCompositePipeline: MTLRenderPipelineState?
    private var _oscilloscopePipeline: MTLRenderPipelineState?
    private var _fullscreenPipeline: MTLRenderPipelineState?
    private var _copyPipeline: MTLRenderPipelineState?

    var spectrumPipeline: MTLRenderPipelineState? {
        self.pipelineLock.lock()
        defer { self.pipelineLock.unlock() }
        if self._spectrumPipeline == nil {
            self._spectrumPipeline = self.makePipeline(vertex: "spectrumVertex", fragment: "spectrumFragment")
        }
        return self._spectrumPipeline
    }

    var spectrumPeakPipeline: MTLRenderPipelineState? {
        self.pipelineLock.lock()
        defer { self.pipelineLock.unlock() }
        if self._spectrumPeakPipeline == nil {
            self._spectrumPeakPipeline = self.makePipeline(vertex: "spectrumPeakVertex", fragment: "spectrumPeakFragment")
        }
        return self._spectrumPeakPipeline
    }

    var spectrumCompositePipeline: MTLRenderPipelineState? {
        self.pipelineLock.lock()
        defer { self.pipelineLock.unlock() }
        if self._spectrumCompositePipeline == nil {
            self._spectrumCompositePipeline = self.makePipeline(vertex: "fullscreenVertex", fragment: "spectrumCompositeFragment")
        }
        return self._spectrumCompositePipeline
    }

    var oscilloscopePipeline: MTLRenderPipelineState? {
        self.pipelineLock.lock()
        defer { self.pipelineLock.unlock() }
        if self._oscilloscopePipeline == nil {
            self._oscilloscopePipeline = self.makePipeline(vertex: "oscilloscopeLineVertex", fragment: "oscilloscopeLineFragment")
        }
        return self._oscilloscopePipeline
    }

    var fullscreenPipeline: MTLRenderPipelineState? {
        self.pipelineLock.lock()
        defer { self.pipelineLock.unlock() }
        if self._fullscreenPipeline == nil {
            self._fullscreenPipeline = self.makePipeline(vertex: "fullscreenVertex", fragment: "fullscreenFragment")
        }
        return self._fullscreenPipeline
    }

    var copyPipeline: MTLRenderPipelineState? {
        self.pipelineLock.lock()
        defer { self.pipelineLock.unlock() }
        if self._copyPipeline == nil {
            self._copyPipeline = self.makePipeline(vertex: "fullscreenVertex", fragment: "copyFragment")
        }
        return self._copyPipeline
    }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        self.library = library
    }

    func makeOffscreenTexture(width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return self.device.makeTexture(descriptor: descriptor)
    }

    private func makePipeline(vertex: String, fragment: String) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment)
        else {
            visualizationLogger.error(
                "Missing Metal function(s) for pipeline (vertex: \(vertex, privacy: .public), fragment: \(fragment, privacy: .public)); visualizer will skip this pass."
            )
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            return try self.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            // A nil pipeline makes the visualizer silently skip frames; surface the reason so a
            // bad shader is diagnosable instead of just showing a black panel.
            visualizationLogger.error(
                "Failed to compile pipeline (vertex: \(vertex, privacy: .public), fragment: \(fragment, privacy: .public)): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
