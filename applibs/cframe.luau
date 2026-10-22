--!strict
--[[
	cframe.luau - Roblox-style CFrame (position + rotation) on Luau's built-in `vector` type (instead of Vector3 / Vector2).

	local CFrame = require("./cframe")
	local cf: CFrame.CFrame = CFrame.new(vector.create(1, 2, 3), vector.create(0, 0, 0))

	Vectors are `vector.create(x, y, z)`. Fields are .x .y .z.

	Constructors
		CFrame.new()                              identity
		CFrame.new(pos)                           pure translation
		CFrame.new(x, y, z)
		CFrame.new(pos, lookAt)                   at pos, looking at lookAt (up = +Y)
		CFrame.new(x, y, z, qx, qy, qz, qw)       from a quaternion
		CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		CFrame.lookAt(at, lookAt, up?)            CFrame.lookAlong(at, direction, up?)
		CFrame.Angles(rx, ry, rz)                 = fromEulerAnglesXYZ (radians)
		CFrame.fromEulerAnglesXYZ / fromEulerAnglesYXZ / fromOrientation (= YXZ)
		CFrame.fromAxisAngle(axis, angle)         CFrame.fromMatrix(pos, vX, vY, vZ?)
		CFrame.identity                           CFrame.isCFrame(value)

	Properties (read-only; CFrames are frozen)
		X Y Z, Position, Rotation (CFrame without position), RightVector, UpVector, LookVector (= -Z axis)

	Methods
		cf:Inverse()  cf:Lerp(goal, alpha)  cf:Orthonormalize()
		cf:ToWorldSpace(...)  cf:ToObjectSpace(...)                          (one or more CFrames)
		cf:PointToWorldSpace(v)  cf:PointToObjectSpace(v)  cf:VectorToWorldSpace(v)  cf:VectorToObjectSpace(v)
		cf:GetComponents()  cf:ToEulerAnglesXYZ()  cf:ToEulerAnglesYXZ()  cf:ToOrientation() (= YXZ)
		cf:ToAxisAngle()  cf:ToQuaternion()  cf:FuzzyEq(other, epsilon?)

	Operators
		cf * cf     compose (a * b = b expressed in a's space)       cf * vector   transforms the point
		            (typed as `CFrame | vector` because Luau has no overloads: refine with typeof(r) == "vector", or call :PointToWorldSpace / :ToWorldSpace)
		cf + vector translate in world space                          cf - vector   the same, negated
		cf == cf    exact equality of all 12 components               tostring(cf)  the 12 components

	Typechecked with luau-lsp 1.70.1 (`analyze --platform=standard`), the math checked against a Python port; never run in Zune.
]]

local module = {}
module.__index = module

-- r00 .. r22 are the rotation matrix (rows); right = column 0, up = column 1, back = column 2. Treat them as internal.
type CFrameData = {
	X: number,
	Y: number,
	Z: number,
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number,

	Position: vector,
	Rotation: CFrame, -- set once by make(); the table is frozen afterwards
	RightVector: vector,
	UpVector: vector,
	LookVector: vector,
}

-- the data above + the metatable `module`, so the methods below are available on every CFrame
export type CFrame = typeof(setmetatable({} :: CFrameData, module))

local EPS = 1e-9

--------------------------------------------------------------------------
-- Internals
--------------------------------------------------------------------------

local function build(
	x: number,
	y: number,
	z: number,
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number
): CFrame
	local data: CFrameData = {
		X = x,
		Y = y,
		Z = z,
		r00 = r00,
		r01 = r01,
		r02 = r02,
		r10 = r10,
		r11 = r11,
		r12 = r12,
		r20 = r20,
		r21 = r21,
		r22 = r22,
		Position = vector.create(x, y, z),
		RightVector = vector.create(r00, r10, r20),
		UpVector = vector.create(r01, r11, r21),
		LookVector = vector.create(-r02, -r12, -r22),
		Rotation = nil :: any, -- set by make(): a CFrame cannot be created before the one it refers to
	}
	return setmetatable(data, module)
end

-- The Rotation of a CFrame is a CFrame without position, and its own Rotation is itself (a pure rotation shares itself).
local function make(
	x: number,
	y: number,
	z: number,
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number
): CFrame
	local self = build(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	if x == 0 and y == 0 and z == 0 then
		self.Rotation = self
	else
		local rotation = build(0, 0, 0, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		rotation.Rotation = rotation
		table.freeze(rotation)
		self.Rotation = rotation
	end
	table.freeze(self)
	return self
end

local function isCFrame(value: any): boolean
	return type(value) == "table" and getmetatable(value :: any) == module
end

local function safeNormalize(v: vector, fallback: vector): vector
	if vector.magnitude(v) < EPS then
		return fallback
	end
	return vector.normalize(v)
end

local function rotate(c: CFrame, v: vector): vector -- R * v
	local x, y, z = v.x, v.y, v.z
	return vector.create(
		c.r00 * x + c.r01 * y + c.r02 * z,
		c.r10 * x + c.r11 * y + c.r12 * z,
		c.r20 * x + c.r21 * y + c.r22 * z
	)
end

local function rotateInverse(c: CFrame, v: vector): vector -- R^T * v
	local x, y, z = v.x, v.y, v.z
	return vector.create(
		c.r00 * x + c.r10 * y + c.r20 * z,
		c.r01 * x + c.r11 * y + c.r21 * z,
		c.r02 * x + c.r12 * y + c.r22 * z
	)
end

local function fromBasis(p: vector, right: vector, up: vector, back: vector): CFrame
	return make(p.x, p.y, p.z, right.x, up.x, back.x, right.y, up.y, back.y, right.z, up.z, back.z)
end

local function mul(a: CFrame, b: CFrame): CFrame
	return make(
		a.r00 * b.X + a.r01 * b.Y + a.r02 * b.Z + a.X,
		a.r10 * b.X + a.r11 * b.Y + a.r12 * b.Z + a.Y,
		a.r20 * b.X + a.r21 * b.Y + a.r22 * b.Z + a.Z,
		a.r00 * b.r00 + a.r01 * b.r10 + a.r02 * b.r20,
		a.r00 * b.r01 + a.r01 * b.r11 + a.r02 * b.r21,
		a.r00 * b.r02 + a.r01 * b.r12 + a.r02 * b.r22,
		a.r10 * b.r00 + a.r11 * b.r10 + a.r12 * b.r20,
		a.r10 * b.r01 + a.r11 * b.r11 + a.r12 * b.r21,
		a.r10 * b.r02 + a.r11 * b.r12 + a.r12 * b.r22,
		a.r20 * b.r00 + a.r21 * b.r10 + a.r22 * b.r20,
		a.r20 * b.r01 + a.r21 * b.r11 + a.r22 * b.r21,
		a.r20 * b.r02 + a.r21 * b.r12 + a.r22 * b.r22
	)
end

local function fromQuat(x: number, y: number, z: number, qx: number, qy: number, qz: number, qw: number): CFrame
	local n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if n < EPS then
		return make(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
	return make(
		x,
		y,
		z,
		1 - 2 * (qy * qy + qz * qz),
		2 * (qx * qy - qz * qw),
		2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw),
		1 - 2 * (qx * qx + qz * qz),
		2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw),
		2 * (qy * qz + qx * qw),
		1 - 2 * (qx * qx + qy * qy)
	)
end

local function toQuat(c: CFrame): (number, number, number, number)
	local tr = c.r00 + c.r11 + c.r22
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		return (c.r21 - c.r12) / s, (c.r02 - c.r20) / s, (c.r10 - c.r01) / s, s / 4
	elseif c.r00 > c.r11 and c.r00 > c.r22 then
		local s = math.sqrt(1 + c.r00 - c.r11 - c.r22) * 2
		return s / 4, (c.r01 + c.r10) / s, (c.r02 + c.r20) / s, (c.r21 - c.r12) / s
	elseif c.r11 > c.r22 then
		local s = math.sqrt(1 + c.r11 - c.r00 - c.r22) * 2
		return (c.r01 + c.r10) / s, s / 4, (c.r12 + c.r21) / s, (c.r02 - c.r20) / s
	end
	local s = math.sqrt(1 + c.r22 - c.r00 - c.r11) * 2
	return (c.r02 + c.r20) / s, (c.r12 + c.r21) / s, s / 4, (c.r10 - c.r01) / s
end

local function rotX(a: number): CFrame
	local c, s = math.cos(a), math.sin(a)
	return make(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end

local function rotY(a: number): CFrame
	local c, s = math.cos(a), math.sin(a)
	return make(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end

local function rotZ(a: number): CFrame
	local c, s = math.cos(a), math.sin(a)
	return make(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end

--------------------------------------------------------------------------
-- Constructors
--------------------------------------------------------------------------

-- Luau has no user-defined overloads: one signature, the arguments are refined by type below.
local function newImpl(a: (vector | number)?, b: (vector | number)?, c: number?, ...: number): CFrame
	if a == nil then
		return make(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif typeof(a) == "vector" then
		if b == nil then
			return make(a.x, a.y, a.z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		elseif typeof(b) == "vector" then
			return module.lookAlong(a, b - a)
		end
		error("CFrame.new: expected (pos) or (pos, lookAt)", 2)
	end
	if typeof(b) ~= "number" or c == nil then
		error("CFrame.new: expected (), (pos), (pos, lookAt), (x, y, z), 7 or 12 numbers", 2)
	end
	local rest: { number } = { ... }
	if #rest == 0 then
		return make(a, b, c, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif #rest == 4 then
		return fromQuat(a, b, c, rest[1], rest[2], rest[3], rest[4])
	elseif #rest == 9 then
		return make(a, b, c, rest[1], rest[2], rest[3], rest[4], rest[5], rest[6], rest[7], rest[8], rest[9])
	end
	error("CFrame.new: expected 3, 7 or 12 numbers", 2)
end

module.new = newImpl

function module.lookAlong(at: vector, direction: vector, up: vector?): CFrame
	local look = safeNormalize(direction, vector.create(0, 0, -1))
	local upv = up or vector.create(0, 1, 0)
	local right = vector.cross(look, upv)
	if vector.magnitude(right) < 1e-6 then -- looking straight along `up`: use another reference
		right = vector.cross(look, if math.abs(look.z) < 0.9 then vector.create(0, 0, -1) else vector.create(1, 0, 0))
	end
	right = vector.normalize(right)
	return fromBasis(at, right, vector.cross(right, look), -look)
end

function module.lookAt(at: vector, lookAt: vector, up: vector?): CFrame
	return module.lookAlong(at, lookAt - at, up)
end

function module.fromEulerAnglesXYZ(rx: number, ry: number, rz: number): CFrame
	return mul(mul(rotX(rx), rotY(ry)), rotZ(rz))
end
module.Angles = module.fromEulerAnglesXYZ

function module.fromEulerAnglesYXZ(rx: number, ry: number, rz: number): CFrame
	return mul(mul(rotY(ry), rotX(rx)), rotZ(rz))
end
module.fromOrientation = module.fromEulerAnglesYXZ

function module.fromAxisAngle(axis: vector, angle: number): CFrame
	local a = safeNormalize(axis, vector.create(0, 1, 0))
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	local x, y, z = a.x, a.y, a.z
	return make(
		0,
		0,
		0,
		c + t * x * x,
		t * x * y - s * z,
		t * x * z + s * y,
		t * x * y + s * z,
		c + t * y * y,
		t * y * z - s * x,
		t * x * z - s * y,
		t * y * z + s * x,
		c + t * z * z
	)
end

function module.fromMatrix(pos: vector, vX: vector, vY: vector, vZ: vector?): CFrame
	return fromBasis(pos, vX, vY, vZ or vector.cross(vX, vY))
end

module.identity = make(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
module.isCFrame = isCFrame

--------------------------------------------------------------------------
-- Methods
--------------------------------------------------------------------------

function module.Inverse(self: CFrame): CFrame
	local px, py, pz = self.X, self.Y, self.Z
	return make(
		-(self.r00 * px + self.r10 * py + self.r20 * pz),
		-(self.r01 * px + self.r11 * py + self.r21 * pz),
		-(self.r02 * px + self.r12 * py + self.r22 * pz),
		self.r00,
		self.r10,
		self.r20,
		self.r01,
		self.r11,
		self.r21,
		self.r02,
		self.r12,
		self.r22
	)
end

function module.Lerp(self: CFrame, goal: CFrame, alpha: number): CFrame
	local ax, ay, az, aw = toQuat(self)
	local bx, by, bz, bw = toQuat(goal)
	local d = ax * bx + ay * by + az * bz + aw * bw
	if d < 0 then
		bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d
	end
	local qx, qy, qz, qw
	if d > 0.9995 then
		qx, qy, qz, qw = ax + (bx - ax) * alpha, ay + (by - ay) * alpha, az + (bz - az) * alpha, aw + (bw - aw) * alpha
	else
		local theta = math.acos(d)
		local sinT = math.sin(theta)
		local s0, s1 = math.sin((1 - alpha) * theta) / sinT, math.sin(alpha * theta) / sinT
		qx, qy, qz, qw = ax * s0 + bx * s1, ay * s0 + by * s1, az * s0 + bz * s1, aw * s0 + bw * s1
	end
	return fromQuat(
		self.X + (goal.X - self.X) * alpha,
		self.Y + (goal.Y - self.Y) * alpha,
		self.Z + (goal.Z - self.Z) * alpha,
		qx,
		qy,
		qz,
		qw
	)
end

function module.Orthonormalize(self: CFrame): CFrame
	local right = safeNormalize(self.RightVector, vector.create(1, 0, 0))
	local up = self.UpVector
	up = safeNormalize(up - right * vector.dot(up, right), vector.create(0, 1, 0))
	return fromBasis(self.Position, right, up, vector.cross(right, up))
end

function module.ToWorldSpace(self: CFrame, ...: CFrame): ...CFrame
	local out: { CFrame } = {}
	local others: { CFrame } = { ... }
	for i, other in others do
		out[i] = mul(self, other)
	end
	return table.unpack(out)
end

function module.ToObjectSpace(self: CFrame, ...: CFrame): ...CFrame
	local inverse = module.Inverse(self)
	local out: { CFrame } = {}
	local others: { CFrame } = { ... }
	for i, other in others do
		out[i] = mul(inverse, other)
	end
	return table.unpack(out)
end

function module.PointToWorldSpace(self: CFrame, v: vector): vector
	return rotate(self, v) + self.Position
end

function module.PointToObjectSpace(self: CFrame, v: vector): vector
	return rotateInverse(self, v - self.Position)
end

function module.VectorToWorldSpace(self: CFrame, v: vector): vector
	return rotate(self, v)
end

function module.VectorToObjectSpace(self: CFrame, v: vector): vector
	return rotateInverse(self, v)
end

function module.GetComponents(self: CFrame): (
	number?,
	number?,
	number?,
	number?,
	number?,
	number?,
	number?,
	number?,
	number?,
	number?,
	number?,
	number?
)
	return self.X,
		self.Y,
		self.Z,
		self.r00,
		self.r01,
		self.r02,
		self.r10,
		self.r11,
		self.r12,
		self.r20,
		self.r21,
		self.r22
end

-- R = Rx(a) * Ry(b) * Rz(c)
function module.ToEulerAnglesXYZ(self: CFrame): (number?, number?, number?)
	local b = math.asin(math.clamp(self.r02, -1, 1))
	if math.abs(self.r02) < 0.9999999 then
		return math.atan2(-self.r12, self.r22), b, math.atan2(-self.r01, self.r00)
	end
	return math.atan2(self.r21, self.r11), b, 0
end

-- R = Ry(b) * Rx(a) * Rz(c); returns (rx, ry, rz)
function module.ToEulerAnglesYXZ(self: CFrame): (number?, number?, number?)
	local a = math.asin(math.clamp(-self.r12, -1, 1))
	if math.abs(self.r12) < 0.9999999 then
		return a, math.atan2(self.r02, self.r22), math.atan2(self.r10, self.r11)
	end
	return a, math.atan2(-self.r20, self.r00), 0
end
module.ToOrientation = module.ToEulerAnglesYXZ

function module.ToAxisAngle(self: CFrame): (vector?, number?)
	local angle = math.acos(math.clamp((self.r00 + self.r11 + self.r22 - 1) / 2, -1, 1))
	if angle < 1e-6 then
		return vector.create(0, 1, 0), 0
	end
	if math.pi - angle < 1e-4 then -- 180 degrees: the axis comes from the diagonal
		local x = math.sqrt(math.max(0, (self.r00 + 1) / 2))
		local y = math.sqrt(math.max(0, (self.r11 + 1) / 2))
		local z = math.sqrt(math.max(0, (self.r22 + 1) / 2))
		if x >= y and x >= z then
			y = if self.r01 < 0 then -y else y
			z = if self.r02 < 0 then -z else z
		elseif y >= z then
			x = if self.r01 < 0 then -x else x
			z = if self.r12 < 0 then -z else z
		else
			x = if self.r02 < 0 then -x else x
			y = if self.r12 < 0 then -y else y
		end
		return safeNormalize(vector.create(x, y, z), vector.create(0, 1, 0)), angle
	end
	return vector.normalize(vector.create(self.r21 - self.r12, self.r02 - self.r20, self.r10 - self.r01)), angle
end

function module.ToQuaternion(self: CFrame): (number?, number?, number?, number?)
	return toQuat(self)
end

function module.FuzzyEq(self: CFrame, other: CFrame, epsilon: number?): boolean
	local e = epsilon or 1e-5
	return math.abs(self.X - other.X) <= e
		and math.abs(self.Y - other.Y) <= e
		and math.abs(self.Z - other.Z) <= e
		and math.abs(self.r00 - other.r00) <= e
		and math.abs(self.r01 - other.r01) <= e
		and math.abs(self.r02 - other.r02) <= e
		and math.abs(self.r10 - other.r10) <= e
		and math.abs(self.r11 - other.r11) <= e
		and math.abs(self.r12 - other.r12) <= e
		and math.abs(self.r20 - other.r20) <= e
		and math.abs(self.r21 - other.r21) <= e
		and math.abs(self.r22 - other.r22) <= e
end

--------------------------------------------------------------------------
-- Metamethods
--------------------------------------------------------------------------

-- cf * cf composes, cf * vector transforms the point. Luau has no overloads, so the result is a union: refine it with typeof(...) or use
-- :PointToWorldSpace(v) / :ToWorldSpace(cf) when you want the exact type.
function module.__mul(a: CFrame, b: CFrame | vector): CFrame | vector
	if typeof(b) == "vector" then
		return rotate(a, b) + a.Position
	end
	return mul(a, b)
end

function module.__add(a: CFrame, b: vector): CFrame
	return make(a.X + b.x, a.Y + b.y, a.Z + b.z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end

function module.__sub(a: CFrame, b: vector): CFrame
	return make(a.X - b.x, a.Y - b.y, a.Z - b.z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end

module.__eq = function(a: CFrame, b: CFrame): boolean
	return a.X == b.X
		and a.Y == b.Y
		and a.Z == b.Z
		and a.r00 == b.r00
		and a.r01 == b.r01
		and a.r02 == b.r02
		and a.r10 == b.r10
		and a.r11 == b.r11
		and a.r12 == b.r12
		and a.r20 == b.r20
		and a.r21 == b.r21
		and a.r22 == b.r22
end

module.__tostring = function(self: CFrame): string
	return table.concat(
		{
			self.X,
			self.Y,
			self.Z,
			self.r00,
			self.r01,
			self.r02,
			self.r10,
			self.r11,
			self.r12,
			self.r20,
			self.r21,
			self.r22,
		} :: { any },
		", "
	)
end

return module
