--[[
	vk.luau - minimal Vulkan 1.0 bindings for Zune (zune.ffi)

	* All Vulkan handles are treated as `pointer` (correct on 64-bit platforms).
	* VkDeviceSize / uint64 arguments are declared u64; Zune accepts a number or an
	  8-byte buffer for them (use vk.U64_MAX for UINT64_MAX).
	* Structs are plain native memory laid out by a tiny C-layout calculator
	  (see defStruct). Unknown field names throw, which catches typos.

	Only the subset needed by renderer.luau is bound.
]]

local ffi = zune.ffi
local T = ffi.types
local ptr, i32, u32, u64, f32, void = T.pointer, T.i32, T.u32, T.u64, T.float, T.void

local vk = {}

local function fn(returns: any, args: { any })
	return { returns = returns, args = args }
end

--------------------------------------------------------------------------
-- Constants (only what we use)
--------------------------------------------------------------------------

vk.C = {
	SUCCESS = 0,
	SUBOPTIMAL = 1000001003,
	ERROR_OUT_OF_DATE = -1000001004,
	API_VERSION_1_0 = 4194304, -- VK_MAKE_API_VERSION(0, 1, 0, 0)
	QUEUE_GRAPHICS = 1,
	-- structure types
	ST_APPLICATION_INFO = 0,
	ST_INSTANCE_CREATE_INFO = 1,
	ST_DEVICE_QUEUE_CREATE_INFO = 2,
	ST_DEVICE_CREATE_INFO = 3,
	ST_SUBMIT_INFO = 4,
	ST_MEMORY_ALLOCATE_INFO = 5,
	ST_FENCE_CREATE_INFO = 8,
	ST_SEMAPHORE_CREATE_INFO = 9,
	ST_BUFFER_CREATE_INFO = 12,
	ST_IMAGE_CREATE_INFO = 14,
	ST_IMAGE_VIEW_CREATE_INFO = 15,
	ST_SHADER_MODULE_CREATE_INFO = 16,
	ST_PIPELINE_SHADER_STAGE = 18,
	ST_PIPELINE_VERTEX_INPUT = 19,
	ST_PIPELINE_INPUT_ASSEMBLY = 20,
	ST_PIPELINE_VIEWPORT = 22,
	ST_PIPELINE_RASTERIZATION = 23,
	ST_PIPELINE_MULTISAMPLE = 24,
	ST_PIPELINE_DEPTH_STENCIL = 25,
	ST_PIPELINE_COLOR_BLEND = 26,
	ST_PIPELINE_DYNAMIC = 27,
	ST_GRAPHICS_PIPELINE_CREATE_INFO = 28,
	ST_PIPELINE_LAYOUT_CREATE_INFO = 30,
	ST_SAMPLER_CREATE_INFO = 31,
	ST_DESCRIPTOR_SET_LAYOUT_CREATE_INFO = 32,
	ST_DESCRIPTOR_POOL_CREATE_INFO = 33,
	ST_DESCRIPTOR_SET_ALLOCATE_INFO = 34,
	ST_WRITE_DESCRIPTOR_SET = 35,
	ST_FRAMEBUFFER_CREATE_INFO = 37,
	ST_RENDER_PASS_CREATE_INFO = 38,
	ST_COMMAND_POOL_CREATE_INFO = 39,
	ST_COMMAND_BUFFER_ALLOCATE_INFO = 40,
	ST_COMMAND_BUFFER_BEGIN_INFO = 42,
	ST_RENDER_PASS_BEGIN_INFO = 43,
	ST_IMAGE_MEMORY_BARRIER = 45,
	ST_SWAPCHAIN_CREATE_INFO = 1000001000,
	ST_PRESENT_INFO = 1000001001,
	-- formats
	FORMAT_R8G8B8A8_UNORM = 37,
	FORMAT_B8G8R8A8_UNORM = 44,
	FORMAT_R32G32_SFLOAT = 103,
	FORMAT_R32G32B32_SFLOAT = 106,
	FORMAT_D16_UNORM = 124,
	FORMAT_X8_D24 = 125,
	FORMAT_D32_SFLOAT = 126,
	-- image layouts
	LAYOUT_UNDEFINED = 0,
	LAYOUT_COLOR_ATTACHMENT = 2,
	LAYOUT_DEPTH_ATTACHMENT = 3,
	LAYOUT_SHADER_READ_ONLY = 5,
	LAYOUT_TRANSFER_DST = 7,
	LAYOUT_PRESENT_SRC = 1000001002,
	-- usage
	BUFFER_TRANSFER_SRC = 1,
	BUFFER_VERTEX = 0x80,
	IMAGE_TRANSFER_DST = 2,
	IMAGE_SAMPLED = 4,
	IMAGE_COLOR_ATTACHMENT = 0x10,
	IMAGE_DEPTH_ATTACHMENT = 0x20,
	-- memory properties
	MEM_DEVICE_LOCAL = 1,
	MEM_HOST_VISIBLE = 2,
	MEM_HOST_COHERENT = 4,
	-- aspects
	ASPECT_COLOR = 1,
	ASPECT_DEPTH = 2,
	-- pipeline stages / access
	STAGE_TOP_OF_PIPE = 1,
	STAGE_FRAGMENT_SHADER = 0x80,
	STAGE_EARLY_FRAGMENT_TESTS = 0x100,
	STAGE_COLOR_ATTACHMENT_OUTPUT = 0x400,
	STAGE_TRANSFER = 0x1000,
	ACCESS_SHADER_READ = 0x20,
	ACCESS_COLOR_WRITE = 0x100,
	ACCESS_DEPTH_WRITE = 0x400,
	ACCESS_TRANSFER_WRITE = 0x1000,
	-- shader stages
	SHADER_VERTEX = 1,
	SHADER_FRAGMENT = 0x10,
	DESCRIPTOR_COMBINED_IMAGE_SAMPLER = 1,
	-- misc
	SUBPASS_EXTERNAL = 0xFFFFFFFF,
	PRESENT_MODE_FIFO = 2,
	COMMAND_POOL_RESET = 2,
	FENCE_SIGNALED = 1,
	DESCRIPTOR_POOL_FREE_SET = 1,
	CMD_ONE_TIME_SUBMIT = 1,
	DEVICE_TYPE_DISCRETE = 2,
}

