//
//  DrawableTextureManager.swift
//  DrawableTextureManager
//
//  Created by Arthur Schiller on 12.08.21.
//

import RealityKit
import ARKit
import MetalKit
import AVFoundation

public class DrawableTextureManager {
    
    public let textureResource: TextureResource
    public let mtlDevice: MTLDevice
    
    public weak var arView: ARView?
    
    public lazy var drawableQueue: TextureResource.DrawableQueue = {
        
        #warning("If the usage below is set to anything other than .none you need to disable Metal API Validation in the projects Scheme Settings – otherwise you will get a warning similar to: Texture at colorAttachment[0] has usage (0x02) which doesn't specify MTLTextureUsageRenderTarget (0x04) in Xcode 13 Beta")

        let descriptor = TextureResource.DrawableQueue.Descriptor(
            pixelFormat: .rgba8Unorm,
            width: 800,
            height: 800,
            usage: .shaderWrite,
            mipmapsMode: .none
        )
        
        do {
            let queue = try TextureResource.DrawableQueue(descriptor)
            queue.allowsNextDrawableTimeout = true
            return queue
        } catch {
            fatalError("Could not create DrawableQueue: \(error)")
        }
    }()
    
    public lazy var commandQueue: MTLCommandQueue? = {
        return mtlDevice.makeCommandQueue()
    }()
    
    public var renderPipelineState: MTLRenderPipelineState?
    private var imagePlaneVertexBuffer: MTLBuffer!
    private lazy var textureLoader = MTKTextureLoader(device: mtlDevice)
    
    private func initializeRenderPipelineState() {
        guard
            let library = mtlDevice.makeDefaultLibrary()
        else {
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
//        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
        
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = 0
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = 0
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        /**
         *  Vertex function to map the texture to the view controller's view
         */
        //pipelineDescriptor.vertexFunction = library.makeFunction(name: "mapTexture")
        pipelineDescriptor.vertexFunction = library.makeFunction(
            name: "drawableQueueVertexShader"
        )
        
        /**
         *  Fragment function to display texture's pixels in the area bounded by vertices of `mapTexture` shader
         */
        pipelineDescriptor.fragmentFunction = library.makeFunction(
            name: "drawableQueueFragmentShader"
        )
        
        pipelineDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        
        do {
            try renderPipelineState = mtlDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            assertionFailure("Failed creating a render state pipeline. Can't render the texture without one. Error: \(error)")
            return
        }
    }

    private let planeVertexData: [Float] = [
        -1, -1,  0,  1,
         1, -1,  1,  1,
         -1,  1,  0,  0,
         1,  1,  1,  0
    ]
    
    public init(
        arView: ARView,
        textureResource: TextureResource,
        mtlDevice: MTLDevice
    ) {
        self.arView = arView
        self.textureResource = textureResource
        self.mtlDevice = mtlDevice
        commonInit()
    }
    
    private func commonInit() {
        textureResource.replace(withDrawables: self.drawableQueue)
        
        let imagePlaneVertexDataCount = planeVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = mtlDevice.makeBuffer(
            bytes: planeVertexData,
            length: imagePlaneVertexDataCount,
            options: []
        )
        
        initializeRenderPipelineState()
    }
}

public extension DrawableTextureManager {
    func update() {
        guard
            let url = Bundle.main.url(forResource: "cat", withExtension: "jpg"),
            let cgImage = UIImage(contentsOfFile: url.path)?.cgImage,
            let texture = try? textureLoader.newTexture(cgImage: cgImage)
        else {
            fatalError()
        }
        
        guard
            let drawable = try? drawableQueue.nextDrawable(),
            let commandBuffer = commandQueue?.makeCommandBuffer(),
            let renderPipelineState = renderPipelineState
        else {
            return
        }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .load
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.renderTargetHeight = textureResource.width
        renderPassDescriptor.renderTargetWidth = textureResource.height
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawCapturedImage")
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        drawable.present()
    }
}
