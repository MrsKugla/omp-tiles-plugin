--!strict
-- JavaScript number semantics the Flow port needs to give the same frames as
-- the original TypeScript: ToInt32/ToUint32 (`| 0`, `>>> 0`, typed-array
-- stores), the 32-bit bit operators, Math.imul, Math.round, `%` and
-- Float32Array rounding. Luau's bit32 works on uint32 and its `%` floors, so
-- every JS bit operator or `%` in the port goes through here unless its
-- operands are known non-negative integers in range.

local M = {}

local TWO32 = 4294967296
local TWO31 = 2147483648

-- ToUint32: `x >>> 0`, and a Uint32Array store.
local function u32(x: number): number
	if x >= 0 and x < TWO32 and x == math.floor(x) then
		return x
	end
	if x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	local t = if x < 0 then -math.floor(-x) else math.floor(x)
	t = math.fmod(t, TWO32)
	if t < 0 then
		t += TWO32
	end
	return t
end
M.u32 = u32

-- ToInt32: `x | 0`, and an Int32Array store.
local function i32(x: number): number
	if x >= -TWO31 and x < TWO31 and x == math.floor(x) then
		return x
	end
	local u = u32(x)
	return if u >= TWO31 then u - TWO32 else u
end
M.i32 = i32

-- ToUint8 / ToUint16 (Uint8Array / Uint16Array stores).
function M.u8(x: number): number
	if x >= 0 and x < 256 and x == math.floor(x) then
		return x
	end
	return u32(x) % 256
end
function M.u16(x: number): number
	if x >= 0 and x < 65536 and x == math.floor(x) then
		return x
	end
	return u32(x) % 65536
end

-- Math.fround: a Float32Array store.
local fb = buffer.create(4)
function M.f32(x: number): number
	buffer.writef32(fb, 0, x)
	return buffer.readf32(fb, 0)
end

-- a | b, a & b, a ^ b (results are int32, as in JS).
function M.bor(a: number, b: number): number
	return i32(bit32.bor(u32(a), u32(b)))
end
function M.band(a: number, b: number): number
	return i32(bit32.band(u32(a), u32(b)))
end
function M.bxor(a: number, b: number): number
	return i32(bit32.bxor(u32(a), u32(b)))
end
-- ~a
function M.bnot(a: number): number
	return i32(bit32.bnot(u32(a)))
end
-- a << n
function M.shl(a: number, n: number): number
	return i32(bit32.lshift(u32(a), u32(n) % 32))
end
-- a >> n (arithmetic)
function M.sar(a: number, n: number): number
	return math.floor(i32(a) / 2 ^ (u32(n) % 32))
end
-- a >>> n (logical; result uint32)
function M.shr(a: number, n: number): number
	return bit32.rshift(u32(a), u32(n) % 32)
end

-- Math.imul.
function M.imul(a: number, b: number): number
	a, b = u32(a), u32(b)
	local al, ah = a % 65536, a // 65536
	local lo = al * b
	local hi = (ah * (b % 65536)) % 65536 * 65536
	return i32((lo + hi) % TWO32)
end

-- Math.round: halves round up (toward +Infinity).
function M.round(x: number): number
	local f = math.floor(x)
	return if x - f >= 0.5 then f + 1 else f
end

-- Math.trunc.
function M.trunc(x: number): number
	return if x >= 0 then math.floor(x) else -math.floor(-x)
end

-- JS `a % b`: the sign of the dividend.
M.mod = math.fmod

-- Math.sign.
function M.sign(x: number): number
	return if x > 0 then 1 elseif x < 0 then -1 else x
end

-- Math.hypot of two.
function M.hypot(a: number, b: number): number
	return math.sqrt(a * a + b * b)
end

M.NaN = 0 / 0
M.isNaN = function(x: number): boolean
	return x ~= x
end

return M
