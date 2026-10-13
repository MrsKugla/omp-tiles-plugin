--!strict
-- omp Tiles: a canvas block with one colored tile per omp session running in
-- Tern, across every Tern session: omp session title, state, directory, Tern
-- session, model and context.
-- Each Tern session gets its own copy of the block; all copies show the same
-- tiles, colors and order. The tiles sit in an invisible grid of at least
-- two columns, more as the block widens. Click a tile to go there;
-- the palette by its Tern session's name colors that session; its ← →
-- arrows move it.

local ui = tern.ui

local TITLE = "omp Tiles"
local COL_MIN_CELLS = 44 -- a grid column is at least this many cells wide
local MIN_COLS, MAX_COLS = 2, 8
local POLL_MS = 1000 -- refresh while a copy is on screen
local HIDDEN_MS = 1500 -- look for a copy coming on screen
local OPEN_MS = 125 -- look for a copy just opened
local SIZE_MS = 2000
local COLORS = { "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink" }

type Tile = {
	pane: number,
	ctx: number?,
	ctxLabel: string?,
	effort: string?,
	ompTitle: string?, -- last title omp showed: the placeholder hides while you type
	info: { [string]: any },
}

local tiles: { [number]: Tile } = {}
local order: { number } = {}
local shownCanvas: number? = nil
local cellsOf: { [number]: number } = {} -- canvas pane -> width in cells
local sizing = false
local lastSize = -math.huge
local waitOpen = 0 -- loop runs left to find a copy just opened

local function str(v: any): string?
	return if type(v) == "string" and v ~= "" then v else nil
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

