--[[
	renderer.luau - small Vulkan 1.0 renderer for UI work (Zune + zune.ffi)

	Immediate-mode API, one frame at a time:

		local r = Renderer.new(glfw, window, { validation = false })
		while ... do
			if r:beginFrame() then
				r:quad(x, y, w, h, red, green, blue, alpha, texture?, u0?, v0?, u1?, v1?)
				r:pushClip(x, y, w, h) ... r:popClip()
				r:drawModel(model, x, y, w, h, mvp, lightDir, color)
				r:endFrame()
			end
		end
		r:destroy()

	Coordinates are framebuffer pixels, origin top-left. Draw order == call order.
	NOT TESTED on real hardware - see the notes in README.md.
]]

local ffi = zune.ffi
local vk = require("@self/vk")
local shaderLoader = require("@self/shader")
local C = vk.C

local FRAMES = 2
local UI_STRIDE = 20 -- x y u v (f32) + rgba (u8x4)
local MODEL_STRIDE = 32 -- pos(3) + normal(3) + uv(2), f32
local MAX_TEXTURES = 512

export type Options = {
	validation: boolean?, -- enable VK_LAYER_KHRONOS_validation (needs the layer installed)
	libraryPath: string?, -- explicit path to the Vulkan loader
	appName: string?,
	clearColor: { number }?, -- {r, g, b, a}
	maxVertices: number?, -- per-frame UI vertex capacity (default 65536 = ~10k quads)
	shaders: any?, -- "folder" (default: "shaders" beside renderer.luau) | { uiVert/uiFrag/modelVert/modelFrag/modelFragDither = "file.vert|.frag|.spv" | SPIR-V buffer } | { libraryPath = shaderc library path, shaders = either of the former }
}

local Renderer = {}
Renderer.__index = Renderer

local Texture = {}
Texture.__index = Texture

local Model = {}
Model.__index = Model

local function readU64(p: any, offset: number): number
	return p:readu32(offset) + p:readu32(offset + 4) * 4294967296
end

local function packColor(r: number, g: number, b: number, a: number): number
	local function c(v: number): number
		return math.floor(math.clamp(v, 0, 1) * 255 + 0.5)
	end
	return c(r) + c(g) * 256 + c(b) * 65536 + c(a) * 16777216
end

--------------------------------------------------------------------------
-- Low-level helpers
--------------------------------------------------------------------------

-- Calls vkCreateXxx(device, info, NULL, out) and returns the new handle.
function Renderer:_create(fname: string, info: any): any
	vk.check(self.L[fname](self.dev, info, nil, self.out), fname)
	return self.out:readptr(0)
end

function Renderer:_memType(typeBits: number, props: number): number
	local mp = self.memProps
	for i = 0, mp:readu32(0) - 1 do
		local flags = mp:readu32(4 + i * 8)
		if bit32.btest(typeBits, bit32.lshift(1, i)) and bit32.band(flags, props) == props then
			return i
		end
	end
	error("vulkan: no suitable memory type")
end

function Renderer:_allocMem(size: number, typeBits: number, props: number, a: any): any
	local info = vk.new("VkMemoryAllocateInfo", {
		sType = C.ST_MEMORY_ALLOCATE_INFO,
		allocationSize = size,
		memoryTypeIndex = self:_memType(typeBits, props),
	}, a)
	vk.check(self.L.vkAllocateMemory(self.dev, info, nil, self.out), "vkAllocateMemory")
	return self.out:readptr(0)
end

function Renderer:_makeBuffer(size: number, usage: number, props: number): any
	local a = vk.arena()
	local info = vk.new("VkBufferCreateInfo", {
		sType = C.ST_BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = 0,
	}, a)
	local buf = self:_create("vkCreateBuffer", info)
	local req = a:alloc(32)
	self.L.vkGetBufferMemoryRequirements(self.dev, buf, req)
	local mem = self:_allocMem(readU64(req, 0), req:readu32(16), props, a)
	vk.check(self.L.vkBindBufferMemory(self.dev, buf, mem, 0), "vkBindBufferMemory")
	local res: any = { buffer = buf, memory = mem, size = size }
	if bit32.band(props, C.MEM_HOST_VISIBLE) ~= 0 then
		vk.check(self.L.vkMapMemory(self.dev, mem, 0, vk.U64_MAX, 0, self.out), "vkMapMemory")
		res.mapped = self.out:readptr(0)
	end
	a:free()
	return res
end

function Renderer:_destroyBuffer(b: any)
	self.L.vkDestroyBuffer(self.dev, b.buffer, nil)
	self.L.vkFreeMemory(self.dev, b.memory, nil) -- freeing also unmaps
end

function Renderer:_makeImage(width: number, height: number, format: number, usage: number, props: number): any
	local a = vk.arena()
	local info = vk.new("VkImageCreateInfo", {
		sType = C.ST_IMAGE_CREATE_INFO,
		imageType = 1,
		format = format,
		width = width,
		height = height,
		depth = 1,
		mipLevels = 1,
		arrayLayers = 1,
		samples = 1,
		tiling = 0,
		usage = usage,
		sharingMode = 0,
		initialLayout = C.LAYOUT_UNDEFINED,
	}, a)
	local image = self:_create("vkCreateImage", info)
	local req = a:alloc(32)
	self.L.vkGetImageMemoryRequirements(self.dev, image, req)
	local mem = self:_allocMem(readU64(req, 0), req:readu32(16), props, a)
	vk.check(self.L.vkBindImageMemory(self.dev, image, mem, 0), "vkBindImageMemory")
	a:free()
	return { image = image, memory = mem }
end

function Renderer:_makeView(image: any, format: number, aspect: number): any
	local a = vk.arena()
	local info = vk.new("VkImageViewCreateInfo", {
		sType = C.ST_IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = 1,
		format = format,
		aspectMask = aspect,
		levelCount = 1,
		layerCount = 1,
	}, a)
	local view = self:_create("vkCreateImageView", info)
	a:free()
	return view
end

-- Records and submits a one-off command buffer, then waits for the queue.
function Renderer:_oneTime(record: (any) -> ())
	local L = self.L
	local cb = self.uploadCmd
	vk.check(L.vkResetCommandBuffer(cb, 0), "reset upload cmd")
	local a = vk.arena()
	local begin = vk.new("VkCommandBufferBeginInfo", {
		sType = C.ST_COMMAND_BUFFER_BEGIN_INFO,
		flags = C.CMD_ONE_TIME_SUBMIT,
	}, a)
	vk.check(L.vkBeginCommandBuffer(cb, begin), "begin upload cmd")
	record(cb)
	vk.check(L.vkEndCommandBuffer(cb), "end upload cmd")
	local cbs = vk.ptrArray({ cb }, a)
	local submit =
		vk.new("VkSubmitInfo", { sType = C.ST_SUBMIT_INFO, commandBufferCount = 1, pCommandBuffers = cbs }, a)
	vk.check(L.vkQueueSubmit(self.queue, 1, submit, nil), "upload submit")
	vk.check(L.vkQueueWaitIdle(self.queue), "upload wait")
	a:free()
end

function Renderer:_barrier(
	cb: any,
	image: any,
	oldL: number,
	newL: number,
	srcA: number,
	dstA: number,
	srcS: number,
	dstS: number,
	aspect: number
)
	local a = vk.arena()
	local barrier = vk.new("VkImageMemoryBarrier", {
		sType = C.ST_IMAGE_MEMORY_BARRIER,
		srcAccessMask = srcA,
		dstAccessMask = dstA,
		oldLayout = oldL,
		newLayout = newL,
		srcQueueFamilyIndex = C.SUBPASS_EXTERNAL,
		dstQueueFamilyIndex = C.SUBPASS_EXTERNAL, -- VK_QUEUE_FAMILY_IGNORED == ~0u
		image = image,
		aspectMask = aspect,
		levelCount = 1,
		layerCount = 1,
	}, a)
	self.L.vkCmdPipelineBarrier(cb, srcS, dstS, 0, 0, nil, 0, nil, 1, barrier)
	a:free()
end

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

