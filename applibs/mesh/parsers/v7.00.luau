local meshTypes = require("@applibs/meshTypes")
local Draco = require("@applibs/draco")

-- i'll look further into parsers later, since it isn't my main focus for today
return function(data: string, headerOffset: number)
	headerOffset -= 1
	local dataBuffer = buffer.fromstring(data)
	local size = buffer.len(dataBuffer)
	if size < headerOffset then
		error("file too small to contain a valid header")
	end

	local header = buffer.readstring(dataBuffer, 0, 12)

	local vertices: { meshTypes.Vertex }? = nil
	local faces: { meshTypes.Face }? = nil

	local offset = headerOffset
	while offset < size do
		if offset + 16 > size then
			break
		end

		local chunkType = buffer.readstring(dataBuffer, offset, 8)
		local chunkVersion = buffer.readu32(dataBuffer, offset + 8)
		local chunkSize = buffer.readu32(dataBuffer, offset + 12)
		local dataStart = offset + 16

		if dataStart + chunkSize > size then
			error(`chunk '{chunkType}' claims {chunkSize} bytes but only {size - dataStart} remain`)
		end

		if chunkType == "COREMESH" then
			if chunkVersion ~= 2 then
				error(
					`COREMESH chunk version {chunkVersion} isn't Draco-compressed (expected version 2) - is this actually a v7.00 file?`
				)
			end

			local dracoSize = buffer.readu32(dataBuffer, dataStart)
			local dracoStart = dataStart + 4
			if dracoStart + dracoSize > dataStart + chunkSize then
				error("dracoBitStreamSize exceeds the COREMESH chunk's declared size")
			end

			local dracoBytes = buffer.create(dracoSize)
			buffer.copy(dracoBytes, 0, dataBuffer, dracoStart, dracoSize)

			vertices, faces = Draco.decodeMeshFull(dracoBytes)
		end

		offset = dataStart + chunkSize
	end

	if not vertices or not faces then
		error("no COREMESH chunk found in file")
	end

	return { vertices = vertices, faces = faces }
end
