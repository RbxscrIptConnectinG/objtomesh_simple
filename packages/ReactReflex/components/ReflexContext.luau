local React = require("@pkgs/React")
local Reflex = require("@pkgs/Reflex")

local ReflexContext = (React.createContext(nil) :: any) :: React.Context<Reflex.Producer<any, any>>

return ReflexContext
