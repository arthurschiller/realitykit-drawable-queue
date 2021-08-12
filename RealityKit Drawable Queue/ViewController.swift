//
//  ViewController.swift
//  RealityKit Drawable Queue
//
//  Created by Arthur Schiller on 12.08.21.
//

import UIKit
import RealityKit

class ViewController: UIViewController {
    
    lazy var arView: CustomARView = {
        let view = CustomARView(
            frame: UIScreen.main.bounds,
            cameraMode: .ar,
            automaticallyConfigureSession: true
        )
        return view
    }()
    
    lazy var mtlDevice: MTLDevice = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError()
        }
        return device
    }()
    
    lazy var drawableTextureManager: DrawableTextureManager? = {
        guard
            let textureResource = try? TextureResource.generate(from: textureCGImage, withName: nil, options: .init(semantic: .color))
        else {
            return nil
        }
        
        return DrawableTextureManager(
            arView: arView,
            textureResource: textureResource,
            mtlDevice: mtlDevice
        )
    }()
    
    lazy var defaultCustomMaterial: CustomMaterial = {
        guard
            let textureResource = try? TextureResource.generate(from: textureCGImage, withName: nil, options: .init(semantic: .color))
        else {
            fatalError("Texture could not be instantiated")
        }
        
        return makeCustomMaterial(textureResource: textureResource)
    }()
    
    lazy var customDrawableMaterial: CustomMaterial = {
        guard let textureResource = drawableTextureManager?.textureResource else {
            fatalError("Texture missing")
        }
        
        return makeCustomMaterial(textureResource: textureResource)
    }()
    
    lazy var textureCGImage: CGImage = {
        guard
            let url = Bundle.main.url(forResource: "cat", withExtension: "jpg"),
            let texture = UIImage(contentsOfFile: url.path)?.cgImage
        else {
            fatalError("Texture could not be instantiated")
        }
        
        return texture
    }()
    
    lazy var hintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.boldSystemFont(ofSize: 18)
        label.numberOfLines = 0
        label.text = "Tap anywhere\nto add objects"
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOffset = CGSize(width: 0, height: 2)
        label.layer.shadowRadius = 1
        label.layer.shadowOpacity = 0.3
        return label
    }()
    
    override func loadView() {
        view = arView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        arView.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(viewWasTapped(sender:)))
        )

        arView.onUpdate = { [weak self] arScene in
            self?.drawableTextureManager?.update()
        }
        
        hintLabel.isHidden = true
        view.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        hintLabel.isHidden = false
        
        arView.enablePeopleOcclusion()
        //arView.debugOptions.insert(.showStatistics)
    }
    
    @objc private func viewWasTapped(sender: UITapGestureRecognizer) {
        addObjects()
        hintLabel.isHidden = true
    }
}

private extension ViewController {
     func makeCustomMaterial(textureResource: TextureResource) -> CustomMaterial {
        let surfaceShader = CustomMaterial.SurfaceShader(
            named: "customMaterialSurfaceModifier",
            in: CustomARView.mtlLibrary
        )
        
        do {
            var customMaterial = try CustomMaterial(
                surfaceShader: surfaceShader,
                geometryModifier: nil,
                lightingModel: .unlit
            )
            customMaterial.custom.texture = .init(textureResource)
            
            return customMaterial
        } catch {
            fatalError("CustomMaterial could not be created: \(error)")
        }
    }
    
    func addObjects(
        atDistance distance: Float = 0.75,
        width: Float = 0.3,
        height: Float = 0.22
    ) {
        let cameraTransform = arView.cameraTransform.matrix

        func addPlane(xOffset: Float, yOffset: Float, material: Material) {
            var offset = matrix_identity_float4x4
            offset.columns.3.z = -distance
            offset.columns.3.x = xOffset
            offset.columns.3.y = yOffset
            let finalTransform = simd_mul(cameraTransform, offset)
            
            let entity = ModelEntity(mesh: .generatePlane(width: width, height: height))
            entity.model?.materials = [material]
            let anchorEntity = AnchorEntity(world: finalTransform)
            anchorEntity.addChild(entity)
            arView.scene.addAnchor(anchorEntity)
        }
        
        let offset: Float = 0.01
        
        // add first plane
        addPlane(
            xOffset: 0,
            yOffset: -height / 2 - offset,
            material: defaultCustomMaterial
        )
        
        // add second plane
        addPlane(
            xOffset: 0,
            yOffset: height / 2 + offset,
            material: customDrawableMaterial
        )
    }
}
