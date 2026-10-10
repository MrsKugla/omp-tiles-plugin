--!strict
-- omp Tiles: a canvas block with one colored tile per omp session running in
-- Tern, across every Tern session: Tern session → omp session, directory,
-- model, context and a small Flow scene (flow/, a port of robdmac/flow) that
-- moves with the work. Each tile has its own scene, picked from its menu.
-- Each Tern session gets its own copy of the block; all copies show the same
-- tiles, colors, scenes, order and sizes. The tiles sit in an invisible grid
-- of at least two columns, more as the block widens. Click a tile to go
-- there; its sliders icon (or right-click > Personalizza) opens a panel to
-- pick its scene and color, resize it on a small grid or move it.

local scenes = require("./flow/scenes")
local DEFAULT_COLOR = require("./flow/cells").DEFAULT_COLOR
local ui = tern.ui

local TITLE = "omp Tiles"
local SCENE_H = 5 -- Flow's band is 5 rows
local SCENE_H_STEP = 10 -- extra scene rows for each extra grid row a tile spans
local NIGHT_FROM, DAY_FROM = 19, 7 -- Flow's clock: night 19:00 to 7:00
local COL_MIN_CELLS = 44 -- a grid column is at least this many cells wide
local MIN_COLS, MAX_COLS = 2, 8
local MAX_ROWS = 2
local FRAME_MS, CALM_FRAME_MS = 70, 125 -- Flow's pace: busy, and calm (low and untinted)
local MAX_CATCHUP = 3 -- frames a scene may step at once to catch up after a slow pass
local PASS_BUDGET_MS = 20 -- scene work per pass, well under Tern's 50 ms per call
-- Scenes too slow at full tile size, in cells: engine is ~22 ms a frame and
-- over 50 ms to set up at 96x15 in Tern, about half at 48x15.
local MAX_AREA: { [string]: number } = { engine = 48 * 15 }
local HIDDEN_MS = 1500
local POLL_MS = 1000
local SIZE_MS = 2000
local COLORS = { "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink" }
local SLOW_OP_MS = 8 -- diagnostics: log any single step slower than this (Tern stops the timer at 50 ms)
local SLOW_PASS_MS = 25 -- diagnostics: log any loop pass slower than this

-- Logs a slow step to tern.log, so a budget trip can be traced to its cause.
local function slow(what: string, t0: number)
	local dt = tern.now() - t0
	if dt >= SLOW_OP_MS then
		tern.log.warn(string.format("omp-tiles slow: %s %.1f ms", what, dt))
	end
end

-- Activity: Flow's work -> level model (hooks/activity.ts), fed from what
-- Tern reports about each agent block instead of Claude Code hooks.
type Tile = {
	pane: number,
	scene: any,
	sceneName: string?,
	frameAt: number?,
	frameCost: number?, -- ms its last frame took (step + drawing), to plan a pass
	frame: string?,
	heat: number,
	floor: number,
	turn: boolean,
	turnMs: number,
	waiting: boolean,
	inFlight: number,
	subagents: number,
	smokeMs: number,
	ctx: number?,
	ctxLabel: string?,
	effort: string?,
	ompTitle: string?,
	seen: { [string]: boolean },
	seenN: number,
	primed: boolean,
	lastMsg: string?,
	lastLen: number,
	pending: number,
	info: { [string]: any },
}

local tiles: { [number]: Tile } = {}
local order: { number } = {}
local shownCanvas: number? = nil
local cellsOf: { [number]: number } = {} -- canvas pane -> width in cells
local sizing = false
local lastSize = -math.huge
local lastPoll = -math.huge
local lastFrame = tern.now()
local loopArmed = false
local waitOpen = 0 -- loop passes left to find a copy just opened
local nextTile = 1 -- where the next pass starts stepping scenes
local workedThisPass = false -- a render pass compiled or set up a scene: it does nothing else heavy
local setupPending = false -- the view needs rebuilding (and scenes setting up) on the next pass

local EFFORT_FLOOR = { minimal = 2, low = 2, medium = 3, high = 4, xhigh = 5, max = 6 }

local function str(v: any): string?
	return if type(v) == "string" and v ~= "" then v else nil
end

-- Flow's dial: idle is its default low glow (level 1, the blue pilot light);
-- only a turn at work (or subagents still running) lifts it.
local function strength(t: Tile): number
	if not (t.turn or t.subagents > 0) then
		return 1
	end
	local boost = if t.subagents > 0 then 1.2 * math.log(1 + t.subagents, 2) else 0
	local turnBoost = if t.turn then t.turnMs // 30000 else 0
	local s = math.clamp(math.floor((if t.turn then t.floor else 1) + t.heat + boost + 0.5) + turnBoost, 1, 10)
	return if t.waiting then math.min(s, 2) else s
end

local function tint(t: Tile): string
	if t.smokeMs > 0 then
		return "smoke"
	end
	if t.ctx and t.ctx >= 0.85 then
		return "blue"
	end
	return "normal"
end

local function addHeat(t: Tile, n: number)
	t.heat = math.min(5, t.heat + n)
end

