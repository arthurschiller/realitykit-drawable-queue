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
    case celebrate
    case dogeGIF
    case heartEyes
    case ninetiesGIF
    case waitingGIF
    case wow
    
    
    var imageName: String {
        switch self {
        case .celebrate:
            return "celebrate"
        case .dogeGIF:
            return "doge"
        case .heartEyes:
            return "heart-eyes"
        case .ninetiesGIF:
            return "90s"
        case .waitingGIF:
            return "waiting"
        case .wow:
            return "wow"
        }
    }
    
    var imageExtension: String {
        return "gif"
    }
}

struct CustomDrawableData {
    let drawableTextureManager: DrawableTextureManager
    let defaultCustomMaterial: CustomMaterial
    let customDrawableMaterial: CustomMaterial
    let textureCGImage: CGImage
}

class ViewController: UIViewController {
    
    var currentImageKind: ImageKind?
    
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
    
    var drawableDataForImageKind: [ImageKind: CustomDrawableData] = [:]
    
    var drawableTextureManagers: [DrawableTextureManager] {
        return drawableDataForImageKind
            .compactMapValues({ $0 })
            .map { $0.value.drawableTextureManager }
    }
    
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
    
    private var showNonCustomDrawableEntity: Bool = false
    
    init() {
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
            self?.drawableTextureManagers.forEach {
                $0.update(withDeltaTime: event.deltaTime)
            }
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
        addObjects()
        
        addContentHintLabel.isHidden = true
        
        if showNonCustomDrawableEntity {
            explanationLabel.isHidden = false
        }
    }
}

private extension ViewController {
    func makeHintLabel() -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOffset = CGSize(width: 0, height: 2)
        label.layer.shadowRadius = 1
        label.layer.shadowOpacity = 0.3
        return label
    }
    
    func getRandomImageKind() -> ImageKind {
        guard
            let randomImageKind = ImageKind.allCases.randomElement()
        else {
            return .dogeGIF
        }
        
        if randomImageKind == currentImageKind {
            return getRandomImageKind()
        }
        
        return randomImageKind
    }
    
    func getDrawableData(forImageKind imageKind: ImageKind) -> CustomDrawableData {
        if let existingData = drawableDataForImageKind[imageKind] {
            return existingData
        }
        
        let textureCGImage: CGImage = {
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
        
        let drawableTextureManager: DrawableTextureManager = {
            guard
                let textureResource = try? TextureResource.generate(from: textureCGImage, withName: nil, options: .init(semantic: .color))
            else {
                fatalError("DrawableTextureManager could not be instantiated")
            }
            
            return DrawableTextureManager(
                arView: arView,
                initialTextureResource: textureResource,
                imageName: imageKind.imageName,
                imageExtension: imageKind.imageExtension,
                mtlDevice: mtlDevice
            )
        }()
        
        let defaultCustomMaterial: CustomMaterial = {
            guard
                let textureResource = try? TextureResource.generate(from: textureCGImage, withName: nil, options: .init(semantic: .color))
            else {
                fatalError("Texture could not be instantiated")
            }
            
            return makeCustomMaterial(textureResource: textureResource)
        }()
        
        let customDrawableMaterial: CustomMaterial = {
            return makeCustomMaterial(textureResource: drawableTextureManager.textureResource)
        }()
        
        let data = CustomDrawableData(
            drawableTextureManager: drawableTextureManager,
            defaultCustomMaterial: defaultCustomMaterial,
            customDrawableMaterial: customDrawableMaterial,
            textureCGImage: textureCGImage
        )
        
        drawableDataForImageKind[imageKind] = data
        return data
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
        width: Float = 0.3
    ) {
        let randomImageKind = getRandomImageKind()
        let drawableData = getDrawableData(forImageKind: randomImageKind)
        let aspectRatio = Float(drawableData.textureCGImage.height) / Float(drawableData.textureCGImage.width)
        
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
        
        if showNonCustomDrawableEntity {
            let offset: Float = 0.01
            
            // add first plane
            addPlane(
                xOffset: 0,
                yOffset: -height / 2 - offset,
                material: drawableData.defaultCustomMaterial
            )
            
            // add second plane
            addPlane(
                xOffset: 0,
                yOffset: height / 2 + offset,
                material: drawableData.customDrawableMaterial
            )
        } else {
            // add second plane
            addPlane(
                xOffset: 0,
                yOffset: 0,
                material: drawableData.customDrawableMaterial
            )
        }
        
        currentImageKind = randomImageKind
    }
}
