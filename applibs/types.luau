local meshTypes = require("@applibs/mesh/types")

export type meshSettings = {
	encoderVer: "1.00" | "1.01" | "2.00" | "3.00" | "3.01" | "4.00" | "4.01" | "5.00" | "7.00" | string,
	options: {
		autoLODs: {
			method: string | "QEM" | "MC",
			levels: number,
			resolution: number,
		}?,
	},
}

type autoLodFunc = (
	baseVerts: { meshTypes.Vertex },
	baseFaces: { meshTypes.Face },
	targetFaceCount: number
) -> ({ meshTypes.Vertex }, { meshTypes.Face })

export type MeshWorks = {
	parsers: {
		[string]: (root: MeshWorks, ...any) -> meshTypes.MeshData,
	},
	encoders: {
		[string]: (root: MeshWorks, ...any) -> ...string,
	},

	decodeMesh: (data: string) -> meshTypes.MeshData,
	meshToOBJ: (mesh: meshTypes.MeshData) -> string,
	objToMesh: (version: string, objData: string, ...any?) -> string,
	convertMeshToOBJ: (data: string) -> string,

	utils: {
		VERTEX_SIZE: number,
		FACE_SIZE: number,

		readVertex: (data: buffer, offset: number) -> meshTypes.Vertex,
		readFace: (data: buffer, offset: number) -> meshTypes.Face,

		writeVertex: (out: buffer, offset: number, v: meshTypes.Vertex) -> nil,
		writeFace: (out: buffer, offset: number, f: meshTypes.Face) -> nil,

		resolveLodOffsets: (mesh: meshTypes.MeshData) -> { number },

		fmt: (number) -> string,

		parseIndex: (token: string, count: number) -> number?,

		autoLOD: {
			QEM: autoLodFunc,
			MC: autoLodFunc,
		},
	},
}

return {}
