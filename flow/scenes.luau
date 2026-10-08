--!strict
-- The Flow scenes this plugin keeps (SCENES in hooks/styles.ts, in `/flow
-- next` order, without balloon, falcon, starship, surf, ski and train). Each scene's code
-- loads on demand: compiling a file can take up to ~20 ms, so a caller
-- under a time budget loads one file per call (`load`) and makes scenes
-- only once `loaded` says so.
--
-- A scene: fields strength (0..10), coverageBoost, tint ("normal" | "smoke" |
-- "blue"), night, waiting, columns, rows; methods ensure(columns, rows),
-- step(), grid() -> Cells (cells.luau).

local M = {}

M.NAMES = { "fire", "warp", "avalon", "engine", "bubbles" }

local MODULE: { [string]: string } = {
	fire = "ember",
	warp = "starfield",
	avalon = "colony",
	engine = "engine",
	bubbles = "bubbles",
}

-- require() needs a literal path in Luau's require-by-string. It caches each
-- file, so requiring a scene's dependencies first, one per call, leaves only
-- that file to compile in each.
local FILES: { [string]: () -> any } = {
	js = function()
		return require("./js")
	end,
	cells = function()
		return require("./cells")
	end,
	pixels = function()
		return require("./pixels")
	end,
	waiting = function()
		return require("./waiting")
	end,
	sound = function()
		return require("./sound")
	end,
	fire = function()
		return require("./fire")
	end,
	ember = function()
		return require("./ember")
	end,
	starfield = function()
		return require("./starfield")
	end,
	colony = function()
		return require("./colony")
	end,
	engine = function()
		return require("./engine")
	end,
	engine_draw = function()
		return require("./engine_draw")
	end,
	bubbles = function()
		return require("./bubbles")
	end,
}

-- Each module's files in load order: dependencies first, the module itself
-- last but for the second half of a split one (engine is split so each
-- half compiles within a call's budget; the second half adds its methods
-- to the first's class).
local STEPS: { [string]: { string } } = {
	ember = { "js", "cells", "pixels", "waiting", "fire", "ember" },
	starfield = { "js", "cells", "pixels", "waiting", "fire", "starfield" },
	colony = { "js", "cells", "pixels", "waiting", "sound", "colony" },
	engine = { "js", "cells", "pixels", "waiting", "sound", "engine", "engine_draw" },
	bubbles = { "js", "cells", "pixels", "waiting", "bubbles" },
}
local SECOND: { [string]: string } = { engine = "engine_draw" }

local done: { [string]: any } = {} -- file -> its module, once loaded

-- Whether the scene's code is fully loaded, so `make` is cheap.
function M.loaded(name: string): boolean
	local m = MODULE[name]
	if not m then
		return false
	end
	local steps = STEPS[m]
	return done[steps[#steps]] ~= nil
end

-- Loads the next file of the scene's code (the slow part), one per call.
-- Call until `loaded` is true.
function M.load(name: string)
	local m = MODULE[name]
	if not m then
		error("unknown scene " .. tostring(name))
	end
	for _, file in STEPS[m] do
		if done[file] == nil then
			local mod = FILES[file]()
			if SECOND[m] == file then
				mod(done[m].__drawEnv)
				mod = true
			end
			done[file] = mod
			return
		end
	end
end

function M.make(name: string, seed: number?): any
	while not M.loaded(name) do
		M.load(name)
	end
	return done[MODULE[name]].make(seed)
end

return M