-- UINT64_MAX as an 8-byte buffer (Zune accepts buffers for u64 arguments)
vk.U64_MAX = buffer.create(8)
buffer.fill(vk.U64_MAX, 0, 255)

local RESULT_NAMES: { [number]: string } = {
	[0] = "SUCCESS",
	[1] = "NOT_READY",
	[2] = "TIMEOUT",
	[-1] = "ERROR_OUT_OF_HOST_MEMORY",
	[-2] = "ERROR_OUT_OF_DEVICE_MEMORY",
	[-3] = "ERROR_INITIALIZATION_FAILED",
	[-4] = "ERROR_DEVICE_LOST",
	[-5] = "ERROR_MEMORY_MAP_FAILED",
	[-6] = "ERROR_LAYER_NOT_PRESENT",
	[-7] = "ERROR_EXTENSION_NOT_PRESENT",
	[-8] = "ERROR_FEATURE_NOT_PRESENT",
	[-9] = "ERROR_INCOMPATIBLE_DRIVER",
	[-10] = "ERROR_TOO_MANY_OBJECTS",
	[-11] = "ERROR_FORMAT_NOT_SUPPORTED",
	[-1000000000] = "ERROR_SURFACE_LOST_KHR",
	[-1000001004] = "ERROR_OUT_OF_DATE_KHR",
	[1000001003] = "SUBOPTIMAL_KHR",
}

function vk.check(result: number, what: string)
	if result < 0 then
		error(`vulkan: {what} failed: {RESULT_NAMES[result] or result}`, 3)
	end
	return result
end

--------------------------------------------------------------------------
-- Function signatures
--------------------------------------------------------------------------