function Renderer.new(glfw: any, window: any, options: Options?): any
	local o: Options = options or {}
	local self: any = setmetatable({}, Renderer)
	self.glfw, self.window = glfw, window
	self.L = vk.open(o.libraryPath)
	self.maxVerts = o.maxVertices or 65536
	self.clearColor = o.clearColor or { 0.09, 0.09, 0.11, 1 }
	self.textures, self.models = {}, {}
	self.preSubmit = {} -- functions called at the start of endFrame (e.g. glyph-atlas uploads)
	self.persist = vk.arena() -- native memory that lives as long as the renderer
	local L = self.L
	local a = vk.arena()

	-- persistent scratch memory (never freed until destroy)
	self.out = ffi.alloc(16, 8)
	self.cnt = ffi.alloc(16, 8)
	self.memProps = ffi.alloc(1024, 8)

	if not glfw.vulkanSupported() then
		error("vulkan: GLFW reports Vulkan is not supported on this system")
	end

	-- instance
	local extCount, extNames = glfw.getRequiredInstanceExtensions()
	local appInfo = vk.new("VkApplicationInfo", {
		sType = C.ST_APPLICATION_INFO,
		pApplicationName = a:cstr(o.appName or "zune-vkui"),
		apiVersion = C.API_VERSION_1_0,
	}, a)
	local instFields: any = {
		sType = C.ST_INSTANCE_CREATE_INFO,
		pApplicationInfo = appInfo,
		enabledExtensionCount = extCount,
		ppEnabledExtensionNames = extNames,
	}
	if o.validation then
		instFields.enabledLayerCount = 1
		instFields.ppEnabledLayerNames = vk.ptrArray({ a:cstr("VK_LAYER_KHRONOS_validation") }, a)
	end
	vk.check(L.vkCreateInstance(vk.new("VkInstanceCreateInfo", instFields, a), nil, self.out), "vkCreateInstance")
	self.instance = self.out:readptr(0)

	-- surface
	vk.check(glfw.createWindowSurface(self.instance, window, self.out), "glfwCreateWindowSurface")
	self.surface = self.out:readptr(0)

	-- physical device + queue family (graphics + present)
	vk.check(L.vkEnumeratePhysicalDevices(self.instance, self.cnt, nil), "enumerate devices")
	local n = self.cnt:readu32(0)
	if n == 0 then
		error("vulkan: no physical devices found")
	end
	local devs = a:alloc(8 * n)
	L.vkEnumeratePhysicalDevices(self.instance, self.cnt, devs)
	local props = a:alloc(1024)
	local bestScore = 0
	for i = 0, n - 1 do
		local pd = devs:readptr(i * 8)
		L.vkGetPhysicalDeviceQueueFamilyProperties(pd, self.cnt, nil)
		local fc = self.cnt:readu32(0)
		local fams = a:alloc(24 * math.max(fc, 1))
		L.vkGetPhysicalDeviceQueueFamilyProperties(pd, self.cnt, fams)
		for f = 0, fc - 1 do
			if bit32.band(fams:readu32(f * 24), C.QUEUE_GRAPHICS) ~= 0 then
				L.vkGetPhysicalDeviceSurfaceSupportKHR(pd, f, self.surface, self.cnt)
				if self.cnt:readu32(0) == 1 then
					L.vkGetPhysicalDeviceProperties(pd, props)
					local score = if props:readu32(16) == C.DEVICE_TYPE_DISCRETE then 2 else 1
					if score > bestScore then
						bestScore, self.pd, self.family = score, pd, f
					end
					break
				end
			end
		end
	end
	if not self.pd then
		error("vulkan: no device with a graphics+present queue found")
	end
	L.vkGetPhysicalDeviceMemoryProperties(self.pd, self.memProps)

	-- logical device
	local qci = vk.new("VkDeviceQueueCreateInfo", {
		sType = C.ST_DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = self.family,
		queueCount = 1,
		pQueuePriorities = vk.f32Array({ 1.0 }, a),
	}, a)
	local dci = vk.new("VkDeviceCreateInfo", {
		sType = C.ST_DEVICE_CREATE_INFO,
		queueCreateInfoCount = 1,
		pQueueCreateInfos = qci,
		enabledExtensionCount = 1,
		ppEnabledExtensionNames = vk.ptrArray({ a:cstr("VK_KHR_swapchain") }, a),
	}, a)
	vk.check(L.vkCreateDevice(self.pd, dci, nil, self.out), "vkCreateDevice")
	self.dev = self.out:readptr(0)
	L.vkGetDeviceQueue(self.dev, self.family, 0, self.out)
	self.queue = self.out:readptr(0)

	-- command pool + buffers (FRAMES for rendering, 1 for uploads)
	self.cmdPool = self:_create(
		"vkCreateCommandPool",
		vk.new("VkCommandPoolCreateInfo", {
			sType = C.ST_COMMAND_POOL_CREATE_INFO,
			flags = C.COMMAND_POOL_RESET,
			queueFamilyIndex = self.family,
		}, a)
	)
	local cbOut = a:alloc(8 * (FRAMES + 1))
	vk.check(
		L.vkAllocateCommandBuffers(
			self.dev,
			vk.new("VkCommandBufferAllocateInfo", {
				sType = C.ST_COMMAND_BUFFER_ALLOCATE_INFO,
				commandPool = self.cmdPool,
				level = 0,
				commandBufferCount = FRAMES + 1,
			}, a),
			cbOut
		),
		"vkAllocateCommandBuffers"
	)
	self.cmdBufs = {}
	for i = 1, FRAMES do
		self.cmdBufs[i] = cbOut:readptr((i - 1) * 8)
	end
	self.uploadCmd = cbOut:readptr(FRAMES * 8)

	-- per-frame sync objects and small native arrays
	self.imageAvailable, self.fences, self.fenceArrs = {}, {}, {}
	for i = 1, FRAMES do
		self.imageAvailable[i] = self:_create(
			"vkCreateSemaphore",
			vk.new("VkSemaphoreCreateInfo", { sType = C.ST_SEMAPHORE_CREATE_INFO }, a)
		)
		self.fences[i] = self:_create(
			"vkCreateFence",
			vk.new("VkFenceCreateInfo", { sType = C.ST_FENCE_CREATE_INFO, flags = C.FENCE_SIGNALED }, a)
		)
		self.fenceArrs[i] = ffi.alloc(8, 8)
		self.fenceArrs[i]:writeptr(0, self.fences[i])
	end
	self.frame = 1
	self.idxOut = ffi.alloc(8, 8)
	self.bufArr, self.offArr, self.setArr = ffi.alloc(8, 8), ffi.alloc(8, 8), ffi.alloc(8, 8)
	self.waitSemArr, self.sigSemArr, self.cbArr, self.swapArr =
		ffi.alloc(8, 8), ffi.alloc(8, 8), ffi.alloc(8, 8), ffi.alloc(8, 8)
	self.stageMask = ffi.alloc(8, 8)
	self.stageMask:writeu32(0, C.STAGE_COLOR_ATTACHMENT_OUTPUT)
	self.vp = ffi.alloc(24, 8)
	self.rect = ffi.alloc(16, 8)
	self.pcUI = ffi.alloc(8, 8)
	self.modeBuf = buffer.create(4) -- fragment push constant: interpolation mode
	self.hlScratch = buffer.create(96) -- push-constant copy used by the highlight passes

	-- sampler, descriptor layout/pool
	self.sampler = self:_create(
		"vkCreateSampler",
		vk.new("VkSamplerCreateInfo", {
			sType = C.ST_SAMPLER_CREATE_INFO,
			magFilter = 1,
			minFilter = 1,
			mipmapMode = 0,
			addressModeU = 2,
			addressModeV = 2,
			addressModeW = 2,
			maxAnisotropy = 1.0,
			maxLod = 1.0,
		}, a)
	)
	self.samplerNearest = self:_create(
		"vkCreateSampler",
		vk.new("VkSamplerCreateInfo", {
			sType = C.ST_SAMPLER_CREATE_INFO,
			magFilter = 0,
			minFilter = 0,
			mipmapMode = 0,
			addressModeU = 2,
			addressModeV = 2,
			addressModeW = 2,
			maxAnisotropy = 1.0,
			maxLod = 1.0,
		}, a)
	)
	local binding = vk.new("VkDescriptorSetLayoutBinding", {
		binding = 0,
		descriptorType = C.DESCRIPTOR_COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
		stageFlags = C.SHADER_FRAGMENT,
	}, a)
	self.dsl = self:_create(
		"vkCreateDescriptorSetLayout",
		vk.new("VkDescriptorSetLayoutCreateInfo", {
			sType = C.ST_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = 1,
			pBindings = binding,
		}, a)
	)
	local poolSize = vk.new(
		"VkDescriptorPoolSize",
		{ type = C.DESCRIPTOR_COMBINED_IMAGE_SAMPLER, descriptorCount = MAX_TEXTURES },
		a
	)
	self.descPool = self:_create(
		"vkCreateDescriptorPool",
		vk.new("VkDescriptorPoolCreateInfo", {
			sType = C.ST_DESCRIPTOR_POOL_CREATE_INFO,
			flags = C.DESCRIPTOR_POOL_FREE_SET,
			maxSets = MAX_TEXTURES,
			poolSizeCount = 1,
			pPoolSizes = poolSize,
		}, a)
	)

	-- depth format
	-- a format with a stencil aspect is preferred: model highlights (outline) need the stencil buffer
	self.depthFormat = 0
	self.hasStencil = false
	local fp = a:alloc(16)
	for _, fmt in { 130, 129, C.FORMAT_D32_SFLOAT, C.FORMAT_X8_D24, C.FORMAT_D16_UNORM } do -- 130 D32_SFLOAT_S8_UINT, 129 D24_UNORM_S8_UINT
		L.vkGetPhysicalDeviceFormatProperties(self.pd, fmt, fp)
		if bit32.btest(fp:readu32(4), 0x200) then -- optimalTilingFeatures & DEPTH_STENCIL_ATTACHMENT
			self.depthFormat = fmt
			self.hasStencil = fmt == 130 or fmt == 129
			break
		end
	end
	if self.depthFormat == 0 then
		error("vulkan: no supported depth format")
	end
	-- resets depth (1.0) and stencil (0) inside a model view
	self.clearAtt = vk.new("VkClearAttachment", {
		aspectMask = if self.hasStencil then 6 else C.ASPECT_DEPTH,
		colorAttachment = 0,
		v0 = 1.0,
		v1 = 0,
	}, self.persist)
	a:free()

	-- swapchain-dependent objects
	if not self:_createSwapchain() then
		error("vulkan: window has zero size at startup")
	end
	self:_createRenderPass()
	self:_createFramebuffers()
	self:_createPipelines(o.shaders)

	-- per-frame UI vertex buffers + CPU staging
	self.uiBufs = {}
	for i = 1, FRAMES do
		self.uiBufs[i] =
			self:_makeBuffer(self.maxVerts * UI_STRIDE, C.BUFFER_VERTEX, C.MEM_HOST_VISIBLE + C.MEM_HOST_COHERENT)
	end
	self.cpu = buffer.create(self.maxVerts * UI_STRIDE)
	self.vcount, self.cmds, self.clipStack = 0, {}, {}

	-- persistent per-frame structs (updated each frame)
	local p = self.persist
	self.clearValues = p:alloc(32)
	self.rpBegin = vk.new("VkRenderPassBeginInfo", {
		sType = C.ST_RENDER_PASS_BEGIN_INFO,
		renderPass = self.renderPass,
		clearValueCount = 2,
		pClearValues = self.clearValues,
	}, p)
	self.beginInfo = vk.new("VkCommandBufferBeginInfo", { sType = C.ST_COMMAND_BUFFER_BEGIN_INFO }, p)
	self.submit = vk.new("VkSubmitInfo", {
		sType = C.ST_SUBMIT_INFO,
		waitSemaphoreCount = 1,
		pWaitSemaphores = self.waitSemArr,
		pWaitDstStageMask = self.stageMask,
		commandBufferCount = 1,
		pCommandBuffers = self.cbArr,
		signalSemaphoreCount = 1,
		pSignalSemaphores = self.sigSemArr,
	}, p)
	self.present = vk.new("VkPresentInfoKHR", {
		sType = C.ST_PRESENT_INFO,
		waitSemaphoreCount = 1,
		pWaitSemaphores = self.sigSemArr,
		swapchainCount = 1,
		pSwapchains = self.swapArr,
		pImageIndices = self.idxOut,
	}, p)
	self.clearRect = vk.new("VkClearRect", { layerCount = 1 }, p)

	-- 1x1 white texture for untextured quads
	local white = buffer.create(4)
	buffer.fill(white, 0, 255)
	self.white = self:createTexture(1, 1, white)

	return self
