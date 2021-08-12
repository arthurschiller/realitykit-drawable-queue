//
//  ViewController.swift
//  RealityKit Drawable Queue
//
//  Created by Arthur Schiller on 12.08.21.
//

import UIKit
import RealityKit
import ARKit

enum ImageKind: CaseIterable {
    case ninetiesGIF
    case dogeGIF
    case waitingGIF
    
    var imageName: String {
        switch self {
        case .ninetiesGIF:
            return "90s"
        case .dogeGIF:
            return "doge"
        case .waitingGIF:
            return "waiting"
        }
    }
    
    var imageExtension: String {
        return "gif"
    }
}

class ViewController: UIViewController {
    
    let imageKind: ImageKind
    
    lazy var arView: CustomARView = {
        let view = CustomARView(
            frame: UIScreen.main.bounds,
            cameraMode: .ar,
            automaticallyConfigureSession: false
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
            initialTextureResource: textureResource,
            imageName: imageKind.imageName,
            imageExtension: imageKind.imageExtension,
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
            let url = Bundle.main.url(
                forResource: imageKind.imageName,
                withExtension: imageKind.imageExtension
            ),
            let texture = UIImage(contentsOfFile: url.path)?.cgImage
        else {
            fatalError("Texture could not be instantiated")
        }
        
        return texture
    }()
    
    lazy var addContentHintLabel: UILabel = {
        let label = makeHintLabel()
        label.font = UIFont.boldSystemFont(ofSize: 18)
        label.text = "Tap anywhere\nto add objects"
        return label
    }()
    
    lazy var explanationLabel: UILabel = {
        let label = makeHintLabel()
        label.font = UIFont.boldSystemFont(ofSize: 18)
        label.text = "The upper object uses DrawableQueue, the bottom one a static texture resource."
        return label
    }()
    
    init() {
        guard let imageKind = ImageKind.allCases.randomElement() else {
            fatalError("Image kind missing.")
        }
        self.imageKind = imageKind
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = arView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        arView.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(viewWasTapped(sender:)))
        )

        arView.onUpdate = { [weak self] event in
            self?.drawableTextureManager?.update(withDeltaTime: event.deltaTime)
        }
        
        [addContentHintLabel, explanationLabel].forEach {
            $0.isHidden = true
            view.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            addContentHintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            addContentHintLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            explanationLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -24),
            explanationLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 24),
            explanationLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        arView.session.run(configuration, options: [])
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        addContentHintLabel.isHidden = false
        
        //arView.debugOptions.insert(.showStatistics)
    }
    
    @objc private func viewWasTapped(sender: UITapGestureRecognizer) {
        let aspectRatio = Float(textureCGImage.height) / Float(textureCGImage.width)
        addObjects(aspectRatio: aspectRatio)
        
        addContentHintLabel.isHidden = true
        explanationLabel.isHidden = false
    }
}

private extension ViewController {
    func makeHintLabel() -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOffset = CGSize(width: 0, height: 2)
        label.layer.shadowRadius = 1
        label.layer.shadowOpacity = 0.3
        return label
    }
    
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
            customMaterial.faceCulling = .none
            
            return customMaterial
        } catch {
            fatalError("CustomMaterial could not be created: \(error)")
        }
    }
    
    func addObjects(
        atDistance distance: Float = 0.75,
        width: Float = 0.3,
        aspectRatio: Float
    ) {
        let cameraTransform = arView.cameraTransform.matrix
        let height = width * aspectRatio
        
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
