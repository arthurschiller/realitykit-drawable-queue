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

private func < <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

private struct AnimatedImageData {
    struct FrameData {
        let texture: MTLTexture
        let delay: TimeInterval
    }
    
    let frames: [FrameData]
}

public class DrawableTextureManager {
    
    public let textureResource: TextureResource
    public let mtlDevice: MTLDevice
    public let imageName: String
    public let imageExtension: String
    
    public weak var arView: ARView?
    
    public lazy var drawableQueue: TextureResource.DrawableQueue = {

        // can be whatever you like – 200 × 200 for most GIFs is probably enough
        let descriptor = TextureResource.DrawableQueue.Descriptor(
            pixelFormat: .rgba8Unorm,
            width: 200,
            height: 200,
            usage: [.renderTarget, .shaderRead, .shaderWrite],
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
    
    private lazy var commandQueue: MTLCommandQueue? = {
        return mtlDevice.makeCommandQueue()
    }()
    
    private var renderPipelineState: MTLRenderPipelineState?
    private var imagePlaneVertexBuffer: MTLBuffer?
    private var animatedImageData: AnimatedImageData?
    
    private var indexOfCurrentFrame: Int = 0
    private var elapsedTime: TimeInterval = 0
    private var timeStampForNextFrame: TimeInterval?
    
    private lazy var textureLoader = MTKTextureLoader(device: mtlDevice)
    
    private func initializeRenderPipelineState() {
        guard
            let library = mtlDevice.makeDefaultLibrary()
        else {
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        
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
        initialTextureResource: TextureResource,
        imageName: String,
        imageExtension: String,
        mtlDevice: MTLDevice
    ) {
        self.arView = arView
        self.textureResource = initialTextureResource
        self.imageName = imageName
        self.imageExtension = imageExtension
        self.mtlDevice = mtlDevice
        commonInit()
    }
    
    private func loadTextureData() {
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            autoreleasepool {
                guard
                    let self = self,
                    let url = Bundle.main.url(
                        forResource: self.imageName, withExtension: self.imageExtension),
                    let gifData = self.animatedGIF(fromURL: url)
                else {
                    fatalError("Image Data could not be loaded")
                }
                
                print("Loaded gif data!")
                DispatchQueue.main.async {
                    self.animatedImageData = gifData
                    
                    // reset timestamp in index of current frame
                    self.indexOfCurrentFrame = 0
                    self.elapsedTime = 0
                }
            }
        }
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
        loadTextureData()
    }
}

public extension DrawableTextureManager {
    func update(withDeltaTime deltaTime: TimeInterval) {
        elapsedTime += deltaTime
        
        guard
            let animatedImageData = animatedImageData
        else {
            return
        }
        
        func bumpIndexOfCurrentFrame() {
            indexOfCurrentFrame += 1
            
            if indexOfCurrentFrame >= animatedImageData.frames.count {
                indexOfCurrentFrame = 0
            }
        }
        
        func drawFrameAndAssignNextTimeStamp() {
            drawFrameAtCurrentIndex()
            bumpIndexOfCurrentFrame()
            
            let delayForNextFrame = animatedImageData.frames[indexOfCurrentFrame].delay
            timeStampForNextFrame = elapsedTime + delayForNextFrame
        }
        
        if timeStampForNextFrame == nil {
            drawFrameAndAssignNextTimeStamp()
            return
        }
        
        guard
            let nextTimeStamp = timeStampForNextFrame,
            elapsedTime >= nextTimeStamp
        else {
            return
        }
        
        print("Draw next frame with index: \(indexOfCurrentFrame) at time: \(nextTimeStamp)")
        drawFrameAndAssignNextTimeStamp()
    }
    
    func drawFrameAtCurrentIndex() {
        guard
            let animatedImageData = animatedImageData,
            animatedImageData.frames.indices.contains(indexOfCurrentFrame),
            let drawable = try? drawableQueue.nextDrawable(),
            let commandBuffer = commandQueue?.makeCommandBuffer(),
            let renderPipelineState = renderPipelineState
        else {
            return
        }
        
        let currentFrame = animatedImageData.frames[indexOfCurrentFrame]

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
        renderEncoder.setFragmentTexture(currentFrame.texture, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        drawable.present()
    }
}

private extension DrawableTextureManager {
    func animatedGIF(fromURL url: URL) -> AnimatedImageData? {
        guard
            let data = try? Data(contentsOf: url) as CFData,
            let imageSource = CGImageSourceCreateWithData(data, nil)
        else {
            print("Source for the image does not exist")
            return nil
        }
        
        let frameCount = CGImageSourceGetCount(imageSource)
        var delays: [TimeInterval] = []
        var textures: [MTLTexture] = []
        
        for index in 0..<frameCount {
            guard
                let cgImage = CGImageSourceCreateImageAtIndex(imageSource, index, nil),
                let mtlTexture = try? textureLoader.newTexture(cgImage: cgImage)
            else {
                continue
            }
            
            let delayInSeconds = delayForImage(atIndex: index, source: imageSource)
            
            textures.append(mtlTexture)
            delays.append(delayInSeconds) // Seconds to ms
        }
        
        // Calculate full duration
        let duration: TimeInterval = {
            var sum: TimeInterval = 0

            for delay in delays {
                sum += delay
            }
            
            return sum
        }()
        
        print("Full duration: \(duration)")
        
        var frames: [AnimatedImageData.FrameData] = []
        
        for (texture, delay) in zip(textures, delays) {
            frames.append(AnimatedImageData.FrameData(texture: texture, delay: delay))
        }
        
        print("Frame data: \(frames)")

        return AnimatedImageData(frames: frames)
        
        // may use later
        // let timePerTexture = Double(duration) / 1000.0 / Double(count)
    }

    // most of the following functions are taken from various iOS code samples that demonstrate how to receive the individual frames of a GIF e.g: https://github.com/kiritmodi2702/GIF-Swift/blob/master/GIF-Swift/iOSDevCenters%2BGIF.swift – there might a better way to do this though
    
    func delayForImage(atIndex index: Int, source: CGImageSource) -> TimeInterval {
        let defaultDelay: TimeInterval = 0.05
        var delay = defaultDelay
        
        let cfProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
        let gifProperties: CFDictionary = unsafeBitCast(
            CFDictionaryGetValue(
                cfProperties,
                Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque()
            ),
            to: CFDictionary.self
        )
        
        var delayObject: AnyObject = unsafeBitCast(
            CFDictionaryGetValue(
                gifProperties,
                Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()
            ),
            to: AnyObject.self
        )
        
        if delayObject.doubleValue == 0 {
            delayObject = unsafeBitCast(
                CFDictionaryGetValue(
                    gifProperties,
                    Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()),
                to: AnyObject.self
            )
        }
        
        if let doubleDelayObject = delayObject as? TimeInterval {
            delay = doubleDelayObject
        }
        
        if delay < defaultDelay {
            delay = defaultDelay
        }
        
        return delay
    }
    
    func gcdForPair(_ a: Int?, _ b: Int?) -> Int {
        var a = a
        var b = b
        if b == nil || a == nil {
            if b != nil {
                return b!
            } else if a != nil {
                return a!
            } else {
                return 0
            }
        }
        
        if a < b {
            let c = a
            a = b
            b = c
        }
        
        var rest: Int
        while true {
            rest = a! % b!
            
            if rest == 0 {
                return b!
            } else {
                a = b
                b = rest
            }
        }
    }
    
    func gcdForArray(_ array: [Int]) -> Int {
        if array.isEmpty {
            return 1
        }
        
        var gcd = array[0]
        
        for val in array {
            gcd = gcdForPair(val, gcd)
        }
        
        return gcd
    }
}