end

--------------------------------------------------------------------------
-- Swapchain
--------------------------------------------------------------------------

function Renderer:_createSwapchain(): boolean
	local L = self.L
	local a = vk.arena()
	local caps = a:alloc(64)
	vk.check(L.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(self.pd, self.surface, caps), "surface capabilities")
	local minImg, maxImg = caps:readu32(0), caps:readu32(4)
	local w, h = caps:readu32(8), caps:readu32(12)
	if w == 0xFFFFFFFF then -- surface size determined by the swapchain
		w, h = self.window:getFramebufferSize()
		w = math.clamp(w, caps:readu32(16), caps:readu32(24))
		h = math.clamp(h, caps:readu32(20), caps:readu32(28))
	end
	if w == 0 or h == 0 then
		a:free()
		return false
	end

	if not self.format then
		vk.check(L.vkGetPhysicalDeviceSurfaceFormatsKHR(self.pd, self.surface, self.cnt, nil), "surface formats")
		local n = self.cnt:readu32(0)
		local fm = a:alloc(8 * n)
		L.vkGetPhysicalDeviceSurfaceFormatsKHR(self.pd, self.surface, self.cnt, fm)
		local pick = 0
		for i = 0, n - 1 do
			local fmt, cs = fm:readu32(i * 8), fm:readu32(i * 8 + 4)
			if cs == 0 and fmt == C.FORMAT_B8G8R8A8_UNORM then
				pick = i
				break
			elseif cs == 0 and fmt == C.FORMAT_R8G8B8A8_UNORM then
				pick = i
			end
		end
		self.format, self.colorSpace = fm:readu32(pick * 8), fm:readu32(pick * 8 + 4)
	end

	local alpha = 1
	local supportedAlpha = caps:readu32(44)
	for _, bitv in { 1, 2, 4, 8 } do
		if bit32.btest(supportedAlpha, bitv) then
			alpha = bitv
			break
		end
	end

	local imageCount = minImg + 1
	if maxImg > 0 and imageCount > maxImg then
		imageCount = maxImg
	end

	local info = vk.new("VkSwapchainCreateInfoKHR", {
		sType = C.ST_SWAPCHAIN_CREATE_INFO,
		surface = self.surface,
		minImageCount = imageCount,
		imageFormat = self.format,
		imageColorSpace = self.colorSpace,
		width = w,
		height = h,
		imageArrayLayers = 1,
		imageUsage = C.IMAGE_COLOR_ATTACHMENT,
		imageSharingMode = 0,
		preTransform = caps:readu32(40),
		compositeAlpha = alpha,
		presentMode = C.PRESENT_MODE_FIFO,
		clipped = 1,
	}, a)
	local sc: any = { width = w, height = h, images = {}, views = {}, fbs = {}, renderFinished = {} }
	vk.check(L.vkCreateSwapchainKHR(self.dev, info, nil, self.out), "vkCreateSwapchainKHR")
	sc.handle = self.out:readptr(0)

	vk.check(L.vkGetSwapchainImagesKHR(self.dev, sc.handle, self.cnt, nil), "swapchain images")
	local n = self.cnt:readu32(0)
	local imgs = a:alloc(8 * n)
	L.vkGetSwapchainImagesKHR(self.dev, sc.handle, self.cnt, imgs)
	for i = 1, n do
		sc.images[i] = imgs:readptr((i - 1) * 8)
		sc.views[i] = self:_makeView(sc.images[i], self.format, C.ASPECT_COLOR)
		sc.renderFinished[i] = self:_create(
			"vkCreateSemaphore",
			vk.new("VkSemaphoreCreateInfo", { sType = C.ST_SEMAPHORE_CREATE_INFO }, a)
		)
	end

	sc.depth = self:_makeImage(w, h, self.depthFormat, C.IMAGE_DEPTH_ATTACHMENT, C.MEM_DEVICE_LOCAL)
	sc.depthView = self:_makeView(sc.depth.image, self.depthFormat, if self.hasStencil then 6 else C.ASPECT_DEPTH)

	self.sc = sc
	self.width, self.height = w, h
	self.needsRecreate = false
	a:free()
	return true
end

function Renderer:_createFramebuffers()
	local a = vk.arena()
	local sc = self.sc
	for i, view in sc.views do
		sc.fbs[i] = self:_create(
			"vkCreateFramebuffer",
			vk.new("VkFramebufferCreateInfo", {
				sType = C.ST_FRAMEBUFFER_CREATE_INFO,
				renderPass = self.renderPass,
				attachmentCount = 2,
				pAttachments = vk.ptrArray({ view, sc.depthView }, a),
				width = sc.width,
				height = sc.height,
				layers = 1,
			}, a)
		)
	end
	a:free()
end

function Renderer:_destroySwapchain()
	local L, dev, sc = self.L, self.dev, self.sc
	if not sc then
		return
	end
	for _, fb in sc.fbs do
		L.vkDestroyFramebuffer(dev, fb, nil)
	end
	for _, v in sc.views do
		L.vkDestroyImageView(dev, v, nil)
	end
	for _, s in sc.renderFinished do
		L.vkDestroySemaphore(dev, s, nil)
	end
	L.vkDestroyImageView(dev, sc.depthView, nil)
	L.vkDestroyImage(dev, sc.depth.image, nil)
	L.vkFreeMemory(dev, sc.depth.memory, nil)
	L.vkDestroySwapchainKHR(dev, sc.handle, nil)
	self.sc = nil
end

