--!strict
-- Port of Flow's hooks/cells.ts: the PRNG and the cell grid every scene returns.

local js = require("./js")
local u32 = js.u32

local M = {}

-- The terminal's own color: transparent.
M.DEFAULT_COLOR = 0x01000000
local SPACE = 0x20

-- xorshift32.
export type Rng = { s: number, int: (self: Rng) -> number, f: (self: Rng) -> number }
local Rng = {}
Rng.__index = Rng
function Rng.new(seed: number?): Rng
	local sd = seed or (os.time() * 1000)
	local s = u32(js.bor(sd, 1))
	if s == 0 then
		s = 0x9e3779b9
	end
	return (setmetatable({ s = s }, Rng) :: any) :: Rng
end
function Rng.int(self: Rng): number
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x
end
function Rng.f(self: Rng): number
	return self:int() / 4294967296
end
M.Rng = Rng

-- A tall layout (the spine's, a pane's) rather than the band's.
function M.isTall(columns: number, rows: number): boolean
	return rows > 8 or rows > columns
end

-- A columns × rows grid: code point, foreground, background per cell (0-based i).
export type Cells = {
	columns: number,
	rows: number,
	words: { number },
	set: (self: Cells, i: number, codePoint: number, fg: number, bg: number?) -> (),
	blank: (self: Cells, i: number) -> (),
	codePoint: (self: Cells, i: number) -> number,
	foreground: (self: Cells, i: number) -> number,
	background: (self: Cells, i: number) -> number,
	behind: (self: Cells, i: number) -> number,
}
local Cells = {}
Cells.__index = Cells
local DEFAULT_COLOR = M.DEFAULT_COLOR
function Cells.new(columns: number, rows: number): Cells
	return (setmetatable({ columns = columns, rows = rows, words = table.create(columns * rows * 3, 0) }, Cells) :: any) :: Cells
end
function Cells.set(self: Cells, i: number, codePoint: number, fg: number, bg: number?)
	local w = self.words
	local k = i * 3
	w[k + 1] = u32(codePoint)
	w[k + 2] = u32(fg)
	w[k + 3] = u32(bg or DEFAULT_COLOR)
end
function Cells.blank(self: Cells, i: number)
	local w = self.words
	local k = i * 3
	w[k + 1] = SPACE
	w[k + 2] = DEFAULT_COLOR
	w[k + 3] = DEFAULT_COLOR
end
function Cells.codePoint(self: Cells, i: number): number
	return self.words[i * 3 + 1]
end
function Cells.foreground(self: Cells, i: number): number
	return self.words[i * 3 + 2]
end
function Cells.background(self: Cells, i: number): number
	return self.words[i * 3 + 3]
end
function Cells.behind(self: Cells, i: number): number
	return if self.words[i * 3 + 1] == 0x2588 then self.words[i * 3 + 2] else self.words[i * 3 + 3]
end
M.Cells = Cells

return M