-- omp's composer (input, context meter, model bar) is a dock node whose id
-- moves between omp versions ("3", then "j"): found by its role among the
-- one-character ids, one node read at a time (~0.1 ms in all; reading the
-- whole surface can pass Tern's 50 ms), then kept per pane until a read
-- through it fails. A miss is retried after 10 s.
local composerOf: { [number]: string? } = {}
local composerMiss: { [number]: number } = {}
local ID_CHARS = "123456789abcdefghijklmnopqrstuvwxyz"
local function findComposer(cx: WindowCx, pane: number): string?
	if tern.now() - (composerMiss[pane] or -math.huge) < 10000 then
		return nil
	end
	for k = 1, #ID_CHARS do
		local id = string.sub(ID_CHARS, k, k)
		local p = surfaceProp(cx, pane, id)
		if p and p.role == "omp.editor" then
			composerMiss[pane] = nil
			return id
		end
	end
	composerMiss[pane] = tern.now()
	return nil
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
	for _, a in cx.agents:list() :: { any } do
		if a.state == "exited" then
			continue
		end
		local pane: number = a.pane
		alive[pane] = true
		local t = tiles[pane]
		if not t then
			t = { pane = pane, info = {} }
			tiles[pane] = t
		end
		local tab = if type(a.tab) == "number" then tabs[a.tab] else nil
		local state = str(a.state) or "idle"
		-- Tern's state comes from omp's progress escape, which can stay on after a
		-- turn ends; `busy` follows the turn itself, so it wins when present.
		if state == "working" and a.busy == false then
			state = "idle"
		end
		-- Session title, model, effort and context, as omp's composer shows them.
		local root = composerOf[pane]
		local omp = if root then surfaceProp(cx, pane, root .. ".line/input") else nil
		if not omp then
			root = findComposer(cx, pane)
			composerOf[pane] = root
			omp = if root then surfaceProp(cx, pane, root .. ".line/input") else nil
		end
		local ctx = if root then surfaceProp(cx, pane, root .. ".context") else nil
		if ctx and type(ctx.value) == "number" then
			t.ctx = ctx.value
			t.ctxLabel = str(ctx.title)
		end
		local eff = if root then surfaceProp(cx, pane, root .. ".bar/model/effort") else nil
		t.effort = if eff then str(eff.level) else nil
		local shown = if omp then sessionTitle(omp.placeholder) else nil
		if shown then
			t.ompTitle = shown
		end
		local session = if type(a.session) == "number" then a.session else (tab and tab.session)
		t.info = {
			session = session,
			sessionName = if session then sessions[session] else nil,
			sessionOrder = if session then (sorder[session] or 99) else 99,
			tabPos = if tab then tab.position else 99,
			title = t.ompTitle or str(a.title) or (tab and str(tab.name)) or "omp",
			cwd = str(a.cwd) or "",
			model = str(a.model),
			state = state,
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

-- Window-only interaction state: the open color picker (the tile showing
-- it, its Tern session and the color being tried, shown on every tile of
-- that session until confirmed).
type ColorPick = { pane: number, session: number, color: string? }
local colorPick: ColorPick? = nil

-- What every copy shares, kept in tern.kv: each Tern session's color and
-- the order of the tiles.
local function colorOf(t: Tile): string?
	local session = t.info.session
	if not session then
		return nil
	end
	local saved = tern.kv.get("scolor:" .. tostring(session))
	if colorPick and colorPick.session == session and colorPick.color then
		saved = colorPick.color
	end
	return if type(saved) == "string" and table.find(COLORS, saved) then saved else nil
end

local function colsFor(cells: number?): number
	return math.clamp((cells or 0) // COL_MIN_CELLS, MIN_COLS, MAX_COLS)
end

-- The color picker, inside the tile whose session name was right-clicked:
-- a click on a dot tries it on every tile of the session; Conferma keeps it.
local function pickerNode(t: Tile): Node
	local color = colorOf(t)
	local kids = {
		ui.el("button", {
			key = "none",
			class = "omt-sw omt-sw-none" .. (if color == nil then " omt-on" else ""),
			title = "Nessun colore",
			actions = { click = "swatch=none" },
		}, { ui.node("icon", { key = "i", name = "slash-circle" }) }),
	}
	for _, c in COLORS do
		table.insert(kids, ui.el("button", {
			key = c,
			class = "omt-sw omt-" .. c .. (if c == color then " omt-on" else ""),
			title = c,
			actions = { click = "swatch=" .. c },
		}))
	end
	return ui.el("div", {
		key = "picker",
		class = "omt-picker",
		-- Clicks between the buttons must not take you to the session.
		actions = { click = "noop" },
	}, {
		ui.el("div", { key = "dots", class = "omt-dots" }, kids),
		ui.el("div", { key = "btns", class = "omt-pickbtns" }, {
			ui.el("button", { key = "cancel", class = "omt-btn", text = "Annulla", actions = { click = "swatch-cancel" } }),
			ui.el("button", { key = "ok", class = "omt-btn omt-btn-ok", text = "Conferma", actions = { click = "swatch-ok" } }),
		}),
	})
end

local function tileNode(t: Tile): Node
	local i = t.info
	local color = colorOf(t)
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
	local paneStr = tostring(t.pane)
	local go = "go=" .. tostring(t.pane)
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
			-- The palette shows while the pointer is on this row; it opens the
			-- session's color picker (again: closes it).
			ui.el("button", {
				key = "palette",
				class = "omt-palette",
				title = "Colore della sessione Tern",
				actions = { click = "colore-sessione=" .. paneStr },
			}, { ui.node("icon", { key = "i", name = "palette" }) }),
			ui.el("span", { key = "session", class = "omt-session", text = i.sessionName or "" }),
		}),
		ui.el("div", { key = "facts", class = "omt-facts" }, {
			ui.node("text", { key = "model", wrap = "none", spans = { ui.span(model, "accent") } }),
			meter,
		}),
		ui.el("div", { key = "acts", class = "omt-acts" }, {
			compactButton("compact", "compact", "/compact"),
			-- Move arrows, shown while the pointer is on the tile.
			ui.el("div", { key = "move", class = "omt-move" }, {
				-- Tern's icon set has no left chevron: the right one, mirrored in CSS.
				ui.el("button", { key = "l", class = "omt-arrow omt-arrow-l", title = "Sposta a sinistra", actions = { click = "left=" .. paneStr } }, {
					ui.node("icon", { key = "i", name = "chev-r" }),
				}),
				ui.el("button", { key = "r", class = "omt-arrow", title = "Sposta a destra", actions = { click = "right=" .. paneStr } }, {
					ui.node("icon", { key = "i", name = "chev-r" }),
				}),
			}),
		}),
	}
	if colorPick and colorPick.pane == t.pane then
		table.insert(kids, pickerNode(t))
	end
	return ui.el("div", {
		key = "p" .. paneStr,
		class = "omt-tile" .. (if color then " omt-" .. color else ""),
		title = i.cwd,
		actions = { click = go },
	}, kids)