function Renderer:_recreateSwapchain(): boolean
	self.L.vkDeviceWaitIdle(self.dev)
	self:_destroySwapchain()
	if not self:_createSwapchain() then
		return false
	end
	self:_createFramebuffers()
	return true
end

--------------------------------------------------------------------------
-- Render pass + pipelines
--------------------------------------------------------------------------

function Renderer:_createRenderPass()
	local a = vk.arena()
	local attachments = vk.newArray("VkAttachmentDescription", {
		{
			format = self.format,
			samples = 1,
			loadOp = 1,
			storeOp = 0,
			stencilLoadOp = 2,
			stencilStoreOp = 1,
			initialLayout = C.LAYOUT_UNDEFINED,
			finalLayout = C.LAYOUT_PRESENT_SRC,
		},
		{
			format = self.depthFormat,
			samples = 1,
			loadOp = 1,
			storeOp = 1,
			stencilLoadOp = if self.hasStencil then 1 else 2,
			stencilStoreOp = 1,
			initialLayout = C.LAYOUT_UNDEFINED,
			finalLayout = C.LAYOUT_DEPTH_ATTACHMENT,
		},
	}, a)
	local colorRef = vk.new("VkAttachmentReference", { attachment = 0, layout = C.LAYOUT_COLOR_ATTACHMENT }, a)
	local depthRef = vk.new("VkAttachmentReference", { attachment = 1, layout = C.LAYOUT_DEPTH_ATTACHMENT }, a)
	local subpass = vk.new("VkSubpassDescription", {
		pipelineBindPoint = 0,
		colorAttachmentCount = 1,
		pColorAttachments = colorRef,
		pDepthStencilAttachment = depthRef,
	}, a)
	local stages = C.STAGE_COLOR_ATTACHMENT_OUTPUT + C.STAGE_EARLY_FRAGMENT_TESTS
	local dep = vk.new("VkSubpassDependency", {
		srcSubpass = C.SUBPASS_EXTERNAL,
		dstSubpass = 0,
		srcStageMask = stages,
		dstStageMask = stages,
		srcAccessMask = 0,
		dstAccessMask = C.ACCESS_COLOR_WRITE + C.ACCESS_DEPTH_WRITE,
	}, a)
	self.renderPass = self:_create(
		"vkCreateRenderPass",
		vk.new("VkRenderPassCreateInfo", {
			sType = C.ST_RENDER_PASS_CREATE_INFO,
			attachmentCount = 2,
			pAttachments = attachments,
			subpassCount = 1,
			pSubpasses = subpass,
			dependencyCount = 1,
			pDependencies = dep,
		}, a)
	)
	a:free()
end

function Renderer:_shaderModule(code: any): any
	local a = vk.arena()
	local mem, size
	if type(code) == "buffer" then
		size = buffer.len(code)
		mem = a:alloc(size)
		mem:write(0, code, 0, size)
	else
		size = #code * 4
		mem = a:alloc(size, 4)
		for i, word in code do
			mem:writeu32((i - 1) * 4, word)
		end
	end
	local module = self:_create(
		"vkCreateShaderModule",
		vk.new("VkShaderModuleCreateInfo", {
			sType = C.ST_SHADER_MODULE_CREATE_INFO,
			codeSize = size,
			pCode = mem,
		}, a)
	)
	a:free()
	return module
end

function Renderer:_createPipeline(
	vs: any,
	fs: any,
	layout: any,
	stride: number,
	attrs: { { [string]: number } },
	blend: boolean,
	depth: boolean,
	cullMode: number?,
	depthStencil
): any
	local a = vk.arena()
	local L = self.L
	local entry = a:cstr("main")
	local stages = vk.newArray("VkPipelineShaderStageCreateInfo", {
		{ sType = C.ST_PIPELINE_SHADER_STAGE, stage = C.SHADER_VERTEX, module = vs, pName = entry },
		{ sType = C.ST_PIPELINE_SHADER_STAGE, stage = C.SHADER_FRAGMENT, module = fs, pName = entry },
	}, a)
	local bindingDesc = vk.new("VkVertexInputBindingDescription", { binding = 0, stride = stride, inputRate = 0 }, a)
	local attrDescs = vk.newArray("VkVertexInputAttributeDescription", attrs, a)
	local vertexInput = vk.new("VkPipelineVertexInputStateCreateInfo", {
		sType = C.ST_PIPELINE_VERTEX_INPUT,
		vertexBindingDescriptionCount = 1,
		pVertexBindingDescriptions = bindingDesc,
		vertexAttributeDescriptionCount = #attrs,
		pVertexAttributeDescriptions = attrDescs,
	}, a)
	local assembly =
		vk.new("VkPipelineInputAssemblyStateCreateInfo", { sType = C.ST_PIPELINE_INPUT_ASSEMBLY, topology = 3 }, a)
	local viewport = vk.new(
		"VkPipelineViewportStateCreateInfo",
		{ sType = C.ST_PIPELINE_VIEWPORT, viewportCount = 1, scissorCount = 1 },
		a
	)
	local rasterFields: { [string]: number } = {
		sType = C.ST_PIPELINE_RASTERIZATION,
		polygonMode = 0,
		cullMode = cullMode or 0,
		frontFace = 0,
		lineWidth = 1.0, -- frontFace 0 = counter-clockwise
	}

	depthStencil = depthStencil or {}

	for k, v in depthStencil do -- depthBias* entries of the override table belong to the rasterizer state
		if string.sub(k, 1, 9) == "depthBias" then
			rasterFields[k] = v
		end
	end
	local raster = vk.new("VkPipelineRasterizationStateCreateInfo", rasterFields, a)
	local ms = vk.new(
		"VkPipelineMultisampleStateCreateInfo",
		{ sType = C.ST_PIPELINE_MULTISAMPLE, rasterizationSamples = 1 },
		a
	)
	local dsFields: { [string]: number } = {
		sType = C.ST_PIPELINE_DEPTH_STENCIL,
		depthTestEnable = if depth then 1 else 0,
		depthWriteEnable = if depth then 1 else 0,
		depthCompareOp = 1,
		maxDepthBounds = 1.0,
	}
	for k, v in depthStencil do -- overrides: depth compare op, stencil state (f0..f6 = front, b0..b6 = back)
		if string.sub(k, 1, 9) ~= "depthBias" then
			dsFields[k] = v
		end
	end
	local ds = vk.new("VkPipelineDepthStencilStateCreateInfo", dsFields, a)
	local att = vk.new(
		"VkPipelineColorBlendAttachmentState",
		if blend
			then {
				blendEnable = 1,
				srcColorBlendFactor = 6,
				dstColorBlendFactor = 7,
				colorBlendOp = 0,
				srcAlphaBlendFactor = 1,
				dstAlphaBlendFactor = 7,
				alphaBlendOp = 0,
				colorWriteMask = 15,
			}
			else { blendEnable = 0, colorWriteMask = 15 },
		a
	)
	local cb = vk.new(
		"VkPipelineColorBlendStateCreateInfo",
		{ sType = C.ST_PIPELINE_COLOR_BLEND, attachmentCount = 1, pAttachments = att },
		a
	)
	local dyn = vk.new("VkPipelineDynamicStateCreateInfo", {
		sType = C.ST_PIPELINE_DYNAMIC,
		dynamicStateCount = 2,
		pDynamicStates = vk.u32Array({ 0, 1 }, a), -- VIEWPORT, SCISSOR
	}, a)
	local info = vk.new("VkGraphicsPipelineCreateInfo", {
		sType = C.ST_GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount = 2,
		pStages = stages,
		pVertexInputState = vertexInput,
		pInputAssemblyState = assembly,
		pViewportState = viewport,
		pRasterizationState = raster,
		pMultisampleState = ms,
		pDepthStencilState = ds,
		pColorBlendState = cb,
		pDynamicState = dyn,
		layout = layout,
		renderPass = self.renderPass,
		subpass = 0,
		basePipelineIndex = -1,
	}, a)
	vk.check(L.vkCreateGraphicsPipelines(self.dev, nil, 1, info, nil, self.out), "vkCreateGraphicsPipelines")
	local pipeline = self.out:readptr(0)
	a:free()
	return pipeline
end

local SHADER_FILES = {
	uiVert = "vert/ui.vert",
	uiFrag = "frag/ui.frag",
	modelVert = "vert/model.vert",
	modelFrag = "frag/model.frag",
	modelFragDither = "frag/model_dither.frag",
	highlightVert = "vert/highlight.vert",
	highlightFrag = "frag/highlight.frag",
}

