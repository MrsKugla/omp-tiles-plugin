--!strict
-- omp Tiles: a canvas block with one colored tile per omp session running in
-- Tern, across every Tern session: Tern session → omp session, directory,
-- model, context and a small Flow scene (flow/, a port of robdmac/flow) that
-- moves with the work. Each tile has its own scene, picked from its menu.
-- Each Tern session gets its own copy of the block; all copies show the same
-- tiles, colors, scenes, order and sizes. The tiles sit in an invisible grid
-- of at least two columns, more as the block widens. Click a tile to go
-- there; right-click it to pick its scene, color, move or resize it.

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
local LOAD_SLACK_MS = 2 -- a file of a scene's code (up to ~20 ms to compile in Tern) loads only this early in a pass
local HIDDEN_MS = 1500
local POLL_MS = 1000
local SIZE_MS = 2000
local COLORS = { "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink" }

-- Activity: Flow's work -> level model (hooks/activity.ts), fed from what
-- Tern reports about each agent block instead of Claude Code hooks.
type Tile = {
	pane: number,
	scene: any,
	sceneName: string?,
	frameAt: number?,
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
		local wasTurn = t.turn
		t.turn = state == "working"
		t.waiting = state == "waiting_input"
		if t.turn and not wasTurn then
			t.turnMs = 0
		end
		-- Model, effort and context, as omp's composer shows them.
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
		t.effort = if eff then str(eff.level) else nil
		t.floor = if t.effort then (EFFORT_FLOOR[t.effort] or 3) else 3
		-- Tool calls and streamed text since the last poll.
		local okT, msgs = pcall(function()
			return cx.agents:transcript(pane, { last = 4 })
		end)
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
			title = str(a.title) or (tab and str(tab.name)) or "omp",
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

-- Menu labels come from the action names: `scene-engine` reads "Scene engine".
local function menu(): { string }
	local items = {}
	for _, s in scenes.NAMES do
		table.insert(items, "scene-" .. s)
	end
	for _, a in { "move-left", "move-right", "wider", "narrower", "taller", "shorter" } do
		table.insert(items, a)
	end
	for _, c in COLORS do
		table.insert(items, "color-" .. c)
	end
	table.insert(items, "color-none")
	return items
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
	local s = t.scene
	local stale = not s or t.sceneName ~= name or s.columns ~= sw or s.rows ~= sh or not t.frame
	if not stale then
		return true
	end
	if tern.now() > deadline then
		return false
	end
	if not s or t.sceneName ~= name then
		if not scenes.loaded(name) then
			-- Compiling a scene's code is the slow part (up to ~20 ms a file):
			-- one file, only on a pass that has done almost nothing yet, and
			-- then the pass stops.
			if tern.now() - start <= LOAD_SLACK_MS then
				scenes.load(name)
			end
			return false
		end
		s = scenes.make(name, math.floor(tern.now()) + t.pane % 100000)
		t.scene = s
		t.sceneName = name
	end
	s:ensure(sw, sh)
	-- Its first frame at this size, so the view never shows an empty or stale-sized one.
	dial(t)
	s:step()
	t.frame = ansi(s:grid())
	return true
end

local function tileNode(t: Tile, cols: number): Node
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
	return ui.el("div", {
		key = "p" .. tostring(t.pane),
		class = class .. (if color then " omt-" .. color else ""),
		title = i.cwd,
		actions = { click = "go=" .. tostring(t.pane), menu = menu() },
	}, {
		ui.el("div", { key = "head", class = "omt-head" }, {
			ui.el("span", { key = "dot", class = "omt-dot" }),
			ui.node("text", {
				key = "name",
				wrap = "none",
				truncate = "end",
				grow = 1,
				spans = {
					ui.span(i.sessionName or "?", "muted"),
					ui.span(" → ", "dim"),
					ui.span(i.title, "strong"),
				},
			}),
			ui.node("badge", { key = "state", text = st[1], tone = st[2] }),
		}),
		ui.node("text", {
			key = "cwd",
			wrap = "none",
			truncate = "middle",
			spans = { ui.span(i.cwd, "path") },
		}),
		ui.el("div", { key = "facts", class = "omt-facts" }, {
			ui.node("text", { key = "model", wrap = "none", spans = { ui.span(model, "accent") } }),
			meter,
		}),
		ui.el("div", { key = "flame", class = "omt-fire" }, { sceneNode(t) }),
	})
end

-- The grid: `cols` equal columns (explicit tracks: Tern's CSS has no
-- auto-fill); a tile spans its own columns and rows.
local function view(cols: number): Node
	local kids = {}
	for _, pane in order do
		table.insert(kids, tileNode(tiles[pane], cols))
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
	for _, p in order do
		if not sceneFor(tiles[p], cols, cells, start, deadline) then
			pending = true
			break -- out of budget, or a module loading: the rest on the next pass
		end
	end
	cx.canvas:set(pane, { view = view(cols) })
	if pending then
		setupPending = true
	end
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
		setupPending = pane ~= nil
	elseif pane and setupPending then
		setupPending = false
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
				if due >= 1 then
					dial(t)
					for _ = 1, due do
						t.scene:step()
					end
					t.frameAt = now
					patch["p" .. tostring(p) .. ".flame.fire"] = sceneNode(t, true)
				end
			end
			if tern.now() - start > PASS_BUDGET_MS then
				nextTile = idx % n + 1
				break
			end
		end
		if next(patch) then
			cx.canvas:set(pane, { set = patch })
		end
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

local function resize(pane: number, axis: string, by: number)
	local t = tiles[pane]
	if not t then
		return
	end
	local w, h = spanOf(t)
	if axis == "w" then
		tern.kv.set("w:" .. tostring(pane), math.clamp(w + by, 1, MAX_COLS))
	else
		tern.kv.set("h:" .. tostring(pane), math.clamp(h + by, 1, MAX_ROWS))
	end
end

local ACTIONS: { [string]: (number) -> () } = {
	["move-left"] = function(p) move(p, -1) end,
	["move-right"] = function(p) move(p, 1) end,
	wider = function(p) resize(p, "w", 1) end,
	narrower = function(p) resize(p, "w", -1) end,
	taller = function(p) resize(p, "h", 1) end,
	shorter = function(p) resize(p, "h", -1) end,
}

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
	local paneStr = string.match(ev.node, "%f[%w]p(%d+)")
	local pane = paneStr and tonumber(paneStr)
	if not paneStr or not pane then
		return false
	end
	local color = string.match(ev.act, "^color%-(%a+)$")
	local scene = string.match(ev.act, "^scene%-(%a+)$")
	if color then
		tern.kv.set("color:" .. paneStr, color)
	elseif scene then
		tern.kv.set("scene:" .. paneStr, scene)
	elseif ACTIONS[ev.act] then
		ACTIONS[ev.act](pane)
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
