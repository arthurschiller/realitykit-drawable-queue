//
//  CustomARView.swift
//  CustomARView
//
//  Created by Arthur Schiller on 12.08.21.
//

import Foundation
import RealityKit
import ARKit
import Combine
import CoreImage.CIFilterBuiltins

public class CustomARView: ARView {
    
    private var updateCancellable: Cancellable?
    
    public var onUpdate: ((SceneEvents.Update) -> Void)?
    
    public static var mtlLibrary: MTLLibrary = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let library = device.makeDefaultLibrary()
        else {
            fatalError()
        }
        return library
    }()
    
    public override init(
        frame frameRect: CGRect,
        cameraMode: ARView.CameraMode,
        automaticallyConfigureSession: Bool
    ) {
        super.init(frame: frameRect, cameraMode: cameraMode, automaticallyConfigureSession: automaticallyConfigureSession)
        
        updateCancellable = scene.subscribe(to: SceneEvents.Update.self, on: nil, { [weak self] event in
            self?.onUpdate?(event)
        })
    }
    
    @MainActor @objc required dynamic init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @MainActor @objc required dynamic init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
}
