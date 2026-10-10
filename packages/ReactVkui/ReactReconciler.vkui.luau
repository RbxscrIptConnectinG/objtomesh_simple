--!nonstrict
-- Hands the vkui host config to the reconciler (this is what react-roblox does in ReactReconciler.roblox.lua).
-- The reconciler keeps the host config in module-level state, so there is one renderer per process.
local initializeReconciler = require("@pkgs/ReactReconciler")

local ReactVkuiHostConfig = require("./client/ReactVkuiHostConfig")

return initializeReconciler(ReactVkuiHostConfig)