local function tick(t: Tile, ms: number)
	local frames = ms / FRAME_MS
	if t.turn and not t.waiting then
		t.turnMs += ms
	end
	if t.pending > 0 then
		addHeat(t, math.min(0.025 * frames, t.pending * 0.002))
		t.pending = 0
	end
	t.heat *= 0.98 ^ frames
	if t.heat < 0.01 then
		t.heat = 0
	end
	if (t.turn or t.subagents > 0) and t.inFlight > 0 and t.heat < 1 then
		t.heat = 1
	end
	t.smokeMs = math.max(0, t.smokeMs - ms)
end

local function linesOf(tool: { [string]: any }): number
	local meta = tool.meta
	if type(meta) == "table" then
		for _, m in meta do
			local n = type(m) == "string" and string.match(m, "%+(%d+)")
			if n then
				return tonumber(n) or 1
			end
		end
	end
	return 1
end

-- What a new tool call adds, as Flow weighs it.
local function toolHeat(t: Tile, tool: { [string]: any })
	local name = str(tool.name) or ""
	if name == "edit" or name == "write" or name == "ast_edit" or name == "notebook" then
		addHeat(t, math.min(4, 1 + linesOf(tool) / 15))
	elseif name == "bash" or name == "eval" or name == "python" then
		addHeat(t, 1)
	elseif name == "task" then
		addHeat(t, 0.5)
	else
		addHeat(t, 0.5)
	end
end

local function surfaceProp(cx: WindowCx, pane: number, root: string): { [string]: any }?
	local ok, tree = pcall(function()
		return cx.session:surface(pane, { as = "table", root = root, depth = 0 })
	end)
	if not ok or type(tree) ~= "table" then
		return nil
	end
	local node = (tree :: any).main or (tree :: any).dock
	return if type(node) == "table" and type(node.p) == "table" then node.p else nil
end

-- omp shows the session title as its input's placeholder: in curly quotes,
-- led by an icon glyph; Tern's agent title is only the shell's. Returns
-- nil for any other placeholder.
local function sessionTitle(placeholder: any): string?
	local text = placeholder
	if type(placeholder) == "table" then
		local parts = {}
		for _, s in placeholder do
			if type(s) == "table" and type(s.t) == "string" then
				table.insert(parts, s.t)
			end
		end
		text = table.concat(parts)
	end
	if type(text) ~= "string" or not utf8.len(text) then
		return nil
	end
	local inner = string.match(text, "^%s*“(.*)”%s*$")
	if not inner then
		return nil
	end
	local kept = {}
	for _, c in utf8.codes(inner) do
		-- Drop icon glyphs: the Private Use Areas.
		if not ((c >= 0xE000 and c <= 0xF8FF) or c >= 0xF0000) then
			table.insert(kept, utf8.char(c))
		end
	end
	return str(string.match(table.concat(kept), "^%s*(.-)%s*$"))
end

local PATH_LEVELS = 4 -- a tile shows only the last levels of its directory

