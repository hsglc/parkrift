import SceneKit
import UIKit

/// Traffic and parked vehicles from Kenney's Car Kit (CC0): sedans, SUVs, taxis, vans, pickups,
/// delivery trucks and the odd police car, ambulance, garbage truck or fire engine. All share one
/// palette texture.
enum TrafficVehicles {
    /// How often each vehicle shows up.
    private static let mix: [(String, Int)] = [
        ("sedan", 5), ("suv", 3), ("taxi", 3), ("hatchback_sports", 2), ("sedan_sports", 2), ("van", 2),
        ("truck", 2), ("suv_luxury", 2), ("delivery", 2), ("police", 1), ("ambulance", 1), ("garbage_truck", 1),
        ("firetruck", 1)
    ]
    private static let pool: [String] = mix.flatMap { Array(repeating: $0.0, count: $0.1) }

    private static let lock = NSRecursiveLock()
    private static var bodies: [String: SCNNode] = [:]
    private static var wheels: [String: SCNNode] = [:]
    private static var parkedTemplates: [String: SCNNode] = [:]

    /// A vehicle for this seed (same seed, same vehicle).
    static func pick(_ seed: Int) -> KenneyVehicle? {
        let index = (abs(seed &* 2654435761) >> 7) % pool.count
        return KenneyCatalog.all[pool[index]]
    }

    static func body(_ id: String) -> SCNNode? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = bodies[id] { return cached }
        let node = CarModels.load("kenney_\(id)_body")
        bodies[id] = node
        return node
    }

    static func wheel(_ id: String) -> SCNNode? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = wheels[id] { return cached }
        let node = CarModels.load("kenney_\(id)_wheel")
        node?.enumerateHierarchy { child, _ in child.castsShadow = false }
        wheels[id] = node
        return node
    }

    /// Reads every vehicle (background thread).
    static func preload() {
        for id in Set(pool) {
            _ = body(id)
            _ = wheel(id)
        }
    }

    /// Body and wheels merged into one mesh for a car that never moves.
    static func parked(_ vehicle: KenneyVehicle) -> SCNNode? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = parkedTemplates[vehicle.id] { return cached }
        guard let body = body(vehicle.id) else { return nil }
        let holder = SCNNode()
        holder.addChildNode(body.clone())
        if let wheel = wheel(vehicle.id) {
            for spot in vehicle.wheels {
                let copy = wheel.clone()
                copy.position = SCNVector3(spot.0, spot.1, spot.2)
                if (spot.2 > 0) != (vehicle.wheelModelSide > 0) { copy.eulerAngles.y = Float.pi }
                holder.addChildNode(copy)
            }
        }
        let flat = holder.flattenedClone()
        parkedTemplates[vehicle.id] = flat
        return flat
    }

    /// Geometry of every loaded vehicle, for the GPU warm-up.
    static var allGeometries: [SCNGeometry] {
        lock.lock()
        let nodes = Array(bodies.values) + Array(wheels.values) + Array(parkedTemplates.values)
        lock.unlock()
        var result: [SCNGeometry] = []
        for node in nodes {
            node.enumerateHierarchy { child, _ in
                if let geometry = child.geometry { result.append(geometry) }
            }
        }
        return result
    }
}