-- Folder of the stock shader sources: "shaders" next to this file (found through the module's own path).
local function defaultShaderDir(): string
	local source = debug.info(1, "s")
	local dir = zune.fs.path.dirname((string.gsub(source, "^@", "")))
	return zune.fs.path.join(if dir and dir ~= "" then dir else ".", "shaders")
end

-- overrides: nil | "folder" holding the standard shader files | { [name]: "path" | SPIR-V buffer } (any subset; the rest come from the default folder)
--   or { libraryPath = ..., shaders = <either of the above> }
-- Shaders are GLSL (.vert / .frag, compiled by shader.luau) or precompiled .spv files.
function Renderer:_createPipelines(overrides: any)
	-- accepted: "folder" | { libraryPath = "shaderc library", shaders = "folder" | { name = "file" } } | { name = "file" } (per shader)
	local shaders = overrides
	if type(overrides) == "table" and (overrides.libraryPath ~= nil or overrides.shaders ~= nil) then
		if overrides.libraryPath then
			shaderLoader.setLibraryPath(overrides.libraryPath)
		end
		shaders = overrides.shaders
	end
	local dir = if type(shaders) == "string" then shaders else defaultShaderDir()
	local custom: { [string]: any } = if type(shaders) == "table" then shaders else {}
	local function code(name: string): any
		local entry = custom[name] or zune.fs.path.join(dir, SHADER_FILES[name])
		if type(entry) == "string" then
			return shaderLoader.load(entry, { cache = true })
		end
		return entry
	end
	local a = vk.arena()
	self.mods = {
		uiVert = self:_shaderModule(code("uiVert")),
		uiFrag = self:_shaderModule(code("uiFrag")),
		modelVert = self:_shaderModule(code("modelVert")),
		modelFrag = self:_shaderModule(code("modelFrag")),
		modelFragDither = self:_shaderModule(code("modelFragDither")),
		highlightVert = self:_shaderModule(code("highlightVert")),
		highlightFrag = self:_shaderModule(code("highlightFrag")),
	}

	self.uiLayout = self:_create(
		"vkCreatePipelineLayout",
		vk.new("VkPipelineLayoutCreateInfo", {
			sType = C.ST_PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount = 1,
			pSetLayouts = vk.ptrArray({ self.dsl }, a),
			pushConstantRangeCount = 2, -- vertex: screen scale (8 bytes); fragment: interpolation mode (4 bytes)
			pPushConstantRanges = vk.newArray("VkPushConstantRange", {
				{ stageFlags = C.SHADER_VERTEX, offset = 0, size = 8 },
				{ stageFlags = C.SHADER_FRAGMENT, offset = 8, size = 4 },
			}, a),
		}, a)
	)
	self.modelLayout = self:_create(
		"vkCreatePipelineLayout",
		vk.new("VkPipelineLayoutCreateInfo", {
			sType = C.ST_PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount = 1,
			pSetLayouts = vk.ptrArray({ self.dsl }, a),
			pushConstantRangeCount = 2, -- vertex: MVP + light + colour (96 bytes); fragment: interpolation mode (4 bytes)
			pPushConstantRanges = vk.newArray("VkPushConstantRange", {
				{ stageFlags = C.SHADER_VERTEX, offset = 0, size = 96 },
				{ stageFlags = C.SHADER_FRAGMENT, offset = 96, size = 4 },
			}, a),
		}, a)
	)

	self.uiPipeline = self:_createPipeline(self.mods.uiVert, self.mods.uiFrag, self.uiLayout, UI_STRIDE, {
		{ location = 0, binding = 0, format = C.FORMAT_R32G32_SFLOAT, offset = 0 },
		{ location = 1, binding = 0, format = C.FORMAT_R32G32_SFLOAT, offset = 8 },
		{ location = 2, binding = 0, format = C.FORMAT_R8G8B8A8_UNORM, offset = 16 },
	}, true, false)
	local modelAttrs = {
		{ location = 0, binding = 0, format = C.FORMAT_R32G32B32_SFLOAT, offset = 0 },
		{ location = 1, binding = 0, format = C.FORMAT_R32G32B32_SFLOAT, offset = 12 },
		{ location = 2, binding = 0, format = C.FORMAT_R32G32_SFLOAT, offset = 24 },
	}
	-- two variants: both sides drawn (default) and back-face culling (doubleSided = false)
	self.modelPipeline = self:_createPipeline(
		self.mods.modelVert,
		self.mods.modelFrag,
		self.modelLayout,
		MODEL_STRIDE,
		modelAttrs,
		true,
		true,
		0
	)
	self.modelPipelineCull = self:_createPipeline(
		self.mods.modelVert,
		self.mods.modelFrag,
		self.modelLayout,
		MODEL_STRIDE,
		modelAttrs,
		true,
		true,
		2
	)
	-- dot-pattern transparency variants (ordered dither with discard: no blending, so no draw-order problems)
	self.modelPipelineDither = self:_createPipeline(
		self.mods.modelVert,
		self.mods.modelFragDither,
		self.modelLayout,
		MODEL_STRIDE,
		modelAttrs,
		false,
		true,
		0
	)
	self.modelPipelineDitherCull = self:_createPipeline(
		self.mods.modelVert,
		self.mods.modelFragDither,
		self.modelLayout,
		MODEL_STRIDE,
		modelAttrs,
		false,
		true,
		2
	)
	-- highlight: (a) fill = the model again with a flat colour (depthMode "Occluded": only where the model is visible; "AlwaysOnTop": no depth test), marks the
	-- stencil buffer with 1; (b) outline = the silhouette grown by a few pixels, drawn only where the stencil is still 0 (outside the model).
	-- Stencil ops: KEEP 0, INCREMENT_AND_CLAMP 3; compare op EQUAL 2.
	if self.hasStencil then
		local function stencil(passOp: number, compareOp: number, reference: number): { [string]: number }
			return {
				stencilTestEnable = 1,
				f0 = 0,
				f1 = passOp,
				f2 = 0,
				f3 = compareOp,
				f4 = 0xFF,
				f5 = 0xFF,
				f6 = reference,
				b0 = 0,
				b1 = passOp,
				b2 = 0,
				b3 = compareOp,
				b4 = 0xFF,
				b5 = 0xFF,
				b6 = reference,
			}
		end
		-- every pixel is painted once: the first fragment that reaches it (stencil 0) increments the stencil to 1
		local fill = stencil(3, 2, 0)
		fill.depthTestEnable, fill.depthWriteEnable, fill.depthCompareOp = 1, 0, 3 -- "Occluded": LEQUAL, no depth writes
		-- The model is drawn by another shader, so equal depth is not guaranteed bit for bit (z-fighting). Pull the fill towards the camera
		-- by a few depth units + slope, far less than the gap to any surface that is really behind.
		fill.depthBiasEnable, fill.depthBiasConstantFactor, fill.depthBiasSlopeFactor = 1, -16.0, -2.0
		local fillTop = stencil(3, 2, 0)
		fillTop.depthTestEnable, fillTop.depthWriteEnable = 0, 0 -- "AlwaysOnTop": no depth test at all
		local outline = stencil(3, 2, 0)
		outline.depthTestEnable, outline.depthWriteEnable = 0, 0
		local hv, hf, ml = self.mods.highlightVert, self.mods.highlightFrag, self.modelLayout
		self.hlFillPipeline = self:_createPipeline(hv, hf, ml, MODEL_STRIDE, modelAttrs, true, true, 0, fill)
		self.hlFillPipelineCull = self:_createPipeline(hv, hf, ml, MODEL_STRIDE, modelAttrs, true, true, 2, fill)
		self.hlFillTopPipeline = self:_createPipeline(hv, hf, ml, MODEL_STRIDE, modelAttrs, true, false, 0, fillTop)
		self.hlFillTopPipelineCull = self:_createPipeline(hv, hf, ml, MODEL_STRIDE, modelAttrs, true, false, 2, fillTop)
		self.hlOutlinePipeline = self:_createPipeline(hv, hf, ml, MODEL_STRIDE, modelAttrs, true, false, 0, outline)
		self.hlOutlinePipelineCull = self:_createPipeline(hv, hf, ml, MODEL_STRIDE, modelAttrs, true, false, 2, outline)
	end
	a:free()
end

--------------------------------------------------------------------------
-- Textures and models
--------------------------------------------------------------------------

-- rgba: buffer of width*height*4 bytes (non-premultiplied RGBA8).
function Renderer:_makeSet(view: any, sampler: any): any
	local L = self.L
	local a = vk.arena()
	vk.check(
		L.vkAllocateDescriptorSets(
			self.dev,
			vk.new("VkDescriptorSetAllocateInfo", {
				sType = C.ST_DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool = self.descPool,
				descriptorSetCount = 1,
				pSetLayouts = vk.ptrArray({ self.dsl }, a),
			}, a),
			self.out
		),
		"vkAllocateDescriptorSets (too many textures?)"
	)
	local set = self.out:readptr(0)
	local imageInfo = vk.new(
		"VkDescriptorImageInfo",
		{ sampler = sampler, imageView = view, imageLayout = C.LAYOUT_SHADER_READ_ONLY },
		a
	)
	L.vkUpdateDescriptorSets(
		self.dev,
		1,
		vk.new("VkWriteDescriptorSet", {
			sType = C.ST_WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 0,
			descriptorCount = 1,
			descriptorType = C.DESCRIPTOR_COMBINED_IMAGE_SAMPLER,
			pImageInfo = imageInfo,
		}, a),
		0,
		nil
	)
	a:free()
	return set
end

function Renderer:createTexture(width: number, height: number, rgba: buffer): any
	local size = width * height * 4
	assert(buffer.len(rgba) >= size, "createTexture: rgba buffer too small")
	local L = self.L
	local staging = self:_makeBuffer(size, C.BUFFER_TRANSFER_SRC, C.MEM_HOST_VISIBLE + C.MEM_HOST_COHERENT)
	staging.mapped:write(0, rgba, 0, size)

	local img = self:_makeImage(
		width,
		height,
		C.FORMAT_R8G8B8A8_UNORM,
		C.IMAGE_TRANSFER_DST + C.IMAGE_SAMPLED,
		C.MEM_DEVICE_LOCAL
	)
	local view = self:_makeView(img.image, C.FORMAT_R8G8B8A8_UNORM, C.ASPECT_COLOR)

	self:_oneTime(function(cb)
		self:_barrier(
			cb,
			img.image,
			C.LAYOUT_UNDEFINED,
			C.LAYOUT_TRANSFER_DST,
			0,
			C.ACCESS_TRANSFER_WRITE,
			C.STAGE_TOP_OF_PIPE,
			C.STAGE_TRANSFER,
			C.ASPECT_COLOR
		)
		local a = vk.arena()
		local region = vk.new(
			"VkBufferImageCopy",
			{ aspectMask = C.ASPECT_COLOR, layerCount = 1, width = width, height = height, depth = 1 },
			a
		)
		L.vkCmdCopyBufferToImage(cb, staging.buffer, img.image, C.LAYOUT_TRANSFER_DST, 1, region)
		a:free()
		self:_barrier(
			cb,
			img.image,
			C.LAYOUT_TRANSFER_DST,
			C.LAYOUT_SHADER_READ_ONLY,
			C.ACCESS_TRANSFER_WRITE,
			C.ACCESS_SHADER_READ,
			C.STAGE_TRANSFER,
			C.STAGE_FRAGMENT_SHADER,
			C.ASPECT_COLOR
		)
	end)
	self:_destroyBuffer(staging)

	local set = self:_makeSet(view, self.sampler)

	local tex =
		setmetatable({ renderer = self, width = width, height = height, image = img, view = view, set = set }, Texture)
	self.textures[tex] = true
	return tex
end

-- data: PNG file contents (string or buffer). Needs zune.serde.zlib.
function Renderer:loadImage(data: string | buffer): any
	local png = require("./png")
	local w, h, rgba = png.decode(data)
	return self:createTexture(w, h, rgba)
end

function Renderer:loadImageFile(path: string): any
	return self:loadImage(zune.fs.readFile(path, true))
end

-- Overwrites a sub-rectangle of an existing texture (RGBA8, tightly packed w*h*4 bytes).
-- Waits for the GPU queue to go idle first, so call it sparingly (the text engine batches its uploads).
function Renderer:updateTexture(tex: any, x: number, y: number, w: number, h: number, rgba: buffer)
	local L = self.L
	local size = w * h * 4
	assert(buffer.len(rgba) >= size, "updateTexture: rgba buffer too small")
	vk.check(L.vkQueueWaitIdle(self.queue), "vkQueueWaitIdle")
	local staging = self:_makeBuffer(size, C.BUFFER_TRANSFER_SRC, C.MEM_HOST_VISIBLE + C.MEM_HOST_COHERENT)
	staging.mapped:write(0, rgba, 0, size)
	self:_oneTime(function(cb)
		self:_barrier(
			cb,
			tex.image.image,
			C.LAYOUT_SHADER_READ_ONLY,
			C.LAYOUT_TRANSFER_DST,
			C.ACCESS_SHADER_READ,
			C.ACCESS_TRANSFER_WRITE,
			C.STAGE_FRAGMENT_SHADER,
			C.STAGE_TRANSFER,
			C.ASPECT_COLOR
		)
		local a = vk.arena()
		local region = vk.new("VkBufferImageCopy", {
			aspectMask = C.ASPECT_COLOR,
			layerCount = 1,
			ox = x,
			oy = y,
			width = w,
			height = h,
			depth = 1,
		}, a)
		L.vkCmdCopyBufferToImage(cb, staging.buffer, tex.image.image, C.LAYOUT_TRANSFER_DST, 1, region)
		a:free()
		self:_barrier(
			cb,
			tex.image.image,
			C.LAYOUT_TRANSFER_DST,
			C.LAYOUT_SHADER_READ_ONLY,
			C.ACCESS_TRANSFER_WRITE,
			C.ACCESS_SHADER_READ,
			C.STAGE_TRANSFER,
			C.STAGE_FRAGMENT_SHADER,
			C.ASPECT_COLOR
		)
	end)
	self:_destroyBuffer(staging)
end

-- Descriptor set that samples this texture with nearest-neighbour filtering (created on first use).
function Texture:nearestSet(): any
	if not self.setNearest then
		self.setNearest = self.renderer:_makeSet(self.view, self.renderer.samplerNearest)
	end
	return self.setNearest
end

function Texture:destroy()
	local r = self.renderer
	if not r.textures[self] then
		return
	end
	r.textures[self] = nil
	local L = r.L
	L.vkDeviceWaitIdle(r.dev)
	local a = vk.arena()
	L.vkFreeDescriptorSets(r.dev, r.descPool, 1, vk.ptrArray({ self.set }, a))
	if self.setNearest then
		L.vkFreeDescriptorSets(r.dev, r.descPool, 1, vk.ptrArray({ self.setNearest }, a))
	end
	a:free()
	L.vkDestroyImageView(r.dev, self.view, nil)
	L.vkDestroyImage(r.dev, self.image.image, nil)
	L.vkFreeMemory(r.dev, self.image.memory, nil)
end

-- mesh: result of obj.parse / mesh.fromIndexed { vertices: buffer(pos+normal+uv f32, 32 bytes/vertex), vertexCount, center, radius },
-- or a raw parser result { vertices = {{vx,vy,vz,nx,ny,nz,tu,tv,tw}}, faces = {{a,b,c}} } (meshOptions -> mesh.fromIndexed)
function Renderer:createModel(mesh: any, meshOptions: any?): any
	if mesh.faces and not mesh.vertexCount then -- indexed {vertices, faces} from a parser
		mesh = require("@self/mesh").fromIndexed(mesh, meshOptions)
	end
	local size = mesh.vertexCount * MODEL_STRIDE
	local b = self:_makeBuffer(size, C.BUFFER_VERTEX, C.MEM_HOST_VISIBLE + C.MEM_HOST_COHERENT)
	b.mapped:write(0, mesh.vertices, 0, size)
	local model = setmetatable({
		renderer = self,
		buf = b,
		vertexCount = mesh.vertexCount,
		center = mesh.center,
		radius = mesh.radius,
	}, Model)
	self.models[model] = true
	return model
end

function Model:destroy()
	local r = self.renderer
	if not r.models[self] then
		return
	end
	r.models[self] = nil
	r.L.vkDeviceWaitIdle(r.dev)
	r:_destroyBuffer(self.buf)
end

--------------------------------------------------------------------------
-- Frame loop / drawing API
--------------------------------------------------------------------------

function Renderer:setClearColor(r: number, g: number, b: number, a: number?)
	self.clearColor = { r, g, b, a or 1 }
end

function Renderer:getSize(): (number?, number?)
	return self.width, self.height
end

function Renderer:waitIdle()
	self.L.vkDeviceWaitIdle(self.dev)
end

-- Returns false when the frame must be skipped (minimized / swapchain being rebuilt).
function Renderer:beginFrame(): boolean
	local L, dev = self.L, self.dev
	local fbw, fbh = self.window:getFramebufferSize()
	if fbw == 0 or fbh == 0 then
		return false
	end
	if self.needsRecreate or fbw ~= self.width or fbh ~= self.height then
		if not self:_recreateSwapchain() then
			return false
		end
	end

	local f = self.frame
	vk.check(L.vkWaitForFences(dev, 1, self.fenceArrs[f], 1, vk.U64_MAX), "vkWaitForFences")
	local r = L.vkAcquireNextImageKHR(dev, self.sc.handle, vk.U64_MAX, self.imageAvailable[f], nil, self.idxOut)
	if r == C.ERROR_OUT_OF_DATE then
		self.needsRecreate = true
		return false
	end
	vk.check(r, "vkAcquireNextImageKHR")
	if r == C.SUBOPTIMAL then
		self.needsRecreate = true -- finish this frame, rebuild afterwards
	end
	vk.check(L.vkResetFences(dev, 1, self.fenceArrs[f]), "vkResetFences")

	self.imageIndex = self.idxOut:readu32(0)
	self.vcount, self.cur = 0, nil
	table.clear(self.cmds)
	table.clear(self.clipStack)
	self.clip = { 0, 0, self.width, self.height }
	self.frameActive = true
	return true
end

function Renderer:pushClip(x: number, y: number, w: number, h: number)
	table.insert(self.clipStack, self.clip)
	local c = self.clip
	local x0, y0 = math.max(c[1], x), math.max(c[2], y)
	local x1, y1 = math.min(c[1] + c[3], x + w), math.min(c[2] + c[4], y + h)
	self.clip = { x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0) }