local SIGNATURES = {
	-- instance / physical device
	vkCreateInstance = fn(i32, { ptr, ptr, ptr }),
	vkDestroyInstance = fn(void, { ptr, ptr }),
	vkEnumeratePhysicalDevices = fn(i32, { ptr, ptr, ptr }),
	vkGetPhysicalDeviceProperties = fn(void, { ptr, ptr }),
	vkGetPhysicalDeviceQueueFamilyProperties = fn(void, { ptr, ptr, ptr }),
	vkGetPhysicalDeviceMemoryProperties = fn(void, { ptr, ptr }),
	vkGetPhysicalDeviceFormatProperties = fn(void, { ptr, u32, ptr }),
	vkGetPhysicalDeviceSurfaceSupportKHR = fn(i32, { ptr, u32, ptr, ptr }),
	vkGetPhysicalDeviceSurfaceCapabilitiesKHR = fn(i32, { ptr, ptr, ptr }),
	vkGetPhysicalDeviceSurfaceFormatsKHR = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroySurfaceKHR = fn(void, { ptr, ptr, ptr }),
	vkCreateDevice = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyDevice = fn(void, { ptr, ptr }),
	vkGetDeviceQueue = fn(void, { ptr, u32, u32, ptr }),
	vkDeviceWaitIdle = fn(i32, { ptr }),

	-- swapchain
	vkCreateSwapchainKHR = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroySwapchainKHR = fn(void, { ptr, ptr, ptr }),
	vkGetSwapchainImagesKHR = fn(i32, { ptr, ptr, ptr, ptr }),
	vkAcquireNextImageKHR = fn(i32, { ptr, ptr, u64, ptr, ptr, ptr }),
	vkQueuePresentKHR = fn(i32, { ptr, ptr }),

	-- images / buffers / memory
	vkCreateImage = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyImage = fn(void, { ptr, ptr, ptr }),
	vkGetImageMemoryRequirements = fn(void, { ptr, ptr, ptr }),
	vkBindImageMemory = fn(i32, { ptr, ptr, ptr, u64 }),
	vkCreateImageView = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyImageView = fn(void, { ptr, ptr, ptr }),
	vkCreateBuffer = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyBuffer = fn(void, { ptr, ptr, ptr }),
	vkGetBufferMemoryRequirements = fn(void, { ptr, ptr, ptr }),
	vkBindBufferMemory = fn(i32, { ptr, ptr, ptr, u64 }),
	vkAllocateMemory = fn(i32, { ptr, ptr, ptr, ptr }),
	vkFreeMemory = fn(void, { ptr, ptr, ptr }),
	vkMapMemory = fn(i32, { ptr, ptr, u64, u64, u32, ptr }),
	vkUnmapMemory = fn(void, { ptr, ptr }),

	-- render pass / pipeline
	vkCreateRenderPass = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyRenderPass = fn(void, { ptr, ptr, ptr }),
	vkCreateFramebuffer = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyFramebuffer = fn(void, { ptr, ptr, ptr }),
	vkCreateShaderModule = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyShaderModule = fn(void, { ptr, ptr, ptr }),
	vkCreateDescriptorSetLayout = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyDescriptorSetLayout = fn(void, { ptr, ptr, ptr }),
	vkCreatePipelineLayout = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyPipelineLayout = fn(void, { ptr, ptr, ptr }),
	vkCreateGraphicsPipelines = fn(i32, { ptr, ptr, u32, ptr, ptr, ptr }),
	vkDestroyPipeline = fn(void, { ptr, ptr, ptr }),
	vkCreateSampler = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroySampler = fn(void, { ptr, ptr, ptr }),
	vkCreateDescriptorPool = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyDescriptorPool = fn(void, { ptr, ptr, ptr }),
	vkAllocateDescriptorSets = fn(i32, { ptr, ptr, ptr }),
	vkFreeDescriptorSets = fn(i32, { ptr, ptr, u32, ptr }),
	vkUpdateDescriptorSets = fn(void, { ptr, u32, ptr, u32, ptr }),

	-- commands / sync
	vkCreateCommandPool = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyCommandPool = fn(void, { ptr, ptr, ptr }),
	vkAllocateCommandBuffers = fn(i32, { ptr, ptr, ptr }),
	vkResetCommandBuffer = fn(i32, { ptr, u32 }),
	vkBeginCommandBuffer = fn(i32, { ptr, ptr }),
	vkEndCommandBuffer = fn(i32, { ptr }),
	vkCreateSemaphore = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroySemaphore = fn(void, { ptr, ptr, ptr }),
	vkCreateFence = fn(i32, { ptr, ptr, ptr, ptr }),
	vkDestroyFence = fn(void, { ptr, ptr, ptr }),
	vkWaitForFences = fn(i32, { ptr, u32, ptr, u32, u64 }),
	vkResetFences = fn(i32, { ptr, u32, ptr }),
	vkQueueSubmit = fn(i32, { ptr, u32, ptr, ptr }),
	vkQueueWaitIdle = fn(i32, { ptr }),

	-- recording
	vkCmdBeginRenderPass = fn(void, { ptr, ptr, u32 }),
	vkCmdEndRenderPass = fn(void, { ptr }),
	vkCmdBindPipeline = fn(void, { ptr, u32, ptr }),
	vkCmdBindVertexBuffers = fn(void, { ptr, u32, u32, ptr, ptr }),
	vkCmdBindDescriptorSets = fn(void, { ptr, u32, ptr, u32, u32, ptr, u32, ptr }),
	vkCmdPushConstants = fn(void, { ptr, ptr, u32, u32, u32, ptr }),
	vkCmdSetViewport = fn(void, { ptr, u32, u32, ptr }),
	vkCmdSetScissor = fn(void, { ptr, u32, u32, ptr }),
	vkCmdDraw = fn(void, { ptr, u32, u32, u32, u32 }),
	vkCmdCopyBufferToImage = fn(void, { ptr, ptr, ptr, u32, u32, ptr }),
	vkCmdPipelineBarrier = fn(void, { ptr, u32, u32, u32, u32, ptr, u32, ptr, u32, ptr }),
	vkCmdClearAttachments = fn(void, { ptr, u32, ptr, u32, ptr }),
}
-- Opens the Vulkan loader and returns the function table.
function vk.open(customPath: string?): any
	local list = if customPath then { customPath } else { "C:/Windows/System32/vulkan-1.dll" }
	local lastError: any = nil
	for _, path in list do
		local ok, result = pcall(ffi.dlopen, path, SIGNATURES)
		if ok then
			return result
		end
		lastError = result
	end
	error(
		"vulkan: could not load the Vulkan loader. Tried: "
			.. table.concat(list, ", ")
			.. "\nLast error: "
			.. tostring(lastError),
		2
	)
