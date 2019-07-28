import UIKit
import SceneKit
import ARKit

var meters: CGFloat = 0

class ViewController: UIViewController {

    // MARK: - Outlets
    @IBOutlet var sceneView: ARSCNView!
    
    @IBOutlet var undoButtonOutlet: UIButton!
    
    @IBOutlet var redoButtonOutlet: UIButton!
    
    // MARK: - Types
    enum ObjectPlacementMode {
        case freeform
        case plane
        case image
    }
    
    // MARK: - Properties
    let configuration = ARWorldTrackingConfiguration()
    var selectedNode: SCNNode?
    var objectMode: ObjectPlacementMode = .freeform {
        didSet {
            reloadConfiguration()
        }
    }
    
    var lastObjectPlacedPosition: SCNVector3?
    let distanceThreshold: Float = 0.05
    // для удобства создаем пустые массивы нод (размещенных нод и нод размещенных на плэйнах):

    
    var placedNodes = [SCNNode]() {
        didSet {
            appearUndoRedo()
            guard let lastElement = redoNodeIndexArray.last else { return }
            for node in placedNodes where node.isHidden && node != placedNodes.last {
                node.removeFromParentNode()
                placedNodes.remove(at: lastElement)
                redoButtonOutlet.isHidden = true
                undoButtonTappedCount = 0
                redoNodeIndexArray.removeAll()
            }
            print(redoNodeIndexArray)

        }
    }
    
    var planeNodes = [SCNNode]()
    
    var undoButtonTappedCount = 0
    
    var redoNodeIndexArray: [Int] = []
    var rootNode: SCNNode {
        return sceneView.scene.rootNode
    }
    
    var showPlaneOverlay = false {
        didSet {
            planeNodes.forEach { $0.isHidden = !showPlaneOverlay }
        }
    }
    
    // MARK: - Custom Methods
    
    // для objectMode
    // аргумент функции (removeAnchors: Bool = false) и options добавили позже (когда делали резет)
    func reloadConfiguration(removeAnchors: Bool = false) {
        /* можно было исп-ть switch и указывать включить то или другое,
        но мы хотим чтобы вторая конфигурация с плэйндетекшн была включена всегда
        */
        configuration.detectionImages = (objectMode == .image) ?
            ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) : nil
        
        configuration.planeDetection = [.horizontal]
        
        var options = ARSession.RunOptions()
        
        if removeAnchors {
            // удаляем все существующие якоря - резет (чобы потом программа создавала по-новой)
            options = [.removeExistingAnchors]
            /* до полного удаления всех нод, находим каждую ноду содержащуюся в массиве
              и удаляем каждую ноду из парэнтНод
            */
            (planeNodes + placedNodes).forEach { $0.removeFromParentNode() }
            planeNodes.removeAll()
            placedNodes.removeAll()
        } else {
            options = []
        }
        
