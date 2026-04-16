import simd

enum BoxGeometry {
    static func generate(width: Float, height: Float, depth: Float) -> ([Vertex], [UInt32]) {
        let hw = width * 0.5
        let hh = height * 0.5
        let hd = depth * 0.5

        var vertices: [Vertex] = []
        var indices: [UInt32] = []

        // Each face has 4 vertices with face-aligned normals and 6 indices (2 triangles).
        // Winding is counter-clockwise when viewed from outside.

        let faceUVs: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1), SIMD2<Float>(0, 1),
        ]

        let faces: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])] = [
            // +X face
            (normal: SIMD3<Float>( 1,  0,  0), corners: [
                SIMD3<Float>( hw, -hh,  hd),
                SIMD3<Float>( hw, -hh, -hd),
                SIMD3<Float>( hw,  hh, -hd),
                SIMD3<Float>( hw,  hh,  hd),
            ]),
            // -X face
            (normal: SIMD3<Float>(-1,  0,  0), corners: [
                SIMD3<Float>(-hw, -hh, -hd),
                SIMD3<Float>(-hw, -hh,  hd),
                SIMD3<Float>(-hw,  hh,  hd),
                SIMD3<Float>(-hw,  hh, -hd),
            ]),
            // +Y face
            (normal: SIMD3<Float>( 0,  1,  0), corners: [
                SIMD3<Float>(-hw,  hh,  hd),
                SIMD3<Float>( hw,  hh,  hd),
                SIMD3<Float>( hw,  hh, -hd),
                SIMD3<Float>(-hw,  hh, -hd),
            ]),
            // -Y face
            (normal: SIMD3<Float>( 0, -1,  0), corners: [
                SIMD3<Float>(-hw, -hh, -hd),
                SIMD3<Float>( hw, -hh, -hd),
                SIMD3<Float>( hw, -hh,  hd),
                SIMD3<Float>(-hw, -hh,  hd),
            ]),
            // +Z face
            (normal: SIMD3<Float>( 0,  0,  1), corners: [
                SIMD3<Float>(-hw, -hh,  hd),
                SIMD3<Float>( hw, -hh,  hd),
                SIMD3<Float>( hw,  hh,  hd),
                SIMD3<Float>(-hw,  hh,  hd),
            ]),
            // -Z face
            (normal: SIMD3<Float>( 0,  0, -1), corners: [
                SIMD3<Float>( hw, -hh, -hd),
                SIMD3<Float>(-hw, -hh, -hd),
                SIMD3<Float>(-hw,  hh, -hd),
                SIMD3<Float>( hw,  hh, -hd),
            ]),
        ]

        for face in faces {
            let base = UInt32(vertices.count)
            for (i, corner) in face.corners.enumerated() {
                vertices.append(Vertex(position: corner, normal: face.normal, texCoords: faceUVs[i]))
            }
            // Two CCW triangles: 0-1-2, 0-2-3
            indices.append(contentsOf: [base, base + 1, base + 2,
                                        base, base + 2, base + 3])
        }

        return (vertices, indices)
    }
}
