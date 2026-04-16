import simd

enum SphereGeometry {
    static func generate(radius: Float, segments: Int) -> ([Vertex], [UInt32]) {
        let segments = max(segments, 4)
        var vertices: [Vertex] = []
        var indices: [UInt32] = []

        for lat in 0...segments {
            let theta = Float(lat) / Float(segments) * .pi
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            for lon in 0...segments {
                let phi = Float(lon) / Float(segments) * 2.0 * .pi
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)

                let normal = SIMD3<Float>(sinTheta * cosPhi, cosTheta, sinTheta * sinPhi)
                let position = radius * normal
                let u = Float(lon) / Float(segments)
                let v = Float(lat) / Float(segments)
                vertices.append(Vertex(position: position, normal: normal, texCoords: SIMD2<Float>(u, v)))
            }
        }

        let stride = UInt32(segments + 1)
        for lat in 0..<UInt32(segments) {
            for lon in 0..<UInt32(segments) {
                let topLeft     = lat * stride + lon
                let topRight    = topLeft + 1
                let bottomLeft  = topLeft + stride
                let bottomRight = bottomLeft + 1

                indices.append(contentsOf: [topLeft, bottomRight, bottomLeft])
                indices.append(contentsOf: [topLeft, topRight, bottomRight])
            }
        }

        return (vertices, indices)
    }
}
