return function(app)
	return {
		fileManip = require("@self/fileManip").new(app),
		coordination = require("@self/coordination"),
	}
end