end

-- Replaces the whole clip state with an absolute rectangle {x, y, w, h}. Reuse the same table for widgets that
-- share a clip: quads with the identical table are batched into one draw call.
function Renderer:setClipRect(rect: { number })
	self.clip = rect
end

function Renderer:popClip()
	self.clip = table.remove(self.clipStack) or { 0, 0, self.width, self.height }
end

function Renderer:quad(
	x: number,
	y: number,
	w: number,
	h: number,
	r: number,
	g: number,
	b: number,
	a: number,
	tex: any?,
	u0: number?,
	v0: number?,
	u1: number?,
	v1: number?,
	interp: number?
)
	if w <= 0 or h <= 0 or a <= 0 or self.vcount + 6 > self.maxVerts then
		return
	end
	tex = tex or self.white
	local cur = self.cur
	interp = interp or 0
	if not cur or cur.tex ~= tex or cur.clip ~= self.clip or cur.interp ~= interp then
		cur = { kind = "quads", tex = tex, interp = interp, clip = self.clip, first = self.vcount, count = 0 }
		table.insert(self.cmds, cur)
		self.cur = cur
	end
	local U0, V0, U1, V1 = u0 or 0, v0 or 0, u1 or 1, v1 or 1
	local col = packColor(r, g, b, a)
	local buf = self.cpu
	local off = self.vcount * UI_STRIDE
	local x2, y2 = x + w, y + h
	local function vert(px: number, py: number, u: number, v: number)
		buffer.writef32(buf, off, px)
		buffer.writef32(buf, off + 4, py)
		buffer.writef32(buf, off + 8, u)
		buffer.writef32(buf, off + 12, v)
		buffer.writeu32(buf, off + 16, col)
		off += UI_STRIDE
	end
	vert(x, y, U0, V0)
	vert(x2, y, U1, V0)
	vert(x, y2, U0, V1)
	vert(x2, y, U1, V0)
	vert(x2, y2, U1, V1)
	vert(x, y2, U0, V1)
	cur.count += 6
	self.vcount += 6
