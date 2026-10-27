import Foundation
import QuartzCore
import SceneKit
import simd

/// Rendering switches. `-legacy` on the command line restores the old (unoptimized) paths so the
/// benchmark can compare both in the same build.
enum PerfSettings {
    static let optimized = !CommandLine.arguments.contains("-legacy")
    static let benchmark = CommandLine.arguments.contains("-benchmark")
    static let finishTest = CommandLine.arguments.contains("-finishtest")

    /// Cars farther than this (meters) use the simple body and skip wheels/lights.
    static let carDetailDistance: CGFloat = 38
}

// MARK: - Mesh building

/// Builds one geometry from boxes written vertex by vertex (SceneKit's own primitives do not expose
/// their real vertex data), grouping triangles by material so a whole city of buildings costs one
/// draw call per material.
final class MeshBuilder {
    private var positions: [SCNVector3] = []
    private var normals: [SCNVector3] = []
    private var uvs: [SIMD2<Float>] = []
    private var materials: [SCNMaterial] = []
    private var groups: [[UInt32]] = []

    private func group(for material: SCNMaterial) -> Int {
        if let index = materials.firstIndex(where: { $0 === material }) { return index }
        materials.append(material)
        groups.append([])
        return materials.count - 1
    }

    private func quad(_ corners: [SIMD3<Float>], normal: SIMD3<Float>, uvMax: SIMD2<Float>, material: SCNMaterial) {
        let base = UInt32(positions.count)
        let uv: [SIMD2<Float>] = [SIMD2(0, uvMax.y), SIMD2(uvMax.x, uvMax.y), SIMD2(uvMax.x, 0), SIMD2(0, 0)]
        for (corner, coord) in zip(corners, uv) {
            positions.append(SCNVector3(corner.x, corner.y, corner.z))
            normals.append(SCNVector3(normal.x, normal.y, normal.z))
            uvs.append(coord)
        }
        let g = group(for: material)
        groups[g] += [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    /// Axis-aligned box (rotated about y by `angle`) standing on y = 0 at `center`.
    /// `sideRepeats(width or length) -> uv repeats` sets the texture tiling on the walls.
    func addBox(center: SIMD3<Float>, width: Float, height: Float, length: Float, angle: Float,
                wall: SCNMaterial, roof: SCNMaterial, wallRepeats: (Float) -> SIMD2<Float>) {
        let c = cos(angle), s = sin(angle)
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            SIMD3(center.x + x * c + z * s, center.y + y, center.z - x * s + z * c)
        }
        func n(_ x: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x * c + z * s, 0, -x * s + z * c) }
        let w = width / 2, l = length / 2, h = height
        // Walls: counter-clockwise seen from outside (bottom-left, bottom-right, top-right, top-left)
        quad([p(-w, 0, l), p(w, 0, l), p(w, h, l), p(-w, h, l)], normal: n(0, 1), uvMax: wallRepeats(width), material: wall)
        quad([p(w, 0, -l), p(-w, 0, -l), p(-w, h, -l), p(w, h, -l)], normal: n(0, -1), uvMax: wallRepeats(width), material: wall)
        quad([p(w, 0, l), p(w, 0, -l), p(w, h, -l), p(w, h, l)], normal: n(1, 0), uvMax: wallRepeats(length), material: wall)
        quad([p(-w, 0, -l), p(-w, 0, l), p(-w, h, l), p(-w, h, -l)], normal: n(-1, 0), uvMax: wallRepeats(length), material: wall)
        quad([p(-w, h, l), p(w, h, l), p(w, h, -l), p(-w, h, -l)], normal: SIMD3(0, 1, 0), uvMax: SIMD2(1, 1), material: roof)
    }

    func build() -> SCNGeometry? {
        guard !positions.isEmpty else { return nil }
        let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvSource = SCNGeometrySource(data: uvData, semantic: .texcoord, vectorCount: uvs.count,
                                         usesFloatComponents: true, componentsPerVector: 2,
                                         bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                         dataStride: MemoryLayout<SIMD2<Float>>.stride)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), uvSource],
                                   elements: groups.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        geometry.materials = materials
        return geometry
    }
}

// MARK: - Frame timing

/// Collects SceneKit render timestamps and game-loop CPU time for the benchmark.
final class FrameMonitor: NSObject, SCNSceneRendererDelegate {
    static let shared = FrameMonitor()

    private let lock = NSLock()
    private var renderTimes: [CFTimeInterval] = []
    private var updateCosts: [Double] = []
    private var renderCosts: [Double] = []
    private var renderStarted: CFTimeInterval = 0
    private(set) var recording = false

