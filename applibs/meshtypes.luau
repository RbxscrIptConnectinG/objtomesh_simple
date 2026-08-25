export type Vertex = {
	vx: number,
	vy: number,
	vz: number,
	nx: number,
	ny: number,
	nz: number,
	tu: number,
	tv: number,
	tw: number,
}

export type Face = {
	a: number,
	b: number,
	c: number,
}

export type MeshData = {
	vertices: { Vertex },
	faces: { Face },
}

return {}
