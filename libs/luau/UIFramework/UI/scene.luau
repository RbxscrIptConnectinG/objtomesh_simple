--!strict
--[[
	scene.luau - the "world" behind the ViewportFrame element (a `scene` prop).

	local scene = require("./scene")
	local CFrame = require("./cframe")

	local world = scene.new()
	world.camera.cframe = CFrame.new(vector.create(0, 2, 8), vector.create(0, 0, 0))     -- at (0,2,8) looking at the origin
	world.camera.fov = 60                                                                  -- vertical field of view in DEGREES
	local ship = world:addModel(shipModel, 1, CFrame.new(0, 0, 0))                         -- model, size (number | vector), cframe
	ship.color = { 0.9, 0.6, 0.2, 1 }
	ship.texture = "ship.png"                                                              -- Texture or file path, like ModelView.texture
	ship.shaders = { ["chromatic.glsl"] = { offset = 3 } }                                 -- effect shaders on this object only (see README)
	ship.cframe = ship.cframe:ToWorldSpace(CFrame.Angles(0, dt, 0))                        -- CFrames are immutable: assign a new one
	                                                                                       -- (`cframe * cframe` works too but is typed CFrame | vector)
	ViewportFrame({ size = ..., scene = world })

	A scene may also be a plain table (same field names); everything is optional:
	scene = {
		camera = { cframe = CFrame.new(vector.create(0, 0, 6)), fov = 60 },
		light = { direction = vector.create(0.3, 1, 0.5), cameraFixed = false },
		objects = {
			{ model = m, size = vector.create(1, 2, 1), cframe = CFrame.new(1, 0, 0), color = { 1, 0, 0, 1 }, shaders = { ... } },
		},
	}

	Object fields: model, size (vector | number, multiplies the model's own units), cframe, color {r,g,b,a}, transparency (0..1, overrides color alpha),
	texture, interpolation, doubleSided (default true), transparencyMethod ("blend" | "dither"), highlight (same table as ModelView.highlight),
	shaders, visible (default true), centered (move the model's centre to the object's origin), name.
	Camera: cframe (default: at (0, 0, 10) looking down -Z), fov (degrees, default 70), near (0.05), far (1000).
	Light: direction (towards the light, default (0.35, 0.6, 0.72)), cameraFixed (default true: the direction is relative to the camera,
	like ModelView; false = world space).

	Drawing order: objects without shaders share one depth buffer and occlude each other (transparent ones are drawn last, far to near).
	Objects WITH shaders are rendered in their own layer after those, far to near, so they are not occluded by (and do not occlude) the others.
	Lighting is per object and ignores non-uniform scaling of the normals (use a uniform size when it matters).

	Untested at runtime; typechecked with luau-lsp.
]]

local CFrame = require("@applibs/cframe")

local ObjectClass = {}
ObjectClass.__index = ObjectClass

local WorldClass = {}
WorldClass.__index = WorldClass

export type Effects = { [string]: { [string]: any } }

export type Camera = {
	cframe: CFrame.CFrame,
	fov: number,
	near: number,
	far: number,
}

export type Light = {
	direction: vector,
	cameraFixed: boolean,
}

type ObjectData = {
	name: string?,
	model: any,
	size: vector,
	cframe: CFrame.CFrame,
	color: { number },
	transparency: number?,
	texture: any?,
	interpolation: string?,
	doubleSided: boolean,
	transparencyMethod: string?,
	highlight: any?,
	shaders: Effects?,
	visible: boolean,
	centered: boolean,
	world: World?,
}

export type Object = typeof(setmetatable({} :: ObjectData, ObjectClass))

type WorldData = {
	camera: Camera,
	light: Light,
	objects: { Object },
}

export type World = typeof(setmetatable({} :: WorldData, WorldClass))

export type ObjectOptions = {
	name: string?,
	color: { number }?,
	transparency: number?,
	texture: any?,
	interpolation: string?,
	doubleSided: boolean?,
	transparencyMethod: string?,
	highlight: any?,
	shaders: Effects?,
	visible: boolean?,
	centered: boolean?,
}

-- Callbacks the UI hands to render(): they know how to resolve textures, interpolation names and so on.
export type RenderHooks = {
	texture: (value: any) -> any,
	interpolation: (value: any) -> number,
	method: (value: any) -> string,
	highlight: (value: any) -> any,
	defaultInterpolation: number,
}

local DEFAULT_LIGHT = vector.create(0.35, 0.6, 0.72)

--------------------------------------------------------------------------
-- Building scenes
--------------------------------------------------------------------------

local function toSize(size: (vector | number)?): vector
	if size == nil then
		return vector.create(1, 1, 1)
	elseif typeof(size) == "vector" then
		return size
	end
	return vector.create(size, size, size)
end

function WorldClass.new(): World
	local data: WorldData = {
		camera = { cframe = CFrame.new(vector.create(0, 0, 10)), fov = 70, near = 0.05, far = 1000 },
		light = { direction = DEFAULT_LIGHT, cameraFixed = true },
		objects = {},
	}
	return setmetatable(data, WorldClass)
end

-- model: a Renderer model (renderer:createModel(...)); size: number (uniform) or vector; cframe: where it is (default: the origin).
function WorldClass.addModel(
	self: World,
	model: any,
	size: (vector | number)?,
	cframe: CFrame.CFrame?,
	options: ObjectOptions?
): Object
	local o: ObjectOptions = options or {}
	local data: ObjectData = {
		name = o.name,
		model = model,
		size = toSize(size),
		cframe = cframe or CFrame.identity,
		color = o.color or { 0.8, 0.8, 0.88, 1 },
		transparency = o.transparency,
		texture = o.texture,
		interpolation = o.interpolation,
		doubleSided = if o.doubleSided == nil then true else o.doubleSided,
		transparencyMethod = o.transparencyMethod,
		highlight = o.highlight,
		shaders = o.shaders,
		visible = if o.visible == nil then true else o.visible,
		centered = o.centered == true,
		world = self,
	}
	local object = setmetatable(data, ObjectClass)
	table.insert(self.objects, object)
	return object
end

function WorldClass.remove(self: World, object: Object)
	local index = table.find(self.objects, object)
	if index then
		table.remove(self.objects, index)
	end
	object.world = nil
end

function WorldClass.clear(self: World)
	for _, object in self.objects do
		object.world = nil
	end
	table.clear(self.objects)
end

function WorldClass.findFirstChild(self: World, name: string): Object?
	for _, object in self.objects do
		if object.name == name then
			return object
		end
	end
	return nil
end

function ObjectClass.destroy(self: Object)
	local world = self.world
	if world then
		world:remove(self)
	end
end

local module = {
	new = WorldClass.new,
}

function module.isWorld(value: any): boolean
	return type(value) == "table" and getmetatable(value :: any) == WorldClass
end

--------------------------------------------------------------------------
-- Matrices (column-major flat arrays, index = col * 4 + row + 1; same conventions as ui.luau)
--------------------------------------------------------------------------

local function matMul(a: { number }, b: { number }): { number }
	local r = table.create(16, 0)
	for c = 0, 3 do
		for row = 0, 3 do
			local s = 0
			for k = 0, 3 do
				s += a[k * 4 + row + 1] * b[c * 4 + k + 1]
			end
			r[c * 4 + row + 1] = s
		end
	end
	return r
end

-- Right-handed, depth 0..1, Y flipped for Vulkan clip space.
local function perspective(fovY: number, aspect: number, near: number, far: number): { number }
	local f = 1 / math.tan(fovY / 2)
	return {
		f / aspect,
		0,
		0,
		0,
		0,
		-f,
		0,
		0,
		0,
		0,
		far / (near - far),
		-1,
		0,
		0,
		(far * near) / (near - far),
		0,
	}
end

local function fromCFrame(c: CFrame.CFrame): { number }
	return { c.r00, c.r10, c.r20, 0, c.r01, c.r11, c.r21, 0, c.r02, c.r12, c.r22, 0, c.X, c.Y, c.Z, 1 }
end

local function scaleMatrix(s: vector): { number }
	return { s.x, 0, 0, 0, 0, s.y, 0, 0, 0, 0, s.z, 0, 0, 0, 0, 1 }
end

local function translateMatrix(x: number, y: number, z: number): { number }
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1 }
end