    func start() {
        lock.lock()
        renderTimes.removeAll()
        updateCosts.removeAll()
        renderCosts.removeAll()
        recording = true
        lock.unlock()
    }

    func stop() {
        lock.lock()
        recording = false
        lock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        renderStarted = CACurrentMediaTime()
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let now = CACurrentMediaTime()
        lock.lock()
        if recording {
            renderTimes.append(now)
            if renderStarted > 0 { renderCosts.append((now - renderStarted) * 1000) }
        }
        lock.unlock()
    }

    func recordUpdate(milliseconds: Double) {
        lock.lock()
        if recording { updateCosts.append(milliseconds) }
        lock.unlock()
    }

    /// Frames slower than `threshold` ms as [seconds since start, milliseconds].
    func spikes(over threshold: Double) -> [[Double]] {
        lock.lock()
        let times = renderTimes
        lock.unlock()
        guard let first = times.first else { return [] }
        var result: [[Double]] = []
        for index in 1..<max(times.count, 1) {
            let ms = (times[index] - times[index - 1]) * 1000
            if ms > threshold {
                result.append([((times[index] - first) * 10).rounded() / 10, ms.rounded()])
            }
        }
        return Array(result.prefix(20))
    }

    struct Summary {
        let frames: Int
        let seconds: Double
        let averageFPS: Double
        let p50: Double
        let p95: Double
        let p99: Double
        let worst: Double
        let onePercentLowFPS: Double
        let jankFrames: Int
        let updateAverage: Double
        let updateP95: Double
        let renderCpuAverage: Double
        let renderCpuP95: Double
    }

    func summary() -> Summary {
        lock.lock()
        let times = renderTimes
        let costs = updateCosts.sorted()
        let renders = renderCosts.sorted()
        lock.unlock()
        var intervals: [Double] = []
        for index in 1..<max(times.count, 1) { intervals.append((times[index] - times[index - 1]) * 1000) }
        let sorted = intervals.sorted()
        func pick(_ list: [Double], _ q: Double) -> Double {
            guard !list.isEmpty else { return 0 }
            return list[min(list.count - 1, Int(Double(list.count - 1) * q))]
        }
        let seconds = (times.last ?? 0) - (times.first ?? 0)
        let slowest = sorted.suffix(max(1, sorted.count / 100))
        let lowAverage = slowest.isEmpty ? 0 : slowest.reduce(0, +) / Double(slowest.count)
        return Summary(frames: times.count, seconds: seconds,
                       averageFPS: seconds > 0 ? Double(max(times.count - 1, 0)) / seconds : 0,
                       p50: pick(sorted, 0.5), p95: pick(sorted, 0.95), p99: pick(sorted, 0.99), worst: sorted.last ?? 0,
                       onePercentLowFPS: lowAverage > 0 ? 1000 / lowAverage : 0,
                       jankFrames: sorted.filter { $0 > 25 }.count,
                       updateAverage: costs.isEmpty ? 0 : costs.reduce(0, +) / Double(costs.count),
                       updateP95: pick(costs, 0.95),
                       renderCpuAverage: renders.isEmpty ? 0 : renders.reduce(0, +) / Double(renders.count),
                       renderCpuP95: pick(renders, 0.95))
    }
}

// MARK: - Scene statistics

enum SceneStats {
    /// Nodes with geometry and the draw calls they would cost at full detail (one per element).
    static func count(_ root: SCNNode) -> (nodes: Int, geometryNodes: Int, drawCalls: Int, triangles: Int) {
        var nodes = 0
        var geometryNodes = 0
        var drawCalls = 0
        var triangles = 0
        root.enumerateHierarchy { node, _ in
            nodes += 1
            guard !node.isHidden, let geometry = node.geometry else { return }
            geometryNodes += 1
            drawCalls += geometry.elements.count
            triangles += geometry.elements.reduce(0) { $0 + $1.primitiveCount }
        }
        return (nodes, geometryNodes, drawCalls, triangles)
    }

    /// Draw calls and triangles actually submitted at the current camera position, taking levels of
    /// detail into account (ignores frustum culling).
    static func effective(_ root: SCNNode, camera: SIMD3<Float>) -> (drawCalls: Int, triangles: Int) {
        var drawCalls = 0
        var triangles = 0
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            var current: SCNNode? = node
            while let check = current {
                if check.isHidden { return }
                current = check.parent
            }
            drawCalls += geometry.elements.count
            triangles += geometry.elements.reduce(0) { $0 + $1.primitiveCount }
        }
        return (drawCalls, triangles)
    }
}

