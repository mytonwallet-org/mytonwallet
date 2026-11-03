import {
  buildAgentSpinningTopMesh, computeAgentSpinningTopTransform, FLOATS_PER_VERTEX, LEAN, VIEW_PITCH,
} from './agentSpinningTopGeometry';

describe('Agent spinning top geometry', () => {
  it('builds a closed surface from the point to the cap with unit normals', () => {
    const { vertices, indices } = buildAgentSpinningTopMesh(40, 24);

    expect(vertices).toHaveLength(40 * 24 * FLOATS_PER_VERTEX);
    expect(indices).toHaveLength(39 * 24 * 6);
    expect(Math.max(...indices)).toBe(40 * 24 - 1);
    // The point at the origin faces down, the cap faces up
    [0, 0, 0, 0, -1, 0].forEach((value, index) => expect(vertices[index]).toBeCloseTo(value, 5));
    const cap = vertices.length - FLOATS_PER_VERTEX;
    expect(vertices[cap + 1]).toBeCloseTo(1.4797, 4);
    expect(vertices[cap + 4]).toBe(1);
    for (let offset = 0; offset < vertices.length; offset += FLOATS_PER_VERTEX) {
      expect(Math.hypot(vertices[offset + 3], vertices[offset + 4], vertices[offset + 5])).toBeCloseTo(1, 3);
    }
    // The rim is the widest ring
    let widest = 0;
    for (let offset = 0; offset < vertices.length; offset += FLOATS_PER_VERTEX) {
      widest = Math.max(widest, Math.hypot(vertices[offset], vertices[offset + 2]));
    }
    expect(widest).toBeGreaterThan(0.72);
    expect(widest).toBeLessThan(0.74);
  });

  it('leans the axis to the right at rest and keeps the rotation rigid', () => {
    const matrix = new Float32Array(16);
    computeAgentSpinningTopTransform(0, 0, 0, 0, matrix);
    expect(Array.from(matrix)).toEqual([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

    computeAgentSpinningTopTransform(0, 0, LEAN, 0, matrix);
    // The image of the axis, the matrix's second column, leans toward +x by the lean
    expect(matrix[4]).toBeCloseTo(Math.sin(LEAN), 5);
    expect(matrix[5]).toBeCloseTo(Math.cos(LEAN), 5);

    computeAgentSpinningTopTransform(1.3, VIEW_PITCH, LEAN, 2.2, matrix);
    for (let column = 0; column < 3; column++) {
      const [x, y, z] = [matrix[column * 4], matrix[column * 4 + 1], matrix[column * 4 + 2]];
      expect(Math.hypot(x, y, z)).toBeCloseTo(1, 5);
    }
    const dot = matrix[0] * matrix[4] + matrix[1] * matrix[5] + matrix[2] * matrix[6];
    expect(dot).toBeCloseTo(0, 5);
  });
});
