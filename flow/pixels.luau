--!strict
-- Port of Flow's hooks/pixels.ts: color math, hashes, glyph tables, fitQuad.

local js = require("./js")
local i32, u32, imul, bxor, shr = js.i32, js.u32, js.imul, js.bxor, js.shr
local extract = bit32.extract

local M = {}

function M.g(ch: string): number
	return utf8.codepoint(ch, 1)
end

function M.clamp(v: number, lo: number?, hi: number?): number
	local l = lo or 0
	local h = hi or 1
	return if v < l then l elseif v > h then h else v
end

function M.clamp01(v: number): number
	return if v < 0 then 0 elseif v > 1 then 1 else v
end

-- `a` moved `k` (0..1) of the way to `b`, per channel of 0xRRGGBB.
local function mix(a: number, b: number, k: number): number
	if k <= 0 then
		return a
	end
	if k >= 1 then
		return b
	end
	local ar, ag, ab = extract(a, 16, 8), extract(a, 8, 8), extract(a, 0, 8)
	local r = i32(ar + (extract(b, 16, 8) - ar) * k + 0.5)
	local gg = i32(ag + (extract(b, 8, 8) - ag) * k + 0.5)
	local bb = i32(ab + (extract(b, 0, 8) - ab) * k + 0.5)
	return js.bor(js.bor(js.shl(r, 16), js.shl(gg, 8)), bb)
end
M.mix = mix

-- Squared RGB distance.
local function dist(a: number, b: number): number
	local r = extract(a, 16, 8) - extract(b, 16, 8)
	local gg = extract(a, 8, 8) - extract(b, 8, 8)
	local bb = extract(a, 0, 8) - extract(b, 0, 8)
	return r * r + gg * gg + bb * bb
end
M.dist = dist

-- A stable hash of a world position (integers) to [0, 1).
function M.hash(x: number, y: number, salt: number?): number
	local h = i32(x * 374761393 + y * 668265263 + (salt or 0) * 2147483647)
	h = imul(bxor(h, shr(h, 13)), 1274126177)
	h = bxor(h, shr(h, 16))
	return u32(h) / 4294967296
end

-- A stable hash of one integer to [0, 1).
local function hash1(n: number): number
	local h = imul(bxor(n, 0x9e3779b9), 0x85ebca6b)
	h = bxor(h, shr(h, 13))
	h = imul(h, 0xc2b2ae35)
	h = bxor(h, shr(h, 16))
	return u32(h) / 4294967296
end
M.hash1 = hash1

-- Smooth 1-D value noise in [0, 1).
function M.noise1(x: number, seed: number): number
	local i = math.floor(x)
	local f = x - i
	local a = hash1(i * 7919 + seed)
	local b = hash1((i + 1) * 7919 + seed)
	return a + (b - a) * f * f * (3 - 2 * f)
end

-- `c` moved `k` of the way to its own grey.
function M.grey(c: number, k: number): number
	local l = i32(extract(c, 16, 8) * 0.3 + extract(c, 8, 8) * 0.59 + extract(c, 0, 8) * 0.11)
	return mix(c, l * 65536 + l * 256 + l, k)
end

-- murmur-finalized hash of (x, y, s) to [0, 1).
function M.hashMurmur(x: number, y: number, s: number): number
	local h = bxor(bxor(imul(i32(x), 0x27d4eb2d), imul(i32(y) + 0x3c6ef372, 0x165667b1)), imul(i32(s), 0x9e3779b9))
	h = imul(bxor(h, shr(h, 15)), 0x85ebca6b)
	h = imul(bxor(h, shr(h, 13)), 0xc2b2ae35)
	h = bxor(h, shr(h, 16))
	return u32(h) / 4294967296
end

-- Quadrant glyphs by pixel mask (0-based: QUAD[mask + 1]).
M.QUAD = {
	0x20, 0x2598, 0x259d, 0x2580, 0x2596, 0x258c, 0x259e, 0x259b, 0x2597, 0x259a, 0x2590, 0x259c, 0x2584, 0x2599,
	0x259f, 0x2588,
}

function M.lowerBlock(eighths: number): number
	return if eighths <= 0 then 0x20 else 0x2580 + math.min(8, eighths)
end

M.NEAR = 1200

-- Braille dot bits by (column 0..1, row 0..3): BRAILLE[col + 1][row + 1].
M.BRAILLE = {
	{ 0x01, 0x02, 0x04, 0x40 },
	{ 0x08, 0x10, 0x20, 0x80 },
}

export type QuadFit = { mask: number, fg: number, bg: number, spread: number }

-- q is 0-based in TS: here q[1..4].
local function groupColor(q: { number }, mask: number, want: number, seed: number, near: number): number
	local r, gg, b, n = 0, 0, 0, 0
	for p = 0, 3 do
		if extract(mask, p, 1) == want then
			local v = q[p + 1]
			if dist(v, seed) <= near then
				r += extract(v, 16, 8)
				gg += extract(v, 8, 8)
				b += extract(v, 0, 8)
				n += 1
			end
		end
	end
	if n == 0 then
		return seed
	end
	return math.floor(r / n + 0.5) * 65536 + math.floor(gg / n + 0.5) * 256 + math.floor(b / n + 0.5)
end

-- `keep` is a 0-based pixel index or -1, as in TS.
function M.fitQuad(q: { number }, fit: QuadFit, near: number?, keep: number?)
	local nr = near or M.NEAR
	local kp = keep or -1
	local bi, bj, best = 0, 0, 0
	for i = 0, 2 do
		for j = i + 1, 3 do
			local d = dist(q[i + 1], q[j + 1])
			if d > best then
				best = d
				bi = i
				bj = j
			end
		end
	end
	fit.spread = best
	if kp >= 0 and best > 0 then
		local far, farD = 0, -1
		for p = 0, 3 do
			local d = dist(q[p + 1], q[kp + 1])
			if d > farD then
				farD = d
				far = p
			end
		end
		if farD > 0 then
			bi = kp
			bj = far
		end
	end
	if best == 0 then
		fit.mask = 0
		fit.fg = q[1]
		fit.bg = q[1]
		return
	end
	local si, sj = q[bi + 1], q[bj + 1]
	local mask = 0
	for p = 0, 3 do
		local v = q[p + 1]
		if dist(v, sj) < dist(v, si) then
			mask += 2 ^ p
		end
	end
	fit.mask = mask
	fit.fg = groupColor(q, mask, 1, sj, nr)
	fit.bg = groupColor(q, mask, 0, si, nr)
end

return M