        sceneView.session.run(configuration, options: options)
    }
    
    func appearUndoRedo() {
        
        placedNodes.count == redoNodeIndexArray.count ? (undoButtonOutlet.isHidden = true) : (undoButtonOutlet.isHidden = false)

    }

    
    // MARK: - UIViewController Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
        
        undoButtonOutlet.isHidden = true
        undoButtonOutlet.layer.cornerRadius = undoButtonOutlet.frame.height / 2
        redoButtonOutlet.isHidden = true
        redoButtonOutlet.layer.cornerRadius = redoButtonOutlet.frame.height / 2
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfiguration()

    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    // MARK: - Object Placement Methods
    func addNode(_ node: SCNNode, to parentNode: SCNNode) {
        /* клонируем ноду (чтобы нода не просто меняла свое положение
         (если не склонировать ее), а чтобы нода оставляля свой след (получится множество следов ноды при перемещении камеры - рисование нодой)
         */
        let cloneNode = node.clone()
        parentNode.addChildNode(cloneNode)
        placedNodes.append(cloneNode)
    }
    
    func addNode(_ node: SCNNode, at point: CGPoint) {
        guard let result = sceneView.hitTest(point, types: [.existingPlaneUsingExtent]).first else { return }


        let transform = result.worldTransform
        
        let position = SCNVector3(
            transform.columns.3.x,
            transform.columns.3.y + Float(meters) / 2 + 0.01,
            transform.columns.3.z
            
        )
        
        
        /* создаем переменную с максимально возможным числом типа Флоат (Float.greatestFiniteMagnitude)
            это нужно, чтобы в случае, если далее идущий if не выполнится, то идущий за ним
            if distanceThreshold < distance точно выполнился (тк distance точно будет больше
            distanceThreshold)
        */
        var distance = Float.greatestFiniteMagnitude
        
        if let lastPosition = lastObjectPlacedPosition {
            let deltaX = position.x - lastPosition.x
            let deltaY = position.y - lastPosition.y
            let deltaZ = position.z - lastPosition.z
            let sum = deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ
            distance = sqrt(sum)
            //    let distance = sqrtf(powf(deltaX, 2) + powf(deltaY, 2) + powf(deltaZ, 2))
        }
        
        if distanceThreshold < distance {
            node.position = position
            addNode(node, to: rootNode)
            lastObjectPlacedPosition = node.position
        }
    }
    
    func addNodeInFront(_ node: SCNNode) {
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        // получаем данные о позиции и ориентации камеры в реальном мире с помощью transform
        let transform = currentFrame.camera.transform
        var translation = matrix_identity_float4x4
        // отодвигаем по оси Z на минус 20 см (то есть отодвигаем от устройства)
        translation.columns.3.z = -0.2
        // далее трансформируем матрицу, чтобы после изменения положения и ориентации камеры менялись и координаты
        node.simdTransform = matrix_multiply(transform, translation)
        
        addNode(node, to: rootNode)
    }
    
    func createFloor(planeAnchor: ARPlaneAnchor) -> SCNNode {
        let node = SCNNode()
        
        let plane = SCNPlane(
            width: CGFloat(planeAnchor.extent.x),
            /* здесь для высоты указываем ось не Y, а Z - тк так повелось
             (изначально распознаваение поверхностей было только горизонтальным,
              а потом добавилось вертикальное (оси так и оставили как для горизонтальной ориентации)
            */
            height: CGFloat(planeAnchor.extent.z)
        )
        plane.firstMaterial?.diffuse.contents = UIColor.purple
        
        node.geometry = plane
        node.eulerAngles.x = -.pi / 2
        node.opacity = 0.25
        
        return node
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        let floor = createFloor(planeAnchor: anchor)
        floor.isHidden = !showPlaneOverlay
        
        node.addChildNode(floor)
        planeNodes.append(node)
        
        
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor) {
        guard let selectedNode = selectedNode else { return }
        addNode(selectedNode, to: node)

    }
    
    
    // MARK: - Touches
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let node = selectedNode else { return }
        guard let touch = touches.first else { return }
        
        switch objectMode {
            
        case .freeform:
            addNodeInFront(node)
            
        case .plane:
            addNode(node, at: touch.location(in: sceneView))
            
        case .image:
            break
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard let node = selectedNode else { return }
        guard let touch = touches.first else { return }
        guard objectMode == .plane else { return }
        
        let newTouchPoint = touch.location(in: sceneView)
        addNode(node, at: newTouchPoint)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        lastObjectPlacedPosition = nil
    }
    
    // MARK: - Actions
    @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            objectMode = .freeform
            showPlaneOverlay = false
        case 1:
            objectMode = .plane
            showPlaneOverlay = true
        case 2:
            objectMode = .image
            showPlaneOverlay = false
        default:
            break
        }
    }
    
    @IBAction func undoButtonPressed(_ sender: UIButton) {
        
        undoButtonTappedCount += 1
        if undoButtonTappedCount > placedNodes.count {
            undoButtonTappedCount = 1
        }
        undoLastObject()
        
    }
    
    @IBAction func redoButtonPressed(_ sender: UIButton) {
        redoObject()
    }
    
    
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOptions" {
            let optionsViewController = segue.destination as! OptionsContainerViewController
            optionsViewController.delegate = self
        }
    }
}

// MARK: - OptionsViewControllerDelegate
extension ViewController: OptionsViewControllerDelegate {
    
    func objectSelected(node: SCNNode) {
        dismiss(animated: true, completion: nil)
        selectedNode = node
    }
    
    func togglePlaneVisualization() {
        dismiss(animated: true, completion: nil)
        showPlaneOverlay.toggle()
    }
    
    func undoLastObject() {
        let undoNodeIndex = placedNodes.count - undoButtonTappedCount
        guard undoNodeIndex >= 0 else { return }
        placedNodes[undoNodeIndex].isHidden = true
        redoNodeIndexArray.append(undoNodeIndex)
        
        appearUndoRedo()
        redoButtonOutlet.isHidden = false
    }
    
    func redoObject() {
        guard let redoNodeIndex: Int = redoNodeIndexArray.last else { return }
        placedNodes[redoNodeIndex].isHidden = false
        redoNodeIndexArray.removeLast()
        redoNodeIndexArray.isEmpty ? (redoButtonOutlet.isHidden = true) : (redoButtonOutlet.isHidden = false)
        
        appearUndoRedo()
        undoButtonTappedCount -= 1
    }
    
    func resetScene() {
        dismiss(animated: true, completion: nil)
        reloadConfiguration(removeAnchors: true)
        undoButtonOutlet.isHidden = true
        redoButtonOutlet.isHidden = true
        redoNodeIndexArray.removeAll()
        undoButtonTappedCount = 0
    }
}

// MARK: - ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate {
    /* как правило (и в этом случае тоже) didAdd node вызывается в двух случаях:
    когда определилась поверхность и когда определилось изображение
     */
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // здесь не сможем использовать guard , тк должны будем выйти, поэтому используем if let
        if let imageAnchor = anchor as? ARImageAnchor {
            nodeAdded(node, for: imageAnchor)
        } else if let planeAnchor = anchor as? ARPlaneAnchor {
            nodeAdded(node, for: planeAnchor)
        }
    }
    
    /* когда система меняет размеры наших поверхностей, нам нужно будет подстраивать размер плэйна
        для didUpdate - здесь в отличие от didAdd используем guard let, тк там интересовали два варианта imageAnchor  и planeAnchor, а здесь работаем
        только с planeAnchor
    */
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        // убеждаемся, что в массиве чайлднод есть первая нода
        guard let floor = node.childNodes.first else { return }
        guard let plane = floor.geometry as? SCNPlane else { return }
        // при изменении поверхности смещаются и координаты центра этой поверхности что мы и предусматриваем далее
        floor.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
        plane.width = CGFloat(planeAnchor.extent.x)
        plane.height = CGFloat(planeAnchor.extent.z)
    }
}
