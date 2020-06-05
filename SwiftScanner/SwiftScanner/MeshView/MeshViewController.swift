//
//  MeshViewController.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 03/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation
import MessageUI
import os.log

open class MeshViewController: UIViewController, UIGestureRecognizerDelegate {
    
    weak var scanView : ScanViewDelegate?
    weak var scanBuffer : ScanBufferDelegate?
    weak var colorizer : ColorizeDelegate?
    
    // force the view to redraw.
    var needsDisplay: Bool = false
    var colorEnabled: Bool = false
    fileprivate var _mesh: STMesh? = nil

    deinit {
        os_log(.debug, log: OSLog.meshView, "MeshViewController deinit called")
    }
    
    var mesh: STMesh? {
        get {
            return _mesh
        }
        set {
            
            if let _ = _mesh {
                os_log(.debug, log: OSLog.meshView, "cleaned up the mesh")
                _mesh = nil
            }
            
            _mesh = newValue
            
            if _mesh != nil {
                
                os_log(.debug, log: OSLog.meshView, "Setting the mesh")
                
                self.renderer!.uploadMesh(_mesh!)
                
                self.trySwitchToColorRenderingMode()
                
                self.needsDisplay = true
            }
        }
    }
    
    var projectionMatrix: GLKMatrix4 = GLKMatrix4Identity
    {
        didSet {
            setCameraProjectionMatrix(projectionMatrix)
        }
    }
    
    var volumeCenter = GLKVector3Make(0,0,0)
    {
        didSet {
            resetMeshCenter(volumeCenter)
        }
    }
    
    @IBOutlet weak var eview: EAGLView!
    @IBOutlet weak var meshViewerMessageLabel: UILabel!
    
