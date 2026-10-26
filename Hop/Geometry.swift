import CoreGraphics
import UIKit

/// Oriented bounding box: `halfSize.width` runs along the heading, `halfSize.height` across it.
struct OBB {
    var center: CGPoint
    var halfSize: CGSize
    var angle: CGFloat

    init(center: CGPoint, size: CGSize, angle: CGFloat) {
        self.center = center
        self.halfSize = CGSize(width: size.width / 2, height: size.height / 2)
        self.angle = angle
    }

    var axisU: CGVector { CGVector(dx: cos(angle), dy: sin(angle)) }
    var axisV: CGVector { CGVector(dx: -sin(angle), dy: cos(angle)) }

    var corners: [CGPoint] {
        let u = axisU
        let v = axisV
        let hx = halfSize.width
        let hy = halfSize.height
        let signs: [(CGFloat, CGFloat)] = [(1, 1), (1, -1), (-1, -1), (-1, 1)]
        var result: [CGPoint] = []
        for sign in signs {
            let x = center.x + u.dx * hx * sign.0 + v.dx * hy * sign.1
            let y = center.y + u.dy * hx * sign.0 + v.dy * hy * sign.1
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }

    func contains(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let u = axisU
        let v = axisV
        let along = dx * u.dx + dy * u.dy
        let across = dx * v.dx + dy * v.dy
        return abs(along) <= halfSize.width && abs(across) <= halfSize.height
    }

    func intersects(_ other: OBB) -> Bool {
        let axes = [axisU, axisV, other.axisU, other.axisV]
        let mine = corners
        let theirs = other.corners
        for axis in axes {
            var minA = CGFloat.greatestFiniteMagnitude
            var maxA = -CGFloat.greatestFiniteMagnitude
            for p in mine {
                let d = p.x * axis.dx + p.y * axis.dy
                minA = min(minA, d)
                maxA = max(maxA, d)
            }
            var minB = CGFloat.greatestFiniteMagnitude
            var maxB = -CGFloat.greatestFiniteMagnitude
            for p in theirs {
                let d = p.x * axis.dx + p.y * axis.dy
                minB = min(minB, d)
                maxB = max(maxB, d)
            }
            if maxA < minB || maxB < minA { return false }
        }
        return true
    }
}

extension CGFloat {
    /// Smallest signed difference between two angles, in -pi...pi.
    static func angleDelta(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        (to - from).remainder(dividingBy: 2 * CGFloat.pi)
    }
}

extension UIColor {
    func darker(by amount: CGFloat = 0.2) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: Swift.max(brightness - amount, 0), alpha: alpha)
    }

    func lighter(by amount: CGFloat = 0.15) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue,
                       saturation: Swift.max(saturation - amount * 0.6, 0),
                       brightness: Swift.min(brightness + amount, 1),
                       alpha: alpha)
    }
}