--------------------------------------------------------------------------
-- Reading scenes (World or plain table)
--------------------------------------------------------------------------

type DrawItem = {
	source: any, -- the object table (World object or plain table)
	model: any,
	mvp: { number },
	light: { number },
	color: { number },
	alpha: number,
	depth: number, -- distance along the camera's look direction
	effects: { any }?,
}

local function readSize(value: any): vector
	if typeof(value) == "vector" then
		return value
	elseif type(value) == "number" then
		return vector.create(value, value, value)
	elseif type(value) == "table" then
		local t = value :: { [any]: any }
		return vector.create(t.x or t[1] or 1, t.y or t[2] or 1, t.z or t[3] or 1)
	end
	return vector.create(1, 1, 1)
end

local function readCFrame(value: any): CFrame.CFrame
	if CFrame.isCFrame(value) then
		return value :: CFrame.CFrame
	end
	return CFrame.identity
end

local function normalizeVector(v: vector, fallback: vector): vector
	if vector.magnitude(v) < 1e-9 then
		return fallback
	end
	return vector.normalize(v)
end

--[[
	Draws `sc` (a World or a plain table) into the pixel rect (x, y, w, h) with renderer:drawModel / beginLayer.
	hooks: see RenderHooks. Returns the number of objects drawn.
]]
function module.render(renderer: any, sc: any, x: number, y: number, w: number, h: number, hooks: RenderHooks): number
	if w <= 0 or h <= 0 then
		return 0
	end
	local cam: { [string]: any } = sc.camera or {}
	local camCf = readCFrame(cam.cframe or CFrame.new(vector.create(0, 0, 10)))
	local fov = math.rad(cam.fov or 70)
	local aspect = math.max(w / math.max(h, 1), 0.01)
	local view = fromCFrame(camCf:Inverse())
	local proj = perspective(fov, aspect, cam.near or 0.05, cam.far or 1000)
	local viewProj = matMul(proj, view)
	local camPos, camLook = camCf.Position, camCf.LookVector

	local lightCfg: { [string]: any } = sc.light or {}
	local lightDir = normalizeVector(lightCfg.direction or DEFAULT_LIGHT, DEFAULT_LIGHT)
	if lightCfg.cameraFixed ~= false then
		lightDir = camCf:VectorToWorldSpace(lightDir)
	end

	local plain: { DrawItem } = {}
	local blended: { DrawItem } = {}
	local layered: { DrawItem } = {}
	local objects: { any } = sc.objects or {}
	for _, obj in objects do
		if obj.visible ~= false and obj.model ~= nil then
			local cf = readCFrame(obj.cframe)
			local model = obj.model
			local m = matMul(fromCFrame(cf), scaleMatrix(readSize(obj.size)))
			if obj.centered and model.center then
				m = matMul(m, translateMatrix(-model.center[1], -model.center[2], -model.center[3]))
			end
			local objLight = cf:VectorToObjectSpace(lightDir)
			local color: { number } = obj.color or { 0.8, 0.8, 0.88, 1 }
			local alpha = if obj.transparency ~= nil then 1 - math.clamp(obj.transparency, 0, 1) else (color[4] or 1)
			local item: DrawItem = {
				source = obj,
				model = model,
				mvp = matMul(viewProj, m),
				light = { objLight.x, objLight.y, objLight.z },
				color = { color[1], color[2], color[3], alpha },
				alpha = alpha,
				depth = vector.dot(cf.Position - camPos, camLook),
				effects = nil,
			}
			if obj.shaders ~= nil then
				local list = renderer:effectsFor(obj.shaders)
				if #list > 0 then
					item.effects = list
				end
			end
			if item.effects ~= nil then
				table.insert(layered, item)
			elseif alpha < 1 then
				table.insert(blended, item)
			else
				table.insert(plain, item)
			end
		end
	end

	local function farToNear(a: DrawItem, b: DrawItem): boolean
		return a.depth > b.depth
	end
	table.sort(blended, farToNear)
	table.sort(layered, farToNear)

	local drawn = 0
	-- clear mode: the first object clears depth + stencil of the view, later ones keep the depth (so they occlude each other);
	-- an object with a highlight needs a clean stencil
	local function draw(item: DrawItem, first: boolean)
		local obj = item.source
		local texture = hooks.texture(obj.texture)
		local interp = if obj.interpolation ~= nil
			then hooks.interpolation(obj.interpolation)
			else hooks.defaultInterpolation
		local highlight = hooks.highlight(obj.highlight)
		local clear = if first then "all" elseif highlight ~= nil then "stencil" else "none"
		renderer:drawModel(
			item.model,
			x,
			y,
			w,
			h,
			item.mvp,
			item.light,
			item.color,
			texture,
			obj.doubleSided,
			interp,
			hooks.method(obj.transparencyMethod),
			highlight,
			clear
		)
		drawn += 1
	end

	local first = true
	for _, item in plain do
		draw(item, first)
		first = false
	end
	for _, item in blended do
		draw(item, first)
		first = false
	end
	for _, item in layered do
		renderer:beginLayer({ x, y, w, h }, item.effects, item.source) -- a fresh layer has a fresh depth buffer
		draw(item, true)
		renderer:endLayer()
	end
	return drawn
end

return module