end

--------------------------------------------------------------------------
-- Struct helpers
--------------------------------------------------------------------------

local SIZES = { u8 = 1, u16 = 2, u32 = 4, i32 = 4, f32 = 4, u64 = 8, ptr = 8 }

-- Static method calls on purpose (FFIPointer methods are namecall-based).
local WRITERS: { [string]: (any, number, any) -> () } = {
	u8 = function(p, o, v)
		p:writeu8(o, v)
	end,
	u16 = function(p, o, v)
		p:writeu16(o, v)
	end,
	u32 = function(p, o, v)
		p:writeu32(o, v)
	end,
	i32 = function(p, o, v)
		p:writei32(o, v)
	end,
	f32 = function(p, o, v)
		p:writef32(o, v)
	end,
	u64 = function(p, o, v)
		p:writeu64(o, v)
	end,
	ptr = function(p, o, v)
		p:writeptr(o, v)
	end,
}

export type StructDef = { name: string, size: number, fields: { [string]: { offset: number, type: string } } }

local S: { [string]: StructDef } = {}

local function defStruct(name: string, spec: string)
	local fields, offset, maxAlign = {}, 0, 1
	for typ, fname in string.gmatch(spec, "(%w+):(%w+)") do
		local size = SIZES[typ]
		assert(size, `bad type {typ} in {name}`)
		offset = (offset + size - 1) // size * size
		fields[fname] = { offset = offset, type = typ }
		offset += size
		maxAlign = math.max(maxAlign, size)
	end
	S[name] = { name = name, size = (offset + maxAlign - 1) // maxAlign * maxAlign, fields = fields }
end

local DEFS = {
	VkApplicationInfo = "u32:sType ptr:pNext ptr:pApplicationName u32:applicationVersion ptr:pEngineName u32:engineVersion u32:apiVersion",
	VkInstanceCreateInfo = "u32:sType ptr:pNext u32:flags ptr:pApplicationInfo u32:enabledLayerCount ptr:ppEnabledLayerNames u32:enabledExtensionCount ptr:ppEnabledExtensionNames",
	VkDeviceQueueCreateInfo = "u32:sType ptr:pNext u32:flags u32:queueFamilyIndex u32:queueCount ptr:pQueuePriorities",
	VkDeviceCreateInfo = "u32:sType ptr:pNext u32:flags u32:queueCreateInfoCount ptr:pQueueCreateInfos u32:enabledLayerCount ptr:ppEnabledLayerNames u32:enabledExtensionCount ptr:ppEnabledExtensionNames ptr:pEnabledFeatures",
	VkSwapchainCreateInfoKHR = "u32:sType ptr:pNext u32:flags ptr:surface u32:minImageCount u32:imageFormat u32:imageColorSpace u32:width u32:height u32:imageArrayLayers u32:imageUsage u32:imageSharingMode u32:queueFamilyIndexCount ptr:pQueueFamilyIndices u32:preTransform u32:compositeAlpha u32:presentMode u32:clipped ptr:oldSwapchain",
	VkImageViewCreateInfo = "u32:sType ptr:pNext u32:flags ptr:image u32:viewType u32:format u32:r u32:g u32:b u32:a u32:aspectMask u32:baseMipLevel u32:levelCount u32:baseArrayLayer u32:layerCount",
	VkImageCreateInfo = "u32:sType ptr:pNext u32:flags u32:imageType u32:format u32:width u32:height u32:depth u32:mipLevels u32:arrayLayers u32:samples u32:tiling u32:usage u32:sharingMode u32:queueFamilyIndexCount ptr:pQueueFamilyIndices u32:initialLayout",
	VkMemoryAllocateInfo = "u32:sType ptr:pNext u64:allocationSize u32:memoryTypeIndex",
	VkBufferCreateInfo = "u32:sType ptr:pNext u32:flags u64:size u32:usage u32:sharingMode u32:queueFamilyIndexCount ptr:pQueueFamilyIndices",
	VkAttachmentDescription = "u32:flags u32:format u32:samples u32:loadOp u32:storeOp u32:stencilLoadOp u32:stencilStoreOp u32:initialLayout u32:finalLayout",
	VkAttachmentReference = "u32:attachment u32:layout",
	VkSubpassDescription = "u32:flags u32:pipelineBindPoint u32:inputAttachmentCount ptr:pInputAttachments u32:colorAttachmentCount ptr:pColorAttachments ptr:pResolveAttachments ptr:pDepthStencilAttachment u32:preserveAttachmentCount ptr:pPreserveAttachments",
	VkSubpassDependency = "u32:srcSubpass u32:dstSubpass u32:srcStageMask u32:dstStageMask u32:srcAccessMask u32:dstAccessMask u32:dependencyFlags",
	VkRenderPassCreateInfo = "u32:sType ptr:pNext u32:flags u32:attachmentCount ptr:pAttachments u32:subpassCount ptr:pSubpasses u32:dependencyCount ptr:pDependencies",
	VkFramebufferCreateInfo = "u32:sType ptr:pNext u32:flags ptr:renderPass u32:attachmentCount ptr:pAttachments u32:width u32:height u32:layers",
	VkShaderModuleCreateInfo = "u32:sType ptr:pNext u32:flags u64:codeSize ptr:pCode",
	VkDescriptorSetLayoutBinding = "u32:binding u32:descriptorType u32:descriptorCount u32:stageFlags ptr:pImmutableSamplers",
	VkDescriptorSetLayoutCreateInfo = "u32:sType ptr:pNext u32:flags u32:bindingCount ptr:pBindings",
	VkPushConstantRange = "u32:stageFlags u32:offset u32:size",
	VkPipelineLayoutCreateInfo = "u32:sType ptr:pNext u32:flags u32:setLayoutCount ptr:pSetLayouts u32:pushConstantRangeCount ptr:pPushConstantRanges",
	VkPipelineShaderStageCreateInfo = "u32:sType ptr:pNext u32:flags u32:stage ptr:module ptr:pName ptr:pSpecializationInfo",
	VkVertexInputBindingDescription = "u32:binding u32:stride u32:inputRate",
	VkVertexInputAttributeDescription = "u32:location u32:binding u32:format u32:offset",
	VkPipelineVertexInputStateCreateInfo = "u32:sType ptr:pNext u32:flags u32:vertexBindingDescriptionCount ptr:pVertexBindingDescriptions u32:vertexAttributeDescriptionCount ptr:pVertexAttributeDescriptions",
	VkPipelineInputAssemblyStateCreateInfo = "u32:sType ptr:pNext u32:flags u32:topology u32:primitiveRestartEnable",
	VkPipelineViewportStateCreateInfo = "u32:sType ptr:pNext u32:flags u32:viewportCount ptr:pViewports u32:scissorCount ptr:pScissors",
	VkPipelineRasterizationStateCreateInfo = "u32:sType ptr:pNext u32:flags u32:depthClampEnable u32:rasterizerDiscardEnable u32:polygonMode u32:cullMode u32:frontFace u32:depthBiasEnable f32:depthBiasConstantFactor f32:depthBiasClamp f32:depthBiasSlopeFactor f32:lineWidth",
	VkPipelineMultisampleStateCreateInfo = "u32:sType ptr:pNext u32:flags u32:rasterizationSamples u32:sampleShadingEnable f32:minSampleShading ptr:pSampleMask u32:alphaToCoverageEnable u32:alphaToOneEnable",
	VkPipelineDepthStencilStateCreateInfo = "u32:sType ptr:pNext u32:flags u32:depthTestEnable u32:depthWriteEnable u32:depthCompareOp u32:depthBoundsTestEnable u32:stencilTestEnable u32:f0 u32:f1 u32:f2 u32:f3 u32:f4 u32:f5 u32:f6 u32:b0 u32:b1 u32:b2 u32:b3 u32:b4 u32:b5 u32:b6 f32:minDepthBounds f32:maxDepthBounds",
	VkPipelineColorBlendAttachmentState = "u32:blendEnable u32:srcColorBlendFactor u32:dstColorBlendFactor u32:colorBlendOp u32:srcAlphaBlendFactor u32:dstAlphaBlendFactor u32:alphaBlendOp u32:colorWriteMask",
	VkPipelineColorBlendStateCreateInfo = "u32:sType ptr:pNext u32:flags u32:logicOpEnable u32:logicOp u32:attachmentCount ptr:pAttachments f32:bc0 f32:bc1 f32:bc2 f32:bc3",
	VkPipelineDynamicStateCreateInfo = "u32:sType ptr:pNext u32:flags u32:dynamicStateCount ptr:pDynamicStates",
	VkGraphicsPipelineCreateInfo = "u32:sType ptr:pNext u32:flags u32:stageCount ptr:pStages ptr:pVertexInputState ptr:pInputAssemblyState ptr:pTessellationState ptr:pViewportState ptr:pRasterizationState ptr:pMultisampleState ptr:pDepthStencilState ptr:pColorBlendState ptr:pDynamicState ptr:layout ptr:renderPass u32:subpass ptr:basePipelineHandle i32:basePipelineIndex",
	VkDescriptorPoolSize = "u32:type u32:descriptorCount",
	VkDescriptorPoolCreateInfo = "u32:sType ptr:pNext u32:flags u32:maxSets u32:poolSizeCount ptr:pPoolSizes",
	VkDescriptorSetAllocateInfo = "u32:sType ptr:pNext ptr:descriptorPool u32:descriptorSetCount ptr:pSetLayouts",
	VkDescriptorImageInfo = "ptr:sampler ptr:imageView u32:imageLayout",
	VkWriteDescriptorSet = "u32:sType ptr:pNext ptr:dstSet u32:dstBinding u32:dstArrayElement u32:descriptorCount u32:descriptorType ptr:pImageInfo ptr:pBufferInfo ptr:pTexelBufferView",
	VkSamplerCreateInfo = "u32:sType ptr:pNext u32:flags u32:magFilter u32:minFilter u32:mipmapMode u32:addressModeU u32:addressModeV u32:addressModeW f32:mipLodBias u32:anisotropyEnable f32:maxAnisotropy u32:compareEnable u32:compareOp f32:minLod f32:maxLod u32:borderColor u32:unnormalizedCoordinates",
	VkCommandPoolCreateInfo = "u32:sType ptr:pNext u32:flags u32:queueFamilyIndex",
	VkCommandBufferAllocateInfo = "u32:sType ptr:pNext ptr:commandPool u32:level u32:commandBufferCount",
	VkCommandBufferBeginInfo = "u32:sType ptr:pNext u32:flags ptr:pInheritanceInfo",
	VkSemaphoreCreateInfo = "u32:sType ptr:pNext u32:flags",
	VkFenceCreateInfo = "u32:sType ptr:pNext u32:flags",
	VkSubmitInfo = "u32:sType ptr:pNext u32:waitSemaphoreCount ptr:pWaitSemaphores ptr:pWaitDstStageMask u32:commandBufferCount ptr:pCommandBuffers u32:signalSemaphoreCount ptr:pSignalSemaphores",
	VkPresentInfoKHR = "u32:sType ptr:pNext u32:waitSemaphoreCount ptr:pWaitSemaphores u32:swapchainCount ptr:pSwapchains ptr:pImageIndices ptr:pResults",
	VkRenderPassBeginInfo = "u32:sType ptr:pNext ptr:renderPass ptr:framebuffer i32:x i32:y u32:width u32:height u32:clearValueCount ptr:pClearValues",
	VkViewport = "f32:x f32:y f32:width f32:height f32:minDepth f32:maxDepth",
	VkRect2D = "i32:x i32:y u32:width u32:height",
	VkImageMemoryBarrier = "u32:sType ptr:pNext u32:srcAccessMask u32:dstAccessMask u32:oldLayout u32:newLayout u32:srcQueueFamilyIndex u32:dstQueueFamilyIndex ptr:image u32:aspectMask u32:baseMipLevel u32:levelCount u32:baseArrayLayer u32:layerCount",
	VkBufferImageCopy = "u64:bufferOffset u32:bufferRowLength u32:bufferImageHeight u32:aspectMask u32:mipLevel u32:baseArrayLayer u32:layerCount i32:ox i32:oy i32:oz u32:width u32:height u32:depth",
	-- VkClearAttachment with the 16-byte VkClearValue union flattened: color = v0..v3 (floats); depth = v0 (float), stencil = v1 (u32 bits)
	VkClearAttachment = "u32:aspectMask u32:colorAttachment f32:v0 f32:v1 f32:v2 f32:v3",
	VkClearRect = "i32:x i32:y u32:width u32:height u32:baseArrayLayer u32:layerCount",
}
for name, spec in DEFS do
	defStruct(name, spec)
end

vk.S = S

-- Arena: tracks native allocations so transient structs can be freed in one go.
local Arena = {}
Arena.__index = Arena

function vk.arena()
	return setmetatable({ items = {} }, Arena)
end

function Arena:alloc(size: number, align: number?): any
	local p = ffi.alloc(math.max(size, 8), align or 8) -- zero-initialised by Zune
	table.insert(self.items, p)
	return p
end

function Arena:cstr(s: string): any
	local p = ffi.dupe(buffer.fromstring(s .. "\0"))
	table.insert(self.items, p)
	return p
end

function Arena:free()
	for _, p in self.items do
		ffi.free(p)
	end
	table.clear(self.items)
end

local function fill(p: any, base: number, def: StructDef, values: { [string]: any })
	for k, v in values do
		local f = def.fields[k]
		if not f then
			error(`unknown field '{k}' for {def.name}`, 3)
		end
		WRITERS[f.type](p, base + f.offset, v)
	end
end

-- Allocates a zeroed struct in `arena` and fills it.
function vk.new(defName: string, values: { [string]: any }, arena: any): any
	local def = S[defName]
	assert(def, "unknown struct " .. defName)
	local p = arena:alloc(def.size)
	fill(p, 0, def, values)
	return p
end

-- Allocates a contiguous array of structs (one values-table per element).
function vk.newArray(defName: string, list: { { [string]: any } }, arena: any): any
	local def = S[defName]
	assert(def, "unknown struct " .. defName)
	local p = arena:alloc(def.size * math.max(#list, 1))
	for i, values in list do
		fill(p, (i - 1) * def.size, def, values)
	end
	return p
end

function vk.ptrArray(list: { any }, arena: any): any
	local p = arena:alloc(8 * math.max(#list, 1))
	for i, v in list do
		p:writeptr((i - 1) * 8, v)
	end
	return p
end

function vk.u32Array(list: { number }, arena: any): any
	local p = arena:alloc(4 * math.max(#list, 1))
	for i, v in list do
		p:writeu32((i - 1) * 4, v)
	end
	return p
end

function vk.f32Array(list: { number }, arena: any): any
	local p = arena:alloc(4 * math.max(#list, 1))
	for i, v in list do
		p:writef32((i - 1) * 4, v)
	end
	return p
end

-- Updates fields of an existing struct pointer in place (for per-frame structs).
function vk.set(p: any, defName: string, values: { [string]: any })
	fill(p, 0, S[defName], values)
end

return vk
