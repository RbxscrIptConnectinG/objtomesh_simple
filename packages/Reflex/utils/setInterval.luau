local tick = zune.time.timestampMillis
local function setInterval(callback: () -> (), interval: number): () -> ()
	if interval < 0 then
		return function() end
	end
	local prevTick = tick()
	local timer = 0
	local connection

	local alive = true
	zune.task.spawn(function()
		while alive do
			local dt = tick() - prevTick

			timer += dt

			if timer >= interval then
				timer -= interval
				callback()
			end
		end
	end)

	return function()
		alive = false
	end
end

return setInterval