end

--[[
	Draws a model inside the pixel rect (x, y, w, h), clipped by the current clip.
	mvp:   16 numbers, column-major (clip-space transform incl. Vulkan Y flip)
	light: {x, y, z} light direction in *object space* (unit length)
	color: {r, g, b, a}   (multiplied with the texture)
	texture: optional Texture (nil = untextured / white)
	highlight: nil | { fill = {r,g,b,a}, outline = {r,g,b,a}, thickness = px, onTop = boolean (true = depthMode "AlwaysOnTop") }  (needs a depth format with stencil; ignored otherwise)
	method: "blend" (default, alpha blending) | "dither" (4x4 dot pattern, alpha picks how many dots; alpha-only texture cutouts included)
	interp: texture interpolation id: 0 Linear (default), 1 Nearest Neighbor, 2 Cubic (Catmull-Rom), 3 Cubic B-spline, 4 Mitchell, 5 Lanczos-3
	doubleSided: false = back faces are culled (counter-clockwise triangles are front faces), anything else = drawn
]]
function Renderer:drawModel(
	model: any,
	x: number,
	y: number,
	w: number,
	h: number,
	mvp: { number },
	light: { number },
	color: { number },
	texture: any?,
	doubleSided: boolean?,
	interp: number?,
	method: string?,
	highlight: any?
)
	local pc = buffer.create(96)
	for i = 1, 16 do
		buffer.writef32(pc, (i - 1) * 4, mvp[i])
	end
	for i = 1, 3 do
		buffer.writef32(pc, 64 + (i - 1) * 4, light[i])
	end
	for i = 1, 4 do
		buffer.writef32(pc, 80 + (i - 1) * 4, color[i])
	end
	table.insert(self.cmds, {
		kind = "model",
		model = model,
		rect = { x, y, w, h },
		clip = self.clip,
		pc = pc,
		tex = texture or self.white,
		cull = (doubleSided == false),
		interp = interp or 0,
		dither = (method == "dither"),
		hl = highlight,
	})
	self.cur = nil
end

local function clipToInts(clip: { number }, W: number, H: number): (number?, number?, number?, number?)
	local x0, y0 = math.max(0, math.floor(clip[1])), math.max(0, math.floor(clip[2]))
	local x1, y1 = math.min(W, math.ceil(clip[1] + clip[3])), math.min(H, math.ceil(clip[2] + clip[4]))
	return x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0)
end

function Renderer:_setScissor(cb: any, x: number, y: number, w: number, h: number)
	self.rect:writei32(0, x)
	self.rect:writei32(4, y)
	self.rect:writeu32(8, w)
	self.rect:writeu32(12, h)
	self.L.vkCmdSetScissor(cb, 0, 1, self.rect)
end

function Renderer:_setViewport(cb: any, x: number, y: number, w: number, h: number)
	local vp = self.vp
	vp:writef32(0, x)
	vp:writef32(4, y)
	vp:writef32(8, w)
	vp:writef32(12, h)
	vp:writef32(16, 0.0)
	vp:writef32(20, 1.0)
	self.L.vkCmdSetViewport(cb, 0, 1, vp)
end

-- Fill + outline highlight for a model that was just drawn (same vertex buffer / descriptor set are still bound).
function Renderer:_drawHighlight(cb: any, cmd: any, viewW: number, viewH: number)
	local L = self.L
	local hl = cmd.hl
	local pc, scratch = cmd.pc, self.hlScratch
	local count = cmd.model.vertexCount

	local function setColor(c: { number })
		for i = 1, 4 do
			buffer.writef32(scratch, 76 + i * 4, c[i]) -- colour lives at byte 80
		end
	end

	-- pass 1: flat fill over the visible surface; also writes stencil = 1 there
	buffer.copy(scratch, 0, pc, 0, 96)
	setColor(hl.fill)
	local fillPipeline = if hl.onTop
		then (if cmd.cull then self.hlFillTopPipelineCull else self.hlFillTopPipeline)
		else (if cmd.cull then self.hlFillPipelineCull else self.hlFillPipeline)
	L.vkCmdBindPipeline(cb, 0, fillPipeline)
	L.vkCmdPushConstants(cb, self.modelLayout, C.SHADER_VERTEX, 0, 96, scratch)
	L.vkCmdDraw(cb, count, 1, 0, 0)

	-- pass 2: silhouette grown by `thickness` pixels (model redrawn shifted along a ring of screen-space offsets); stencil makes every
	-- pixel get painted once, and never inside the model
	local t = hl.thickness
	if hl.outline[4] > 0 and t > 0 and viewW > 0 and viewH > 0 then
		L.vkCmdBindPipeline(cb, 0, if cmd.cull then self.hlOutlinePipelineCull else self.hlOutlinePipeline)
		local function ring(radius: number, n: number, phase: number)
			for k = 0, n - 1 do
				local angle = phase + k * 2 * math.pi / n
				local ox, oy = 2 * radius * math.cos(angle) / viewW, 2 * radius * math.sin(angle) / viewH
				for col = 0, 3 do -- clip.xy += offset * clip.w, applied to every column of the MVP
					local base = col * 16
					local w = buffer.readf32(pc, base + 12)
					buffer.writef32(scratch, base, buffer.readf32(pc, base) + ox * w)
					buffer.writef32(scratch, base + 4, buffer.readf32(pc, base + 4) + oy * w)
					buffer.writef32(scratch, base + 8, buffer.readf32(pc, base + 8))
					buffer.writef32(scratch, base + 12, w)
				end
				L.vkCmdPushConstants(cb, self.modelLayout, C.SHADER_VERTEX, 0, 96, scratch)
				L.vkCmdDraw(cb, count, 1, 0, 0)
			end
		end
		buffer.copy(scratch, 0, pc, 0, 96)
		setColor(hl.outline)
		ring(t, 16, 0)
		if t >= 3 then
			ring(t * 0.5, 12, math.pi / 12) -- inner ring so thick outlines have no gaps
		end
	end
