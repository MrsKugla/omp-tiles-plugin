--!strict
-- The Flow scenes this plugin keeps (SCENES in hooks/styles.ts, in `/flow
-- next` order, without balloon, surf, ski and train). Each scene's module
-- loads on demand: compiling one can take tens of milliseconds, so a caller
-- under a time budget loads one module per call (`load`) and makes scenes
-- only once `loaded` says so.
--
-- A scene: fields strength (0..10), coverageBoost, tint ("normal" | "smoke" |
-- "blue"), night, waiting, columns, rows; methods ensure(columns, rows),
-- step(), grid() -> Cells (cells.luau).

local M = {}

M.NAMES = { "fire", "warp", "avalon", "engine", "falcon", "starship", "bubbles" }

-- Scenes that draw a night version too.
M.NIGHT = { falcon = true, starship = true }

local MODULE: { [string]: string } = {
	fire = "ember",
	warp = "starfield",
	avalon = "colony",
	engine = "engine",
	falcon = "rocket",
	starship = "rocket",
	bubbles = "bubbles",
}

-- require() needs a literal path in Luau's require-by-string.
local LOADERS: { [string]: () -> any } = {
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
	rocket = function()
		return require("./rocket")
	end,
	bubbles = function()
		return require("./bubbles")
	end,
}

-- The two biggest modules are split in half (each half compiles within a
-- Tern call's budget); the second half adds its methods to the first's class.
local SECOND: { [string]: () -> any } = {
	engine = function()
		return require("./engine_draw")
	end,
	rocket = function()
		return require("./rocket_draw")
	end,
}

local modules: { [string]: any } = {}
local complete: { [string]: boolean } = {}

-- Whether the scene's code is fully loaded, so `make` is cheap.
function M.loaded(name: string): boolean
	local m = MODULE[name]
	return m ~= nil and complete[m] == true
end

-- Loads the next piece of the scene's code (the slow part): one module, or
-- one half of a split one, per call. Call until `loaded` is true.
function M.load(name: string)
	local m = MODULE[name]
	if not m then
		error("unknown scene " .. tostring(name))
	end
	if complete[m] then
		return
	end
	if not modules[m] then
		modules[m] = LOADERS[m]()
		complete[m] = SECOND[m] == nil
		return
	end
	SECOND[m]()(modules[m].__drawEnv)
	complete[m] = true
end

function M.make(name: string, seed: number?): any
	while not M.loaded(name) do
		M.load(name)
	end
	local mod = modules[MODULE[name]]
	if name == "falcon" then
		return mod.falcon(seed)
	elseif name == "starship" then
		return mod.starship(seed)
	end
	return mod.make(seed)
end

return M