end

-- The grid: `cols` equal columns (explicit tracks: Tern's CSS has no
-- auto-fill); a tile spans its own columns and rows.
local function view(cols: number): Node
	local kids = {}
	for _, pane in order do
		table.insert(kids, tileNode(tiles[pane]))
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
							cellsOf[b.id] = b.cols
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

local function render(cx: WindowCx, pane: number)
	cx.canvas:set(pane, { view = view(colsFor(cellsOf[pane])) })
end

-- One loop for every copy: only the copy on screen is refreshed; another
-- copy gets the current view when you come to its session. `arm` replaces
-- the pending run, so an action or a focus change refreshes at once.
local loop: (cx: WindowCx?) -> ()
local armed = 0
local function arm(ms: number)
	armed += 1
	local mine = armed
	tern.timer(ms, function(cx)
		if mine == armed then
			loop(cx)
		end
	end)
end

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
			arm(OPEN_MS)
		end
		return
	end
	waitOpen = 0
	local pane = onScreen(cx, all)
	if pane ~= shownCanvas then
		shownCanvas = pane
		lastSize = -math.huge
	end
	if not pane then
		arm(HIDDEN_MS)
		return
	end
	local now = tern.now()
	if now - lastSize >= SIZE_MS then
		lastSize = now
		measure()
	end
	poll(cx)
	render(cx, pane)
	arm(POLL_MS)
end

-- Ctrl+Alt+R: this session's copy, opened beside the focused pane if it has none.
local function open(cx: WindowCx)
	local pane = canvases(cx)[cx.sessions:current().id]
	if pane then
		cx.layout:focus(pane)
		arm(0)
		return
	end
	poll(cx)
	local p, err = cx.canvas:open({
		title = TITLE,
		about = "Tile delle sessioni omp aperte in Tern. Click: vai alla sessione. Tasto destro sul nome della sessione Tern: colore. Frecce: sposta.",
		view = view(MIN_COLS),
		how = "beside",
	})
	if not p then
		cx:toast("error", "omp Tiles non aperto", err)
		return
	end
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

-- The ← → arrows swap a tile with the one before or after it. Saved as
-- strings: pane ids can exceed JSON's exact integers.
local function shift(pane: number, by: number)
	local from = table.find(order, pane)
	local to = from and from + by
	if not from or not to or to < 1 or to > #order then
		return
	end
	order[from], order[to] = order[to], order[from]
	local saved = {}
	for k, q in order do
		saved[k] = tostring(q)
	end
	tern.kv.set("order", saved)
end

tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean?
	local mine = false
	for _, pane in canvases(cx) do
		mine = mine or pane == ev.pane
	end
	if not mine then
		return false
	end
	local target = tonumber(ev.value)
	if ev.act == "go" and target then
		local t = tiles[target]
		if t and t.info.session then
			cx.sessions:switch(t.info.session)
		end
		cx.layout:focus(target)
		return true
	end
	local COMPACT = { compact = "/compact" }
	if (COMPACT[ev.act] or ev.act == "busy") and target then
		local t = tiles[target]
		if not t then
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
			arm(0)
		else
			cx:toast("error", "Compact non inviato", tostring(err))
		end
		return true
	end
	if (ev.act == "left" or ev.act == "right") and target then
		shift(target, if ev.act == "left" then -1 else 1)
		render(cx, ev.pane)
		return true
	end
	if ev.act == "noop" then
		return true
	end
	-- The color picker of a Tern session, opened from the palette on its row.
	if ev.act == "colore-sessione" and target then
		local t = tiles[target]
		if not (t and t.info.session) then
			return true
		end
		colorPick = if colorPick and colorPick.pane == target then nil else { pane = target, session = t.info.session, color = nil }
	elseif ev.act == "swatch" and colorPick and (ev.value == "none" or table.find(COLORS, ev.value or "")) then
		colorPick.color = ev.value
	elseif ev.act == "swatch-ok" and colorPick then
		if colorPick.color then
			tern.kv.set("scolor:" .. tostring(colorPick.session), colorPick.color)
		end
		colorPick = nil
	elseif ev.act == "swatch-cancel" then
		colorPick = nil
	else
		return false
	end
	render(cx, ev.pane)
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