-- The last PATH_LEVELS directories of a path, led by "…" when cut.
local function shortPath(path: string): string
	local sep = if string.find(path, "\\", 1, true) then "\\" else "/"
	local parts = {}
	for part in string.gmatch(path, "[^\\/]+") do
		table.insert(parts, part)
	end
	if #parts <= PATH_LEVELS then
		return path
	end
	return "…" .. sep .. table.concat(parts, sep, #parts - PATH_LEVELS + 1)
end

local function poll(cx: WindowCx)
	local sessions: { [number]: string } = {}
	local sorder: { [number]: number } = {}
	for i, s in cx.sessions:list() do
		sessions[s.id] = s.name
		sorder[s.id] = i
	end
	local tabs: { [number]: TabInfo } = {}
	for _, tab in cx.session:tabs() do
		tabs[tab.id] = tab
	end
	local alive: { [number]: boolean } = {}
	local list: { { [string]: any } } = {}
	for _, a in cx.agents:list() :: { any } do
		if a.state ~= "exited" then
			table.insert(list, a)
		end
	end
	for _, a in list do
		local pane: number = a.pane
		alive[pane] = true
		local t = tiles[pane]
		if not t then
			t = {
				pane = pane,
				scene = nil,
				sceneName = nil,
				frameAt = nil,
				heat = 0,
				floor = 3,
				turn = false,
				turnMs = 0,
				waiting = false,
				inFlight = 0,
				subagents = 0,
				smokeMs = 0,
				seen = {},
				seenN = 0,
				primed = false,
				lastLen = 0,
				pending = 0,
				info = {},
			}
			tiles[pane] = t
		end
		local tab = if type(a.tab) == "number" then tabs[a.tab] else nil
		local state = str(a.state) or "idle"
		-- Tern's state comes from omp's progress escape, which can stay on after a
		-- turn ends; `busy` follows the turn itself, so it wins when present.
		if state == "working" and a.busy == false then
			state = "idle"
		end
		local wasTurn = t.turn
		t.turn = state == "working"
		t.waiting = state == "waiting_input"
		if t.turn and not wasTurn then
			t.turnMs = 0
		end
		-- Session title, model, effort and context, as omp's composer shows them.
		local omp = surfaceProp(cx, pane, "3.line/input")
		t.ompTitle = if omp then sessionTitle(omp.placeholder) else nil
		local tOp = tern.now()
		local ctx = surfaceProp(cx, pane, "3.context")
		if ctx and type(ctx.value) == "number" then
			local prev = t.ctx
			t.ctx = ctx.value
			t.ctxLabel = str(ctx.title)
			if prev and prev - ctx.value > 0.15 then
				-- A real compaction: the fire drops to nothing and smokes.
				t.heat = 0
				t.smokeMs = 40 * FRAME_MS
			end
		end
		local eff = surfaceProp(cx, pane, "3.bar/model/effort")
		slow("surface pane " .. tostring(pane), tOp)
		t.effort = if eff then str(eff.level) else nil
		t.floor = if t.effort then (EFFORT_FLOOR[t.effort] or 3) else 3
		-- Tool calls and streamed text since the last poll.
		tOp = tern.now()
		local okT, msgs = pcall(function()
			return cx.agents:transcript(pane, { last = 4 })
		end)
		slow("transcript pane " .. tostring(pane), tOp)
		local inFlight, subagents = 0, 0
		local working = t.turn or t.subagents > 0
		if okT and type(msgs) == "table" then
			for mi, m in msgs :: { any } do
				if type(m.tools) == "table" then
					for ti, tool in m.tools do
						-- The call's own id; without one, its place in the transcript
						-- (counted from the end, so it holds while new messages arrive).
						local key = str(tool.key)
							or string.format("%s#%d.%d", tostring(tool.name), #msgs - mi, ti)
						local status = str(tool.status) or "pending"
						if status == "running" or status == "pending" then
							inFlight += 1
							if tool.name == "task" then
								subagents += 1
							end
						end
						if not t.seen[key] then
							t.seen[key] = true
							t.seenN += 1
							-- Calls already there when the tile first saw them, or made
							-- while the agent is not at work, add no heat.
							if t.primed and working then
								toolHeat(t, tool)
							end
						end
						local errKey = key .. "#error"
						if status == "error" and not t.seen[errKey] then
							t.seen[errKey] = true
							if t.primed and working then
								-- A failed call: the fire dips and smokes for ~2 s.
								t.smokeMs = 30 * FRAME_MS
								t.heat = math.max(0, t.heat - 2)
							end
						end
					end
				end
			end
			local last = msgs[#msgs]
			if last and last.role == "assistant" and type(last.text) == "string" then
				local id = tostring(#msgs) .. ":" .. string.sub(last.text, 1, 64)
				local len = #last.text
				if t.primed and t.turn then
					local grown = if id == t.lastMsg and len >= t.lastLen then len - t.lastLen else len
					if id ~= t.lastMsg or len > t.lastLen then
						t.pending += grown
					end
				end
				t.lastMsg, t.lastLen = id, len
			end
		end
		-- Forget old calls now and then, keeping the ones still on screen:
		-- they must not count as new.
		if t.seenN > 400 then
			table.clear(t.seen)
			t.seenN = 0
			for mi, m in (if okT and type(msgs) == "table" then msgs else {}) :: { any } do
				for ti, tool in m.tools or {} do
					local key = str(tool.key) or string.format("%s#%d.%d", tostring(tool.name), #msgs - mi, ti)
					t.seen[key] = true
					t.seen[key .. "#error"] = true
					t.seenN += 2
				end
			end
		end
		t.primed = true
		if not working then
			t.heat, t.pending = 0, 0
		end
		t.inFlight, t.subagents = inFlight, subagents
		local session = if type(a.session) == "number" then a.session else (tab and tab.session)
		t.info = {
			session = session,
			sessionName = if session then sessions[session] else nil,
			sessionOrder = if session then (sorder[session] or 99) else 99,
			tabPos = if tab then tab.position else 99,
			tabColor = if tab then tab.color else nil,
			title = t.ompTitle or str(a.title) or (tab and str(tab.name)) or "omp",
			cwd = str(a.cwd) or "",
			model = str(a.model),
			state = state,
			alert = a.alert == true,
		}
	end
	for pane in tiles do
		if not alive[pane] then
			tiles[pane] = nil
		end
	end
	-- The order is shared by every copy (tern.kv): saved tiles keep their place,
	-- new ones go after them in Tern's own order (session, then tab).
	local fresh: { number } = {}
	for pane in tiles do
		table.insert(fresh, pane)
	end
	table.sort(fresh, function(x, y)
		local a, b = tiles[x].info, tiles[y].info
		if a.sessionOrder ~= b.sessionOrder then
			return a.sessionOrder < b.sessionOrder
		end
		if a.tabPos ~= b.tabPos then
			return a.tabPos < b.tabPos
		end
		return x < y
	end)
	local saved = tern.kv.get("order")
	local placed: { [number]: boolean } = {}
	table.clear(order)
	if type(saved) == "table" then
		for _, v in saved do
			local p = tonumber(v)
			if p and tiles[p] and not placed[p] then
				placed[p] = true
				table.insert(order, p)
			end
		end
	end
	for _, p in fresh do
		if not placed[p] then
			table.insert(order, p)
		end
	end
end

local STATE_LABEL = {
	working = { "lavora", "pending" },
	waiting_input = { "attende te", "warning" },
	idle = { "inattivo", "muted" },
}

-- What every copy shares, kept in tern.kv: per tile its color, scene, columns
-- and rows; and the order of the tiles.
local function colorOf(t: Tile): string?
	local saved = tern.kv.get("color:" .. tostring(t.pane))
	if saved == "none" then
		return nil
	end
	if type(saved) == "string" then
		return saved
	end
	return str(t.info.tabColor)
end

local function spanOf(t: Tile): (number, number)
	local w = tonumber(tern.kv.get("w:" .. tostring(t.pane))) or 1
	local h = tonumber(tern.kv.get("h:" .. tostring(t.pane))) or 1
	return math.clamp(w, 1, MAX_COLS), math.clamp(h, 1, MAX_ROWS)
end

local function colsFor(cells: number?): number
	return math.clamp((cells or 0) // COL_MIN_CELLS, MIN_COLS, MAX_COLS)
end

-- The tile's scene: its own pick, else fire (Flow's default).
local function sceneOf(t: Tile): string
	local saved = tern.kv.get("scene:" .. tostring(t.pane))
	if type(saved) == "string" and table.find(scenes.NAMES, saved) then
		return saved
	end
	return "fire"
end

-- A tile's look as copied by "Copia stile": its scene and color, kept in
-- tern.kv so every copy of the block (and a restart) can paste it.
type Style = { scene: string, color: string }

local function copiedStyle(): Style?
	local s = tern.kv.get("style-clip")
	if type(s) == "table" and type(s.scene) == "string" and type(s.color) == "string" then
		return s :: any
	end
	return nil
end

-- The right-click menu (Tern adds its own Copy, of the tile's text, after
-- it). Labels come from the action names: "copia-stile" reads "Copia stile".
-- "Incolla stile" shows only once a style has been copied.
local function menuFor(canPaste: boolean): { string }
	if canPaste then
		return { "personalizza", "copia-stile", "incolla-stile" }
	end
	return { "personalizza", "copia-stile" }
end

-- Each scene's icon in the options panel (Tern's icon set).
local SCENE_ICON: { [string]: string } = {
	fire = "flame",
	warp = "sparkle",
	avalon = "globe",
	engine = "rocket",
	bubbles = "wave",
}

-- Tiles whose options panel is open, in this window only.
local optsOpen: { [number]: boolean } = {}

-- The options panel: scene, color, size and position, each a row of
-- buttons. Size is a small grid as wide as the block's columns: the cell
-- clicked is the tile's new bottom-right corner.
local function optsNode(t: Tile, cols: number): Node
	local current = sceneOf(t)
	local color = colorOf(t)
	local w, h = spanOf(t)
	w = math.min(w, cols)
	local sceneKids = {}
	for _, s in scenes.NAMES do
		table.insert(sceneKids, ui.el("button", {
			key = s,
			class = "omt-opt" .. (if s == current then " omt-on" else ""),
			title = "Scena " .. s,
			actions = { click = "scene=" .. s },
		}, {
			ui.node("icon", { key = "i", name = SCENE_ICON[s] or "flame" }),
			ui.el("span", { key = "t", text = s }),
		}))
	end
	local colorKids = {
		ui.el("button", {
			key = "none",
			class = "omt-sw omt-sw-none" .. (if color == nil then " omt-on" else ""),
			title = "Nessun colore",
			actions = { click = "color=none" },
		}, { ui.node("icon", { key = "i", name = "slash-circle" }) }),
	}
	for _, c in COLORS do
		table.insert(colorKids, ui.el("button", {
			key = c,
			class = "omt-sw omt-" .. c .. (if c == color then " omt-on" else ""),
			title = c,
			actions = { click = "color=" .. c },
		}))
	end
	local cells = {}
	for r = 1, MAX_ROWS do
		for c = 1, cols do
			local size = tostring(c) .. "x" .. tostring(r)
			table.insert(cells, ui.el("button", {
				key = "s" .. size,
				class = "omt-cell" .. (if c <= w and r <= h then " omt-on" else ""),
				title = tostring(c) .. " × " .. tostring(r),
				actions = { click = "size=" .. size },
			}))
		end
	end
	local function row(key: string, icon: string, label: string, kids: { Node }): Node
		return ui.el("div", { key = key, class = "omt-optrow" }, {
			ui.el("div", { key = "l", class = "omt-optlabel" }, {
				ui.node("icon", { key = "i", name = icon }),
				ui.el("span", { key = "t", text = label }),
			}),
			ui.el("div", { key = "c", class = "omt-optctl" }, kids),
		})
	end
	return ui.el("div", {
		key = "opts",
		class = "omt-opts",
		-- Clicks between the buttons must not take you to the session.
		actions = { click = "noop" },
	}, {
		row("scene", "reel", "Scena", sceneKids),
		row("color", "palette", "Colore", colorKids),
		row("size", "grid", "Dimensione", {
			ui.el("div", { key = "grid", class = "omt-sizegrid omt-c" .. tostring(cols) }, cells),
			ui.el("span", { key = "n", class = "omt-sizelabel", text = tostring(w) .. " × " .. tostring(h) }),
		}),
		row("move", "swap", "Posizione", {
			ui.el("button", { key = "l", class = "omt-opt", title = "Sposta a sinistra", actions = { click = "move=-1" } }, {
				ui.node("icon", { key = "i", name = "arrow-left" }),
			}),
			ui.el("button", { key = "r", class = "omt-opt", title = "Sposta a destra", actions = { click = "move=1" } }, {
				ui.node("icon", { key = "i", name = "arrow-right" }),
			}),
			ui.el("button", { key = "x", class = "omt-opt omt-close", title = "Chiudi", actions = { click = "personalizza" } }, {
				ui.node("icon", { key = "i", name = "check" }),
				ui.el("span", { key = "t", text = "Fatto" }),
			}),
		}),
	})
end

-- Flow's clock: night from 19:00 to 7:00 (local time).
local function isNight(): boolean
	local hour = tonumber(os.date("%H")) or 12
	return hour >= NIGHT_FROM or hour < DAY_FROM
end

-- Flow's dials, as its SceneDriver sets them each frame.
local function dial(t: Tile)
	local s = t.scene
	s.strength = strength(t)
	s.coverageBoost = math.min(60, t.subagents * 15)
	s.tint = tint(t)
	s.night = isNight()
	s.waiting = t.waiting
end

-- A frame as ANSI rows (pi/ansi.ts): 24-bit colors, the terminal's own where Flow leaves it.
local function rgb(c: number): string
	return string.format("%d;%d;%d", bit32.extract(c, 16, 8), bit32.extract(c, 8, 8), bit32.extract(c, 0, 8))
end
local function ansi(g: any): string
	local lines = table.create(g.rows)
	local cols = g.columns
	for r = 0, g.rows - 1 do
		local parts = {}
		local fg, bg = DEFAULT_COLOR, DEFAULT_COLOR
		for x = 0, cols - 1 do
			local i = r * cols + x
			local f, b = g:foreground(i), g:background(i)
			if f ~= fg or b ~= bg then
				if (f == DEFAULT_COLOR and fg ~= DEFAULT_COLOR) or (b == DEFAULT_COLOR and bg ~= DEFAULT_COLOR) then
					table.insert(parts, "\27[0m")
					fg, bg = DEFAULT_COLOR, DEFAULT_COLOR
				end
				if f ~= fg then
					table.insert(parts, "\27[38;2;" .. rgb(f) .. "m")
				end
				if b ~= bg then
					table.insert(parts, "\27[48;2;" .. rgb(b) .. "m")
				end
				fg, bg = f, b
			end
			table.insert(parts, utf8.char(g:codePoint(i)))
		end
		if not (fg == DEFAULT_COLOR and bg == DEFAULT_COLOR) then
			table.insert(parts, "\27[0m")
		end
		lines[r + 1] = table.concat(parts)
	end
	return table.concat(lines, "\n")
end

-- The tile's scene as last drawn; `draw` draws a fresh frame first.
local function sceneNode(t: Tile, draw: boolean?): Node
	if draw and t.scene then
		t.frame = ansi(t.scene:grid())
	end
	return ui.node("ansi", { key = "fire", text = t.frame or "" })
end

-- The scene fills the tile: as many cells wide as its columns allow, taller
-- when the tile spans two rows. A new scene starts when the pick changes;
-- a new size keeps it going (Flow's scenes resize themselves). Setting one
-- up costs a few milliseconds (more the first time its code loads), so a
-- pass sets up as many as fit its budget and leaves the rest for the next:
-- returns whether this tile is ready.
local function sceneFor(t: Tile, cols: number, cells: number, start: number, deadline: number): boolean
	local w, h = spanOf(t)
	local span = math.min(w, cols)
	local sw = math.max(16, math.floor(cells / cols * span) - 8)
	local sh = SCENE_H + (h - 1) * SCENE_H_STEP
	local name = sceneOf(t)
	-- A heavy scene's cost grows with its area: past MAX_AREA it stays this
	-- big, narrower than the tile and centered in it.
	local maxArea = MAX_AREA[name]
	if maxArea and sw * sh > maxArea then
		sw = math.max(16, math.floor(maxArea / sh))
	end
	local s = t.scene
	local stale = not s or t.sceneName ~= name or s.columns ~= sw or s.rows ~= sh or not t.frame
	if not stale then
		return true
	end
	if tern.now() > deadline then
		return false
	end
	-- One heavy step per pass: compiling a scene file (up to ~25 ms) or
	-- setting a scene up (up to ~40 ms for a big engine) leaves no room for
	-- a second one, or for sending the view, inside Tern's 50 ms.
	if workedThisPass then
		return false
	end
	workedThisPass = true
	if not s or t.sceneName ~= name then
		if not scenes.loaded(name) then
			tern.log.warn("omp-tiles compile " .. name) -- logged before: names the step if Tern stops the timer
			scenes.load(name)
			return false
		end
	end
	local tOp = tern.now()
	tern.log.warn(string.format("omp-tiles setup %s %dx%d", name, sw, sh))
	if not s or t.sceneName ~= name then
		s = scenes.make(name, math.floor(tern.now()) + t.pane % 100000)
		t.scene = s
		t.sceneName = name
	end
	s:ensure(sw, sh)
	-- Its first frame at this size, so the view never shows an empty or stale-sized one.
	dial(t)
	s:step()
	t.frame = ansi(s:grid())
	slow(string.format("setup %s %dx%d", name, sw, sh), tOp)
	return true
end

local function tileNode(t: Tile, cols: number, menu: { string }): Node
	local i = t.info
	local color = colorOf(t)
	local w, h = spanOf(t)
	local st = STATE_LABEL[i.state] or { i.state, "muted" }
	local ctxPct = if t.ctx then string.format("%d%%", math.floor(t.ctx * 100 + 0.5)) else "—"
	local model = (i.model or "?") .. (if t.effort then " · " .. t.effort else "")
	local meter = ui.node("meter", {
		key = "ctx",
		value = t.ctx or 0,
		style = "bar",
		label = ctxPct,
		title = t.ctxLabel or "Contesto",
		thresholds = { warn = 0.5, bad = 0.85 },
		grow = 1,
	})
	local class = "omt-tile omt-w" .. tostring(math.min(w, cols)) .. " omt-h" .. tostring(h)
	-- /compact buttons: live only while omp is idle; otherwise greyed, and a
	-- click just says why.
	local idle = i.state == "idle"
	local function compactButton(key: string, label: string, command: string): Node
		return ui.el("button", {
			key = key,
			class = "omt-btn" .. (if idle then "" else " omt-btn-off"),
			text = label,
			title = if idle then command else command .. " (solo con omp fermo)",
			actions = { click = (if idle then key else "busy") .. "=" .. tostring(t.pane) },
		})
	end
	local kids = {
		ui.el("div", { key = "head", class = "omt-head" }, {
			ui.el("span", { key = "dot", class = "omt-dot" }),
			ui.node("text", {
				key = "name",
				wrap = "none",
				truncate = "end",
				grow = 1,
				spans = {
					ui.span(i.title, "strong"),
				},
			}),
			ui.node("badge", { key = "state", text = st[1], tone = st[2] }),
			ui.el("button", {
				key = "opts",
				class = "omt-optbtn",
				title = "Personalizza",
				actions = { click = "personalizza" },
			}, { ui.node("icon", { key = "i", name = "sliders" }) }),
		}),
		ui.el("div", { key = "where", class = "omt-where" }, {
			ui.el("div", { key = "cwd", class = "omt-cwd" }, {
				ui.node("text", {
					key = "path",
					wrap = "none",
					truncate = "start",
					spans = { ui.span(shortPath(i.cwd), "path") },
				}),
			}),
			ui.el("span", { key = "session", class = "omt-session", text = i.sessionName or "" }),
		}),
		ui.el("div", { key = "facts", class = "omt-facts" }, {
			ui.node("text", { key = "model", wrap = "none", spans = { ui.span(model, "accent") } }),
			meter,
		}),
		ui.el("div", { key = "acts", class = "omt-acts" }, {
			compactButton("compact", "compact", "/compact"),
			compactButton("snapcompact", "snapcompact", "/compact snapcompact"),
		}),
	}
	if optsOpen[t.pane] then
		table.insert(kids, optsNode(t, cols))
	end
	table.insert(kids, ui.el("div", { key = "flame", class = "omt-fire" }, { sceneNode(t) }))
	return ui.el("div", {
		key = "p" .. tostring(t.pane),
		class = class .. (if color then " omt-" .. color else ""),
		title = i.cwd,
		actions = { click = "go=" .. tostring(t.pane), menu = menu },
	}, kids)
end

-- The grid: `cols` equal columns (explicit tracks: Tern's CSS has no
-- auto-fill); a tile spans its own columns and rows.
local function view(cols: number): Node
	local kids = {}
	local menu = menuFor(copiedStyle() ~= nil)
	for _, pane in order do
		table.insert(kids, tileNode(tiles[pane], cols, menu))
	end
	if #kids == 0 then
		table.insert(kids, ui.node("text", { key = "empty", spans = { ui.span("Nessuna sessione omp aperta in Tern.", "muted") } }))
	end
	return ui.el("div", { key = "grid", class = "omt-grid omt-c" .. tostring(cols) }, kids)
end

-- Our canvases, one per Tern session, by the session that holds them.
local function canvases(cx: WindowCx): { [number]: number }
	local sessionOfTab: { [number]: number } = {}
	for _, tab in cx.session:tabs() do
		sessionOfTab[tab.id] = tab.session
	end
	local bySession: { [number]: number } = {}
	for _, c in cx.canvas:list() do
		if c.owner == tern.plugin.id and c.title == TITLE then
			local tab = cx.session:tab_of(c.pane)
			local s = tab and sessionOfTab[tab]
			if s and not bySession[s] then
				bySession[s] = c.pane
			end
		end
	end
	return bySession
end

-- The copy on screen now: the one in the focused pane's tab.
local function onScreen(cx: WindowCx, all: { [number]: number }): number?
	local focused = cx.session:focused()
	local tab = focused and cx.session:tab_of(focused)
	if not tab then
		return nil
	end
	for _, pane in all do
		if cx.session:tab_of(pane) == tab then
			return pane
		end
	end
	return nil
end

-- Block widths in cells, from `tern ls` (the window API reports no pane size).
local function measure()
	if sizing or tern.runtime.os == "ios" then
		return
	end
	sizing = true
	local ok = pcall(function()
		tern.process.run({ "tern", "ls", "--json" }, { timeout_ms = 5000 }, function(r, _cx)
			sizing = false
			if r.status ~= 0 then
				return
			end
			local okJ, doc = pcall(tern.json.decode, r.stdout)
			if not okJ or type(doc) ~= "table" then
				return
			end
			for _, s in doc.sessions or {} do
				for _, tab in s.tabs or {} do
					for _, b in tab.blocks or {} do
						if b.program == "tern.canvas" and type(b.id) == "number" and type(b.cols) == "number" then
							local prev = cellsOf[b.id]
							cellsOf[b.id] = b.cols
							if prev ~= b.cols then
								setupPending = true -- the block changed width: rebuild the view
							end
						end
					end
				end
			end
		end)
	end)
	if not ok then
		sizing = false
	end
end

local function render(cx: WindowCx, pane: number, start: number)
	local cells = cellsOf[pane] or (COL_MIN_CELLS * MIN_COLS)
	local cols = colsFor(cells)
	local deadline = start + PASS_BUDGET_MS
	local pending = false
	workedThisPass = false
	for _, p in order do
		if not sceneFor(tiles[p], cols, cells, start, deadline) then
			pending = true
			break -- a heavy step already done: the rest on the next pass
		end
	end
	-- A pass that compiled or set up a scene leaves the view for the next
	-- one (sending it costs up to ~35 ms); the old view stays meanwhile.
	if pending or workedThisPass then
		setupPending = true
		return
	end
	local tSet = tern.now()
	cx.canvas:set(pane, { view = view(cols) })
	slow("render view+set", tSet)
end

local loop: (cx: WindowCx?) -> ()
local function arm(ms: number)
	if loopArmed then
		return
	end
	loopArmed = true
	tern.timer(ms, function(cx)
		loopArmed = false
		loop(cx)
	end)
end

-- One loop for every copy: only the copy on screen is drawn and animated;
-- another copy gets the current view when you come to its session.
loop = function(cx: WindowCx?)
	if not cx then
		return
	end
	local all = canvases(cx)
	if next(all) == nil then
		shownCanvas = nil
		-- No copy open. A copy just opened takes a moment to reach this
		-- window's list, so look again a few times before going to sleep.
		if waitOpen > 0 then
			waitOpen -= 1
			arm(CALM_FRAME_MS)
		end
		return
	end
	waitOpen = 0
	local now = tern.now()
	local passStart = now
	local phase = "anim"
	local ms = math.min(1000, now - lastFrame)
	lastFrame = now
	local pane = onScreen(cx, all)
	if pane ~= shownCanvas then
		shownCanvas = pane
		lastPoll = -math.huge
		lastSize = -math.huge
	end
	if pane and now - lastSize >= SIZE_MS then
		lastSize = now
		measure()
	end
	for _, t in tiles do
		tick(t, ms)
	end
	if now - lastPoll >= (if pane then POLL_MS else HIDDEN_MS) then
		-- Read the agents; the view is rebuilt on the next pass, with its own budget.
		lastPoll = now
		poll(cx)
		phase = "poll"
		setupPending = pane ~= nil
	elseif pane and setupPending then
		setupPending = false
		phase = "render"
		render(cx, pane, tern.now())
	elseif pane then
		-- Each scene moves at Flow's pace (a frame every 70 ms, 125 when calm)
		-- by its own clock. A pass steps and draws only what fits in its share
		-- of Tern's 50 ms budget, starting after the tile it stopped at, so a
		-- slow scene never stalls the window or starves the others.
		local patch: { [string]: Node | false } = {}
		local n = #order
		local start = tern.now()
		for k = 1, n do
			local idx = (nextTile + k - 2) % n + 1
			local p = order[idx]
			local t = tiles[p]
			if t and t.scene then
				local pace = if t.scene.strength <= 1 and t.scene.tint == "normal" then CALM_FRAME_MS else FRAME_MS
				local due = math.min(MAX_CATCHUP, (now - (t.frameAt or now - pace)) // pace)
				local cost = t.frameCost or 0
				-- A frame that would not fit what is left of the budget waits for
				-- the next pass, which starts with it (an engine frame alone can
				-- take ~22 ms); a slow scene does not catch up on missed frames.
				if due >= 1 and tern.now() - start > 0.5 and tern.now() - start + cost > PASS_BUDGET_MS then
					nextTile = idx
					break
				end
				if cost > PASS_BUDGET_MS / 4 then
					due = math.min(due, 1)
				end
				if due >= 1 then
					local tFrame = tern.now()
					dial(t)
					for _ = 1, due do
						t.scene:step()
					end
					t.frameAt = now
					patch["p" .. tostring(p) .. ".flame.fire"] = sceneNode(t, true)
					t.frameCost = (tern.now() - tFrame) / due
					slow("frame " .. tostring(t.sceneName), tFrame)
				end
			end
			if tern.now() - start > PASS_BUDGET_MS then
				nextTile = idx % n + 1
				break
			end
		end
		if next(patch) then
			local tSet = tern.now()
			cx.canvas:set(pane, { set = patch })
			slow("anim set", tSet)
		end
	end
	local passMs = tern.now() - passStart
	if passMs >= SLOW_PASS_MS then
		tern.log.warn(string.format("omp-tiles slow pass: %s %.1f ms, %d tiles", phase, passMs, #order))
	end
	arm(if pane then FRAME_MS else HIDDEN_MS)
end

-- Ctrl+Alt+R: this session's copy, opened beside the focused pane if it has none.
local function open(cx: WindowCx)
	local pane = canvases(cx)[cx.sessions:current().id]
	if pane then
		cx.layout:focus(pane)
		lastPoll = -math.huge
		arm(0)
		return
	end
	poll(cx)
	local p, err = cx.canvas:open({
		title = TITLE,
		about = "Tile delle sessioni omp aperte in Tern. Click: vai alla sessione. Tasto destro: colore, posizione e dimensioni del tile.",
		view = view(MIN_COLS),
		how = "beside",
	})
	if not p then
		cx:toast("error", "omp Tiles non aperto", err)
		return
	end
	lastPoll = -math.huge
	lastSize = -math.huge
	waitOpen = 20
	arm(0)
end

tern.command({
	id = "open",
	title = "Apri omp Tiles",
	icon = "sparkle",
	keys = { "ctrl+alt+r" },
	run = open,
})

local function move(pane: number, by: number)
	for i, p in order do
		if p == pane then
			local j = i + by
			if j >= 1 and j <= #order then
				order[i], order[j] = order[j], order[i]
				local saved = {}
				for k, q in order do
					saved[k] = tostring(q) -- as strings: pane ids can exceed JSON's exact integers
				end
				tern.kv.set("order", saved)
			end
			return
		end
	end
end

-- The tile's new size from the options panel's grid: columns × rows.
local function resize(pane: number, size: string)
	local w, h = string.match(size, "^(%d+)x(%d+)$")
	if w and h then
		tern.kv.set("w:" .. tostring(pane), math.clamp(tonumber(w) :: number, 1, MAX_COLS))
		tern.kv.set("h:" .. tostring(pane), math.clamp(tonumber(h) :: number, 1, MAX_ROWS))
	end
end

tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean?
	local mine = false
	for _, pane in canvases(cx) do
		mine = mine or pane == ev.pane
	end
	if not mine then
		return false
	end
	if ev.act == "go" and ev.value then
		local target = tonumber(ev.value)
		local t = target and tiles[target]
		if t and t.info.session then
			cx.sessions:switch(t.info.session)
		end
		if target then
			cx.layout:focus(target)
		end
		return true
	end
	local COMPACT = { compact = "/compact", snapcompact = "/compact snapcompact" }
	if (COMPACT[ev.act] or ev.act == "busy") and ev.value then
		local target = tonumber(ev.value)
		local t = target and tiles[target]
		if not (target and t) then
			return true
		end
		-- The state may have changed since the view was drawn: check it again.
		if ev.act == "busy" or t.info.state ~= "idle" then
			cx:toast("info", "omp sta lavorando", "Compact solo quando la sessione è ferma.")
			return true
		end
		local ok, err = pcall(function()
			cx.agents:ask(target, COMPACT[ev.act])
		end)
		if ok then
			cx:toast("info", COMPACT[ev.act] .. " inviato", t.info.title)
			lastPoll = -math.huge
			arm(0)
		else
			cx:toast("error", "Compact non inviato", tostring(err))
		end
		return true
	end
	local paneStr = string.match(ev.node, "%f[%w]p(%d+)")
	local pane = paneStr and tonumber(paneStr)
	if not paneStr or not pane then
		return false
	end
	local value = ev.value or ""
	if ev.act == "noop" then
		return true
	elseif ev.act == "personalizza" then
		optsOpen[pane] = not optsOpen[pane]
	elseif ev.act == "copia-stile" then
		local t = tiles[pane]
		if not t then
			return true
		end
		local style: Style = { scene = sceneOf(t), color = colorOf(t) or "none" }
		tern.kv.set("style-clip", style)
		cx:toast("info", "Stile copiato", style.scene .. ", " .. (if style.color == "none" then "nessun colore" else style.color))
	elseif ev.act == "incolla-stile" then
		local style = copiedStyle()
		if not style then
			return true
		end
		if table.find(scenes.NAMES, style.scene) then
			tern.kv.set("scene:" .. paneStr, style.scene)
		end
		if style.color == "none" or table.find(COLORS, style.color) then
			tern.kv.set("color:" .. paneStr, style.color)
		end
		-- One paste per copy: pasting again needs a new "Copia stile".
		tern.kv.set("style-clip", nil)
	elseif ev.act == "color" and (value == "none" or table.find(COLORS, value)) then
		tern.kv.set("color:" .. paneStr, value)
	elseif ev.act == "scene" and table.find(scenes.NAMES, value) then
		tern.kv.set("scene:" .. paneStr, value)
	elseif ev.act == "size" then
		resize(pane, value)
	elseif ev.act == "move" and tonumber(value) then
		move(pane, tonumber(value) :: number)
	else
		return false
	end
	setupPending = true
	arm(0)
	return true
end)

-- Changing session or tab, a copy restored after a restart: wake the loop.
tern.on("focus", function(_ev, _cx)
	arm(0)
end)
tern.on("window_start", function(_cx)
	arm(0)
end)
tern.timer(300, function(_cx)
	arm(0)
end)
