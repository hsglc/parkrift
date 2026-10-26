import Foundation
import QuartzCore
import SceneKit
import simd

/// Rendering switches. `-legacy` on the command line restores the old (unoptimized) paths so the
/// benchmark can compare both in the same build.
enum PerfSettings {
    static let optimized = !CommandLine.arguments.contains("-legacy")
    static let benchmark = CommandLine.arguments.contains("-benchmark")

    /// Cars farther than this (meters) use the simple body and skip wheels/lights.
    static let carDetailDistance: CGFloat = 38
}

// MARK: - Geometry merging

/// Bakes a node tree into a single geometry with one element per distinct material, so a whole
/// car (or every building of a city) is drawn with a handful of draw calls instead of dozens.
enum GeometryMerger {
    /// `uvScale` lets callers bake texture repeats into the UVs (per node and element) so one shared
    /// material can serve differently sized faces.
    static func merge(_ root: SCNNode, uvScale: ((SCNNode, Int) -> SIMD2<Float>)? = nil) -> SCNGeometry? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var materials: [SCNMaterial] = []
        var groups: [[UInt32]] = []

        func visit(_ node: SCNNode, _ parent: simd_float4x4) {
            let transform = parent * node.simdTransform
            if let geometry = node.geometry {
                let vertices = vectors(geometry, .vertex, components: 3)
                if !vertices.isEmpty {
                    let normalSource = vectors(geometry, .normal, components: 3)
                    let texcoords = vectors(geometry, .texcoord, components: 2)
                    let base = UInt32(positions.count)
                    let linear = simd_float3x3(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                               SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                               SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
                    let normalMatrix = linear.inverse.transpose
                    for index in 0..<vertices.count {
                        let v = vertices[index]
                        let p = transform * SIMD4<Float>(v[0], v[1], v[2], 1)
                        positions.append(SIMD3(p.x, p.y, p.z))
                        if index < normalSource.count {
                            let n = normalSource[index]
                            normals.append(simd_normalize(normalMatrix * SIMD3(n[0], n[1], n[2])))
                        } else {
                            normals.append(SIMD3(0, 1, 0))
                        }
                        uvs.append(index < texcoords.count ? SIMD2(texcoords[index][0], texcoords[index][1]) : .zero)
                    }
                    // Per-element UV scaling needs per-element vertices; remember which vertices each element uses
                    for (elementIndex, element) in geometry.elements.enumerated() where element.primitiveType == .triangles {
                        let material = geometry.materials.isEmpty ? SCNMaterial()
                                                                  : geometry.materials[elementIndex % geometry.materials.count]
                        var indices = elementIndices(element)
                        if let uvScale = uvScale {
                            let scale = uvScale(node, elementIndex)
                            if scale != SIMD2(1, 1) {
                                // Duplicate this element's vertices so the scale does not leak into other faces
                                var remap: [UInt32: UInt32] = [:]
                                for (k, i) in indices.enumerated() {
                                    if let mapped = remap[i] {
                                        indices[k] = mapped
                                        continue
                                    }
                                    let source = Int(base + i)
                                    positions.append(positions[source])
                                    normals.append(normals[source])
                                    uvs.append(uvs[source] * scale)
                                    let newIndex = UInt32(positions.count - 1) - base
                                    remap[i] = newIndex
                                    indices[k] = newIndex
                                }
                            }
                        }
                        let shifted = indices.map { $0 + base }
                        if let group = materials.firstIndex(where: { $0 === material }) {
                            groups[group].append(contentsOf: shifted)
                        } else {
                            materials.append(material)
                            groups.append(shifted)
                        }
                    }
                }
            }
            for child in node.childNodes { visit(child, transform) }
        }
        visit(root, matrix_identity_float4x4)
        guard !positions.isEmpty else { return nil }

        let vertexSource = SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) })
        let normalSource = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
        let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvSource = SCNGeometrySource(data: uvData, semantic: .texcoord, vectorCount: uvs.count,
                                         usesFloatComponents: true, componentsPerVector: 2,
                                         bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                         dataStride: MemoryLayout<SIMD2<Float>>.stride)
        let elements = groups.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
        let geometry = SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: elements)
        geometry.materials = materials
        return geometry
    }

    private static func vectors(_ geometry: SCNGeometry, _ semantic: SCNGeometrySource.Semantic, components: Int) -> [[Float]] {
        guard let source = geometry.sources(for: semantic).first,
              source.usesFloatComponents, source.bytesPerComponent == 4,
              source.componentsPerVector >= components else { return [] }
        var result: [[Float]] = []
        result.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for index in 0..<source.vectorCount {
                let offset = source.dataOffset + index * source.dataStride
                var vector: [Float] = []
                for component in 0..<components {
                    vector.append(raw.loadUnaligned(fromByteOffset: offset + component * 4, as: Float.self))
                }
                result.append(vector)
            }
        }
        return result
    }

    private static func elementIndices(_ element: SCNGeometryElement) -> [UInt32] {
        let count = element.primitiveCount * 3
        var result: [UInt32] = []
        result.reserveCapacity(count)
        element.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for index in 0..<count {
                switch element.bytesPerIndex {
                case 1: result.append(UInt32(raw.loadUnaligned(fromByteOffset: index, as: UInt8.self)))
                case 2: result.append(UInt32(raw.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self)))
                default: result.append(raw.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self))
                }
            }
        }
        return result
    }
}

// MARK: - Frame timing

/// Collects SceneKit render timestamps and game-loop CPU time for the benchmark.
final class FrameMonitor: NSObject, SCNSceneRendererDelegate {
    static let shared = FrameMonitor()

    private let lock = NSLock()
    private var renderTimes: [CFTimeInterval] = []
    private var updateCosts: [Double] = []
    private(set) var recording = false

    func start() {
        lock.lock()
        renderTimes.removeAll()
        updateCosts.removeAll()
        recording = true
        lock.unlock()
    }

    func stop() {
        lock.lock()
        recording = false
        lock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let now = CACurrentMediaTime()
        lock.lock()
        if recording { renderTimes.append(now) }
        lock.unlock()
    }

    func recordUpdate(milliseconds: Double) {
        lock.lock()
        if recording { updateCosts.append(milliseconds) }
        lock.unlock()
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
    }

    func summary() -> Summary {
        lock.lock()
        let times = renderTimes
        let costs = updateCosts.sorted()
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
                       updateP95: pick(costs, 0.95))
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
}