end

function Renderer:endFrame()
	if not self.frameActive then
		return
	end
	self.frameActive = false
	local L = self.L
	local f = self.frame
	local cb = self.cmdBufs[f]
	local W, H = self.width, self.height
	local sc = self.sc
	local ui = self.uiBufs[f]

	for _, hook in self.preSubmit do
		hook()
	end

	if self.vcount > 0 then
		ui.mapped:write(0, self.cpu, 0, self.vcount * UI_STRIDE)
	end

	-- clear values: colour + depth(1.0, 0)
	local cv = self.clearValues
	for i = 1, 4 do
		cv:writef32((i - 1) * 4, self.clearColor[i])
	end
	cv:writef32(16, 1.0)
	cv:writeu32(20, 0)

	vk.check(L.vkResetCommandBuffer(cb, 0), "vkResetCommandBuffer")
	vk.check(L.vkBeginCommandBuffer(cb, self.beginInfo), "vkBeginCommandBuffer")
	vk.set(self.rpBegin, "VkRenderPassBeginInfo", { framebuffer = sc.fbs[self.imageIndex + 1], width = W, height = H })
	L.vkCmdBeginRenderPass(cb, self.rpBegin, 0)
	self:_setViewport(cb, 0, 0, W, H)
	self:_setScissor(cb, 0, 0, W, H)

	local bound: string? = nil
	local boundTex: any = nil
	local lastUiMode: number? = nil

	local function useUI()
		if bound == "ui" then
			return
		end
		bound, boundTex, lastUiMode = "ui", nil, nil
		L.vkCmdBindPipeline(cb, 0, self.uiPipeline)
		self.pcUI:writef32(0, 2 / W)
		self.pcUI:writef32(4, 2 / H)
		L.vkCmdPushConstants(cb, self.uiLayout, C.SHADER_VERTEX, 0, 8, self.pcUI)
		self.bufArr:writeptr(0, ui.buffer)
		self.offArr:writeu64(0, 0)
		L.vkCmdBindVertexBuffers(cb, 0, 1, self.bufArr, self.offArr)
	end

	for _, cmd in self.cmds do
		local cx, cy, cw, ch = clipToInts(cmd.clip, W, H)
		if cw > 0 and ch > 0 then
			if cmd.kind == "quads" then
				if cmd.count > 0 then
					useUI()
					self:_setScissor(cb, cx, cy, cw, ch)
					local wantSet = if cmd.interp == 1 then cmd.tex:nearestSet() else cmd.tex.set
					if lastUiMode ~= cmd.interp then
						lastUiMode = cmd.interp
						buffer.writeu32(self.modeBuf, 0, cmd.interp)
						L.vkCmdPushConstants(cb, self.uiLayout, C.SHADER_FRAGMENT, 8, 4, self.modeBuf)
					end
					if boundTex ~= wantSet then
						boundTex = wantSet
						self.setArr:writeptr(0, wantSet)
						L.vkCmdBindDescriptorSets(cb, 0, self.uiLayout, 0, 1, self.setArr, 0, nil)
					end
					L.vkCmdDraw(cb, cmd.count, 1, cmd.first, 0)
				end
			else -- model
				local mx, my, mw, mh = cmd.rect[1], cmd.rect[2], cmd.rect[3], cmd.rect[4]
				local vx0, vy0 = math.max(cx, math.floor(mx)), math.max(cy, math.floor(my))
				local vx1, vy1 = math.min(cx + cw, math.ceil(mx + mw)), math.min(cy + ch, math.ceil(my + mh))
				if vx1 > vx0 and vy1 > vy0 then
					bound, boundTex = "model", nil
					local pipeline = if cmd.dither
						then (if cmd.cull then self.modelPipelineDitherCull else self.modelPipelineDither)
						else (if cmd.cull then self.modelPipelineCull else self.modelPipeline)
					L.vkCmdBindPipeline(cb, 0, pipeline)
					self:_setViewport(cb, mx, my, mw, mh)
					self:_setScissor(cb, vx0, vy0, vx1 - vx0, vy1 - vy0)
					vk.set(self.clearRect, "VkClearRect", { x = vx0, y = vy0, width = vx1 - vx0, height = vy1 - vy0 })
					L.vkCmdClearAttachments(cb, 1, self.clearAtt, 1, self.clearRect) -- reset depth inside the view
					L.vkCmdPushConstants(cb, self.modelLayout, C.SHADER_VERTEX, 0, 96, cmd.pc)
					self.setArr:writeptr(0, if cmd.interp == 1 then cmd.tex:nearestSet() else cmd.tex.set)
					buffer.writeu32(self.modeBuf, 0, cmd.interp)
					L.vkCmdPushConstants(cb, self.modelLayout, C.SHADER_FRAGMENT, 96, 4, self.modeBuf)
					L.vkCmdBindDescriptorSets(cb, 0, self.modelLayout, 0, 1, self.setArr, 0, nil)
					self.bufArr:writeptr(0, cmd.model.buf.buffer)
					self.offArr:writeu64(0, 0)
					L.vkCmdBindVertexBuffers(cb, 0, 1, self.bufArr, self.offArr)
					L.vkCmdDraw(cb, cmd.model.vertexCount, 1, 0, 0)
					if cmd.hl and self.hasStencil then
						self:_drawHighlight(cb, cmd, mw, mh)
					end
					self:_setViewport(cb, 0, 0, W, H)
				end
			end
		end
	end

	L.vkCmdEndRenderPass(cb)
	vk.check(L.vkEndCommandBuffer(cb), "vkEndCommandBuffer")

	self.waitSemArr:writeptr(0, self.imageAvailable[f])
	self.sigSemArr:writeptr(0, sc.renderFinished[self.imageIndex + 1])
	self.cbArr:writeptr(0, cb)
	vk.check(L.vkQueueSubmit(self.queue, 1, self.submit, self.fences[f]), "vkQueueSubmit")

	self.swapArr:writeptr(0, sc.handle)
	local r = L.vkQueuePresentKHR(self.queue, self.present)
	if r == C.ERROR_OUT_OF_DATE or r == C.SUBOPTIMAL then
		self.needsRecreate = true
	else
		vk.check(r, "vkQueuePresentKHR")
	end

	self.frame = self.frame % FRAMES + 1
end

--------------------------------------------------------------------------
-- Teardown
--------------------------------------------------------------------------

function Renderer:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	local L, dev = self.L, self.dev
	L.vkDeviceWaitIdle(dev)
	for t in self.textures do
		t:destroy()
	end
	for m in self.models do
		m:destroy()
	end
	for _, b in self.uiBufs do
		self:_destroyBuffer(b)
	end
	L.vkDestroyPipeline(dev, self.uiPipeline, nil)
	L.vkDestroyPipeline(dev, self.modelPipeline, nil)
	L.vkDestroyPipeline(dev, self.modelPipelineCull, nil)
	L.vkDestroyPipeline(dev, self.modelPipelineDither, nil)
	L.vkDestroyPipeline(dev, self.modelPipelineDitherCull, nil)
	if self.hasStencil then
		L.vkDestroyPipeline(dev, self.hlFillPipeline, nil)
		L.vkDestroyPipeline(dev, self.hlFillPipelineCull, nil)
		L.vkDestroyPipeline(dev, self.hlFillTopPipeline, nil)
		L.vkDestroyPipeline(dev, self.hlFillTopPipelineCull, nil)
		L.vkDestroyPipeline(dev, self.hlOutlinePipeline, nil)
		L.vkDestroyPipeline(dev, self.hlOutlinePipelineCull, nil)
	end
	L.vkDestroyPipelineLayout(dev, self.uiLayout, nil)
	L.vkDestroyPipelineLayout(dev, self.modelLayout, nil)
	for _, m in self.mods do
		L.vkDestroyShaderModule(dev, m, nil)
	end
	self:_destroySwapchain()
	L.vkDestroyRenderPass(dev, self.renderPass, nil)
	L.vkDestroyDescriptorPool(dev, self.descPool, nil)
	L.vkDestroyDescriptorSetLayout(dev, self.dsl, nil)
	L.vkDestroySampler(dev, self.sampler, nil)
	L.vkDestroySampler(dev, self.samplerNearest, nil)
	for i = 1, FRAMES do
		L.vkDestroySemaphore(dev, self.imageAvailable[i], nil)
		L.vkDestroyFence(dev, self.fences[i], nil)
	end
	L.vkDestroyCommandPool(dev, self.cmdPool, nil)
	L.vkDestroyDevice(dev, nil)
	L.vkDestroySurfaceKHR(self.instance, self.surface, nil)
	L.vkDestroyInstance(self.instance, nil)
end

return Renderer