    var displayLink: CADisplayLink?
    var renderer: MeshRenderer!
    var viewpointController: ViewpointController!
    var viewport = [GLfloat](repeating: 0, count: 4)
    var modelViewMatrixBeforeUserInteractions: GLKMatrix4?
    var projectionMatrixBeforeUserInteractions: GLKMatrix4?
        
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

    }

    override open func viewDidLoad() {
        
        super.viewDidLoad()

        renderer = MeshRenderer.init()
        
        viewpointController = ViewpointController.init(screenSizeX: Float(self.view.frame.size.width), screenSizeY: Float(self.view.frame.size.height))
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if displayLink != nil {
            displayLink!.invalidate()
            displayLink = nil
        }
        
        displayLink = CADisplayLink(target: self, selector: #selector(MeshViewController.draw))
        displayLink!.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        
        viewpointController.reset()
        viewpointController.initRotation(xAngleDegrees: InitialViewModelRotation.xAngleDegrees, yAngleDegrees: InitialViewModelRotation.yAngleDegrees)
    }
    
    // Make sure the status bar is disabled (iOS 7+)
    override open var prefersStatusBarHidden : Bool {
        return true
    }

    override open func didReceiveMemoryWarning () {
        
    }
    
    func setupGL (_ context: EAGLContext) {

        (self.view as! EAGLView).context = context

        EAGLContext.setCurrent(context)

        renderer.initializeGL( GLenum(GL_TEXTURE3))

        self.eview.setFramebuffer()
        
        let framebufferSize: CGSize = self.eview.getFramebufferSize()
        
        // The iPad's diplay conveniently has a 4:3 aspect ratio just like our video feed.
        // Some iOS devices need to render to only a portion of the screen so that we don't distort
        // our RGB image. Alternatively, you could enlarge the viewport (losing visual information),
        // but fill the whole screen.
        
        // if you want to keep aspect ratio
        //        var imageAspectRatio: CGFloat = 1
        //
        //        if abs(framebufferSize.width / framebufferSize.height - 640.0 / 480.0) > 1e-3 {
        //            imageAspectRatio = 480.0 / 640.0
        //        }
        //
        //        viewport[0] = Float(framebufferSize.width - framebufferSize.width * imageAspectRatio) / 2
        //        viewport[1] = 0
        //        viewport[2] = Float(framebufferSize.width * imageAspectRatio)
        //        viewport[3] = Float(framebufferSize.height)
        
        // if you want full screen
        viewport[0] = 0
        viewport[1] = 0
        viewport[2] = Float(framebufferSize.width)
        viewport[3] = Float(framebufferSize.height)
    }
    
    private func cleanup() {
        
        self.colorizer?.stopColorizing()
                
        renderer.releaseGLBuffers()
        renderer.releaseGLTextures()
        renderer = nil
        
        viewpointController = nil
        
        displayLink!.invalidate()
        displayLink = nil
        
        mesh = nil

        self.eview.context = nil

        os_log(.debug, log: OSLog.meshView, "Mesh view dismissed")
}
    
    //MARK: - MeshViewer setup when loading the mesh
    
    func setCameraProjectionMatrix (_ projection: GLKMatrix4) {

        viewpointController.setCameraProjection(projection)
        projectionMatrixBeforeUserInteractions = projection
    }
    
    func resetMeshCenter (_ center: GLKVector3) {

        viewpointController.reset()
        viewpointController.initRotation(xAngleDegrees: InitialViewModelRotation.xAngleDegrees, yAngleDegrees: InitialViewModelRotation.yAngleDegrees)
        viewpointController.setMeshCenter(center)
        modelViewMatrixBeforeUserInteractions = viewpointController.currentGLModelViewMatrix()
    }

    //MARK: Rendering
    
    @objc func draw () {
        
        self.eview.setFramebuffer()
        
        glViewport(GLint(viewport[0]), GLint(viewport[1]), GLint(viewport[2]), GLint(viewport[3]))
        
        let viewpointChanged = viewpointController.update()
        
        // If nothing changed, do not waste time and resources rendering.
        if !needsDisplay && !viewpointChanged {
            return
        }
        
        var currentModelView = viewpointController.currentGLModelViewMatrix()
        var currentProjection = viewpointController.currentGLProjectionMatrix()
        
        renderer!.clear()
        
        withUnsafePointer(to: &currentProjection) { (one) -> () in
            withUnsafePointer(to: &currentModelView, { (two) -> () in
                
                one.withMemoryRebound(to: GLfloat.self, capacity: 16, { (onePtr) -> () in
                    two.withMemoryRebound(to: GLfloat.self, capacity: 16, { (twoPtr) -> () in
                        
                        renderer!.render(onePtr,modelViewMatrix: twoPtr)
                    })
                })
            })
        }
        
        needsDisplay = false
        
        let _ = self.eview.presentFramebuffer()

    }
    
    //MARK: Touch & Gesture Control
    
    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            viewpointController.onTouchBegan()
        }
    }
    
    @IBAction func pinchScaleGesture(_ sender: UIPinchGestureRecognizer) {

        // Forward to the ViewpointController.
        if sender.state == .began {
            viewpointController.onPinchGestureBegan(Float(sender.scale))
        }
        else if sender.state == .changed {
            viewpointController.onPinchGestureChanged(Float(sender.scale))
        }
    }
    
    @IBAction func oneFingerPanGesture(_ sender: UIPanGestureRecognizer) {

        let touchPos = sender.location(in: view)
        let touchVel = sender.velocity(in: view)
        let touchPosVec = GLKVector2Make(Float(touchPos.x), Float(touchPos.y))
        let touchVelVec = GLKVector2Make(Float(touchVel.x), Float(touchVel.y))
        
        if sender.state == .began {
            viewpointController.onOneFingerPanBegan(touchPosVec)
        }
        else if sender.state == .changed {
            viewpointController.onOneFingerPanChanged(touchPosVec)
        }
        else if sender.state == .ended {
            viewpointController.onOneFingerPanEnded(touchVelVec)
        }
    }

    @IBAction func twoFingersPanGesture(_ sender: AnyObject) {

        if sender.numberOfTouches != 2 {
            return
        }
        
        let touchPos = sender.location(in: view)
        let touchVel = sender.velocity(in: view)
        let touchPosVec = GLKVector2Make(Float(touchPos.x), Float(touchPos.y))
        let touchVelVec = GLKVector2Make(Float(touchVel.x), Float(touchVel.y))
        
        if sender.state == .began {
            viewpointController.onTwoFingersPanBegan(touchPosVec)
        }
        else if sender.state == .changed {
            viewpointController.onTwoFingersPanChanged(touchPosVec)
        }
        else if sender.state == .ended {
            viewpointController.onTwoFingersPanEnded(touchVelVec)
        }
    }
    
    @IBAction func resetView(_ sender: UIButton) {
        viewpointController.resetView()
    }
    
    //MARK: UI Control
    
    private func trySwitchToColorRenderingMode() {
   
        // Choose the best available color render mode, falling back to LightedGray
        // This method may be called when colorize operations complete, and will
        // switch the render mode to color, as long as the user has not changed
        // the selector.
        
        if    mesh!.hasPerVertexUVTextureCoords() {
            
            os_log(.info, log: OSLog.meshView, "Setting rendermode textured")
            renderer.setRenderingMode(.textured)
        }
        else if mesh!.hasPerVertexColors() {
            
            os_log(.info, log: OSLog.meshView, "Setting rendermode per vertex color")
            renderer.setRenderingMode(.perVertexColor)
        }
        else {
            
            os_log(.info, log: OSLog.meshView, "Setting rendermode lighted gray")
            renderer.setRenderingMode(.lightedGray)
        }
    }
    
    internal func showColorRenderingMode() {
        
        os_log(.debug, log: OSLog.meshView, "ShowColorRenderingMode")
        
        trySwitchToColorRenderingMode()
        
        let meshIsColorized: Bool = mesh!.hasPerVertexColors() || mesh!.hasPerVertexUVTextureCoords()
        
        os_log(.debug, log: OSLog.meshView, "Mesh is colorized = %{Public}@", String(describing: meshIsColorized))
        
        if !meshIsColorized {
            
            colorizeMesh()
        }
    }
    
    func colorizeMesh() {
        os_log(.debug, log: OSLog.meshView, "Colorizing Mesh")
        
        let previewHandler = {
            os_log(.debug, log: OSLog.meshView, "Colorizing mesh - preview")
        }
        
        let completionHandler = { [weak self] in
            os_log(.debug, log: OSLog.meshView, "Colorizing mesh - enhanced")
            // Hide progress bar.
            self?.hideMeshViewerMessage()
        }
        
        let _ = self.colorizer?.meshViewDidRequestColorizing(self.mesh!,
                                                       previewCompletionHandler: previewHandler,
                                                       enhancedCompletionHandler: completionHandler)
    }
        
    func hideMeshViewerMessage() {
        
        UIView.animate(withDuration: 0.5, animations: {
            self.meshViewerMessageLabel.alpha = 0.0
            }, completion: { _ in
                self.meshViewerMessageLabel.isHidden = true
        })
    }
    
    func showMeshViewerMessage(_ msg: String) {
        
        meshViewerMessageLabel.text = msg
        
        if meshViewerMessageLabel.isHidden == true {
            
            meshViewerMessageLabel.alpha = 0.0
            meshViewerMessageLabel.isHidden = false
            
            UIView.animate(withDuration: 0.5, animations: {
                self.meshViewerMessageLabel.alpha = 1.0
            })
        }
    }
    
    //MARK: Navigation
    open override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        switch segue.identifier ?? "" {
        case "unwindMeshToScanView":
            os_log("Preparing for unwindMeshToScanView", log: OSLog.meshView, type: .debug)
            self.cleanup()
                            
        case "unwindMeshToMainView":
            os_log("Preparing for unwindMeshToMainView", log: OSLog.meshView, type: .debug)
            if let mesh = self.mesh {
                self.scanBuffer?.addScan(mesh)
            }
            self.cleanup()
            self.scanView?.cleanup()            

        default:
            return
        }

    }
}

