-- GatherPath Forever: routes through your GatherMate2 nodes, drawn on the
-- world map and the minimap.
--
-- A route belongs to one map (zone). It's made from the kinds of node you pick
-- (Peacebloom, Copper Vein...), read from GatherMate2, put in the shortest
-- loop Optimize.lua can find, and saved as a list of map positions.

local ADDON, ns = ...
local T = ns.Theme
local O = ns.Optimize

local GP = {}
ns.GP = GP
GatherPathForever = GP

local sqrt, max, min, floor, cos, sin = math.sqrt, math.max, math.min, math.floor, math.cos, math.sin

local function Print(msg) print(T.CHAT_PREFIX .. ": " .. msg) end
GP.Print = Print

GP.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Icon"
GP.LOGO_TEXT = "|T" .. GP.ICON .. ":0|t"

GP.DEFAULTS = {
    worldMap = true,       -- draw routes on the world map
    minimap = true,        -- and on the minimap
    worldWidth = 4,        -- line width on the world map
    minimapWidth = 3,      -- and on the minimap
    worldAlpha = 85,       -- line opacity on the world map (percent)
    minimapAlpha = 85,     -- and on the minimap
    worldRouteColor = true,    -- world map lines in each route's own color
    minimapRouteColor = true,  -- minimap lines too
    worldColor = { 1, 0.82, 0 },   -- the world map's one color when worldRouteColor is off
    minimapColor = { 1, 0.82, 0 }, -- and the minimap's
    range = false,         -- a circle round you on the minimap: how far Find Herbs/Find Minerals show nodes
    rangeYards = 100,      -- its radius
    rangeAlpha = 60,       -- its opacity (percent)
    rangeColor = { 0.25, 0.80, 1.00 },  -- its color
    arrows = true,         -- arrows along the lines show which way round to ride
    arrowsReverse = false, -- and they point the other way
    joinLine = true,       -- a dashed line on the minimap from you to the nearest point of a route
    tabooShow = true,      -- taboo areas drawn (red, hatched) on the world map
    autoAdd = true,        -- nodes GatherMate2 finds later join the routes they belong to
    minimapButton = true,
    minimapAngle = 200,
    sight = 185,           -- where New route's "route passes within" starts (yards, 0 = go to every node)
    nextColor = 1,
}
-- The settings on the Display tab, which its Restore defaults button puts back
-- (not routes, the minimap button's place, New route's slider or the remembered speed)
GP.DISPLAY_KEYS = {
    "worldMap", "minimap", "worldWidth", "minimapWidth", "worldAlpha", "minimapAlpha",
    "worldRouteColor", "minimapRouteColor", "worldColor", "minimapColor",
    "arrows", "arrowsReverse", "joinLine",
    "range", "rangeYards", "rangeAlpha", "rangeColor",
    "autoAdd", "minimapButton",
}
GP.RANGES = {
    worldWidth = { 1, 10 },
    minimapWidth = { 1, 8 },
    worldAlpha = { 10, 100 },
    minimapAlpha = { 10, 100 },
    rangeYards = { 20, 200 },
    rangeAlpha = { 10, 100 },
    sight = { 0, 200 },
}

-- New routes take these in turn
GP.COLORS = {
    { 1.00, 0.82, 0.00 },   -- gold
    { 0.25, 0.80, 1.00 },   -- blue
    { 1.00, 0.35, 0.30 },   -- red
    { 0.45, 1.00, 0.40 },   -- green
    { 1.00, 0.55, 0.10 },   -- orange
    { 0.85, 0.50, 1.00 },   -- purple
    { 1.00, 1.00, 1.00 },   -- white
}

-- GatherMate2's kinds of node, in the order they're listed, with our names for them
GP.KINDS = { "Herb Gathering", "Mining", "Fishing", "Treasure", "Extract Gas", "Archaeology", "Logging" }
GP.KIND_NAMES = {
    ["Herb Gathering"] = "Herbs", ["Mining"] = "Ore", ["Fishing"] = "Fishing",
    ["Treasure"] = "Treasure", ["Extract Gas"] = "Gas", ["Archaeology"] = "Archaeology", ["Logging"] = "Logging",
}

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function GP:LoadSettings()
    GatherPathForeverDB = type(GatherPathForeverDB) == "table" and GatherPathForeverDB or {}
    local db = GatherPathForeverDB
    -- 1.1.0 started "pass within" at 50 yards; 1.1.1 starts it at 100
    if db.sight == 50 and not db.sight100 then db.sight = nil end
    db.sight100 = true
    db.merge = nil   -- New route's "merge nodes closer than" until 1.3.0
    -- one "Opacity" for both kinds of line until 1.5.0
    if type(db.alpha) == "number" then
        if db.worldAlpha == nil then db.worldAlpha = db.alpha end
        if db.minimapAlpha == nil then db.minimapAlpha = db.alpha end
    end
    db.alpha = nil
    for k, v in pairs(self.DEFAULTS) do
        if type(v) == "table" then
            local c = db[k]
            local ok = type(c) == "table"
            for i = 1, 3 do ok = ok and type(c[i]) == "number" end
            db[k] = ok and { max(0, min(1, c[1])), max(0, min(1, c[2])), max(0, min(1, c[3])) } or { unpack(v) }
        elseif db[k] == nil then
            db[k] = v
        end
    end
    for k, r in pairs(self.RANGES) do
        if type(db[k]) ~= "number" then db[k] = self.DEFAULTS[k] end
        db[k] = max(r[1], min(r[2], db[k]))
    end
    -- node names left out of every route (the skip list): { [name] = true }
    local skip = {}
    if type(db.skip) == "table" then
        for name, on in pairs(db.skip) do
            if type(name) == "string" and on == true then skip[name] = true end
        end
    end
    db.skip = skip
    -- taboo areas: { [mapID] = { { x1, y1, x2, y2, ... }, ... } }, map positions 0-1
    local taboos = {}
    if type(db.taboos) == "table" then
        for mapID, list in pairs(db.taboos) do
            if type(mapID) == "number" and type(list) == "table" then
                local keep = {}
                for _, xy in ipairs(list) do
                    if type(xy) == "table" and #xy >= 6 and #xy % 2 == 0 then
                        local ok = true
                        for i = 1, #xy do ok = ok and type(xy[i]) == "number" end
                        if ok then keep[#keep + 1] = xy end
                    end
                end
                if #keep > 0 then taboos[mapID] = keep end
            end
        end
    end
    db.taboos = taboos
    db.routes = type(db.routes) == "table" and db.routes or {}
    db.nextID = db.nextID or 1
    -- drop anything that isn't a usable route
    for i = #db.routes, 1, -1 do
        local r = db.routes[i]
        if type(r) ~= "table" or type(r.mapID) ~= "number" or type(r.points) ~= "table" then
            table.remove(db.routes, i)
        else
            r.kinds = type(r.kinds) == "table" and r.kinds or {}
            r.name = type(r.name) == "string" and r.name or "Route"
            r.color = type(r.color) == "table" and r.color or { 1, 0.82, 0 }
            if r.shown == nil then r.shown = true end
            if not r.id then r.id = db.nextID; db.nextID = db.nextID + 1 end
            r.merge = nil   -- gone in 1.3.0: "route passes within" groups nearby nodes itself
        end
    end
    self.db = db
end

-- The Display tab's Restore defaults: every setting on it as it was to start
function GP:RestoreDefaults()
    local db = self.db
    for _, k in ipairs(self.DISPLAY_KEYS) do
        local v = self.DEFAULTS[k]
        db[k] = type(v) == "table" and { unpack(v) } or v
    end
    db.hiddenWas = nil   -- lines hidden from the minimap button come back too
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end
    self:Changed()
end

---------------------------------------------------------------------------
-- Maps
---------------------------------------------------------------------------
function GP:MapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or ("Map " .. tostring(mapID))
end

function GP:PlayerMap()
    return C_Map.GetBestMapForUnit("player")
end

-- How many yards across and down a map is. Cached; nil if the game can't say.
local yardCache = {}
function GP:MapYards(mapID)
    if yardCache[mapID] then return yardCache[mapID][1], yardCache[mapID][2] end
    local w, h
    if C_Map.GetMapWorldSize then
        w, h = C_Map.GetMapWorldSize(mapID)
    end
    if not (w and h and w > 0 and h > 0) and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        if a and b then
            local ax, ay = a:GetXY()
            local bx, by = b:GetXY()
            w, h = math.abs(ay - by), math.abs(ax - bx)   -- the world's x runs north, y west
        end
    end
    if not (w and h and w > 0 and h > 0) then return nil end
    yardCache[mapID] = { w, h }
    return w, h
end

-- Yards for the route solver; a map the game can't measure is taken as 1500 x 1000
local function Yards(mapID)
    local w, h = GP:MapYards(mapID)
    return w or 1500, h or 1000
end

local function PlayerPos(mapID)
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos.x, pos.y
    if x == nil and pos.GetXY then x, y = pos:GetXY() end
    if not x or (x == 0 and y == 0) then return nil end
    return x, y
end

---------------------------------------------------------------------------
-- GatherMate2
---------------------------------------------------------------------------
function GP:HasGatherMate()
    local gm = _G.GatherMate2
    return type(gm) == "table" and type(gm.GetNodesForZone) == "function" and type(gm.DecodeLoc) == "function"
end

-- GatherMate2's kinds, in our order, then any we don't know
function GP:Kinds()
    local list, seen = {}, {}
    local known = (_G.GatherMate2 and _G.GatherMate2.db_types) or {}
    local have = {}
    for _, k in ipairs(known) do have[k] = true end
    for _, k in ipairs(self.KINDS) do
        if have[k] or #known == 0 then list[#list + 1] = k; seen[k] = true end
    end
    for _, k in ipairs(known) do
        if not seen[k] then list[#list + 1] = k; seen[k] = true end
    end
    return list
end

function GP:KindName(kind) return self.KIND_NAMES[kind] or kind end

-- Calls fn(x, y, nodeName) for every GatherMate2 node of that kind on that map
function GP:EachNode(mapID, kind, fn)
    local gm = _G.GatherMate2
    if not self:HasGatherMate() then return end
    pcall(function()
        for coord, nodeID in gm:GetNodesForZone(mapID, kind, true) do
            local x, y = gm:DecodeLoc(coord)
            local name = gm.GetNameForNode and gm:GetNameForNode(kind, nodeID) or nil
            fn(x, y, name or ("Node " .. tostring(nodeID)))
        end
    end)
end

-- The skip list: node names (Poor Copper Ore, Wilted Peacebloom...) that no
-- route uses, in any zone. Routes that had one drop it when they're rebuilt.
function GP:IsSkipped(name) return self.db.skip[name] == true end

function GP:SetSkipped(name, on)
    if type(name) ~= "string" then return end
    self.db.skip[name] = on and true or nil
    self:Changed()
end

-- The skipped names, sorted
function GP:SkippedNames()
    local list = {}
    for name in pairs(self.db.skip) do list[#list + 1] = name end
    table.sort(list)
    return list
end

-- What GatherMate2 knows on a map: { { kind =, name =, count =, skip = }, ... }, by kind then name
function GP:ZoneNodes(mapID)
    local list = {}
    for _, kind in ipairs(self:Kinds()) do
        local counts = {}
        self:EachNode(mapID, kind, function(_, _, name) counts[name] = (counts[name] or 0) + 1 end)
        local names = {}
        for name in pairs(counts) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            list[#list + 1] = { kind = kind, name = name, count = counts[name], skip = self:IsSkipped(name) }
        end
    end
    return list
end

-- The maps GatherMate2 has nodes for, sorted by name
function GP:GatherZones()
    local gm = _G.GatherMate2
    local found = {}
    if self:HasGatherMate() and type(gm.gmdbs) == "table" then
        for _, kind in ipairs(self:Kinds()) do
            local db = gm.gmdbs[kind]
            if type(db) == "table" then
                -- GatherMate2 keeps nodes in its saved variables, by map number
                local stores = {}
                if type(rawget(db, "__gm2_base_storage")) == "table" then
                    stores[#stores + 1] = rawget(db, "__gm2_base_storage")
                    for _, s in pairs(rawget(db, "__gm2_storage_map") or {}) do stores[#stores + 1] = s end
                else
                    stores[1] = db
                end
                for _, store in ipairs(stores) do
                    for mapID, nodes in pairs(store) do
                        if type(mapID) == "number" and type(nodes) == "table" and next(nodes) then
                            found[mapID] = true
                        end
                    end
                end
            end
        end
    end
    local here = self:PlayerMap()
    if here then found[here] = true end
    local list = {}
    for mapID in pairs(found) do list[#list + 1] = mapID end
    table.sort(list, function(a, b) return self:MapName(a) < self:MapName(b) end)
    return list
end

-- The nodes a route is made from, as { x, y } map positions (none on the skip list)
function GP:CollectNodes(mapID, kinds)
    local pts = {}
    local skip = self.db.skip
    for kind, names in pairs(kinds) do
        self:EachNode(mapID, kind, function(x, y, name)
            if names[name] and not skip[name] then pts[#pts + 1] = { x, y } end
        end)
    end
    -- the same order every time, whatever order GatherMate2 gives them in
    table.sort(pts, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    return pts
end

-- A name for a route from what's in it: "Peacebloom", "Peacebloom and Silverleaf", "Herbs", "Herbs and Ore"...
function GP:RouteName(mapID, kinds)
    local names, whole = {}, {}
    local all = self:ZoneNodes(mapID)
    local perKind = {}
    for _, n in ipairs(all) do
        if not n.skip then perKind[n.kind] = (perKind[n.kind] or 0) + 1 end
    end
    for _, kind in ipairs(self:Kinds()) do
        local picked = kinds[kind]
        if picked and next(picked) then
            local list = {}
            for name in pairs(picked) do
                if not self:IsSkipped(name) then list[#list + 1] = name end
            end
            table.sort(list)
            if #list > 2 and #list >= (perKind[kind] or 0) then
                whole[#whole + 1] = self:KindName(kind)
            else
                for _, n in ipairs(list) do names[#names + 1] = n end
            end
        end
    end
    for _, w in ipairs(whole) do names[#names + 1] = w end
    if #names == 0 then return "Route" end
    if #names == 1 then return names[1] end
    if #names == 2 then return names[1] .. " and " .. names[2] end
    return names[1] .. ", " .. names[2] .. " and " .. (#names - 2) .. " more"
end

---------------------------------------------------------------------------
-- Routes
---------------------------------------------------------------------------
function GP:RoutesOn(mapID)
    local list = {}
    for _, r in ipairs(self.db.routes) do
        if r.mapID == mapID then list[#list + 1] = r end
    end
    return list
end

-- The maps that have routes, sorted by name
function GP:RouteZones()
    local seen, list = {}, {}
    for _, r in ipairs(self.db.routes) do
        if not seen[r.mapID] then seen[r.mapID] = true; list[#list + 1] = r.mapID end
    end
    table.sort(list, function(a, b) return self:MapName(a) < self:MapName(b) end)
    return list
end

-- Stops on the loop (fewer than nodes when the route only passes near them)
function GP:NodeCount(route) return floor(#route.points / 2) end

-- Nodes the route takes you past
function GP:RouteNodes(route) return route.nodes or self:NodeCount(route) end

-- The route's length in yards, round the loop
function GP:RouteLength(route)
    local w, h = Yards(route.mapID)
    local p = route.points
    local n = floor(#p / 2)
    if n < 2 then return 0 end
    local total = 0
    for i = 1, n do
        local j = i % n + 1
        local dx, dy = (p[2 * j - 1] - p[2 * i - 1]) * w, (p[2 * j] - p[2 * i]) * h
        total = total + sqrt(dx * dx + dy * dy)
    end
    return total
end

local function Round(v) return floor(v * 10000 + 0.5) / 10000 end

---------------------------------------------------------------------------
-- Taboo areas: parts of a zone routes keep out of. No node inside one is
-- used, and a line that would cross one goes round it instead.
---------------------------------------------------------------------------
-- The taboo areas on a map: a list of flat { x1, y1, x2, y2, ... } (map positions)
function GP:Taboos(mapID)
    return self.db.taboos[mapID] or {}
end

-- The taboo areas of a map as walls for the solver (yards), or nil if none.
-- Kept until an area changes.
local wallCache = {}
GP.tabooVersion = 0
local function WallsFor(mapID)
    local list = GP.db.taboos[mapID]
    if not list or #list == 0 then return nil end
    local c = wallCache[mapID]
    if c and c.version == GP.tabooVersion then return c.walls end
    local w, h = Yards(mapID)
    local polys = {}
    for i, xy in ipairs(list) do
        local p = {}
        for k = 1, #xy, 2 do p[k], p[k + 1] = xy[k] * w, xy[k + 1] * h end
        polys[i] = p
    end
    local walls = O.Walls(polys)
    wallCache[mapID] = { version = GP.tabooVersion, walls = walls }
    return walls
end
GP.WallsFor = WallsFor

-- Is this map position inside one of the map's taboo areas?
function GP:InTaboo(mapID, x, y)
    local walls = WallsFor(mapID)
    if not walls then return false end
    local w, h = Yards(mapID)
    return walls:Inside({ x * w, y * h })
end

-- Adds a taboo area (flat list of 3 or more corners, map positions). Turned
-- down if its edges cross. Every route on that map is then worked out again.
function GP:AddTaboo(mapID, xy)
    if type(mapID) ~= "number" or type(xy) ~= "table" or #xy < 6 then
        Print("a taboo area needs at least 3 corners.")
        return false
    end
    local w, h = Yards(mapID)
    local yards = {}
    for k = 1, #xy, 2 do yards[k], yards[k + 1] = xy[k] * w, xy[k + 1] * h end
    if O.SelfCrossing(yards) then
        Print("that area's edges cross each other. Right-click to take corners back until they don't, then Finish.")
        return false
    end
    local copy = {}
    for k = 1, #xy do copy[k] = Round(xy[k]) end
    self.db.taboos[mapID] = self.db.taboos[mapID] or {}
    table.insert(self.db.taboos[mapID], copy)
    self.tabooVersion = self.tabooVersion + 1
    self:Changed()
    self:RebuildZone(mapID)
    return true
end

function GP:DeleteTaboo(mapID, index)
    local list = self.db.taboos[mapID]
    if not (list and list[index]) then return false end
    table.remove(list, index)
    if #list == 0 then self.db.taboos[mapID] = nil end
    self.tabooVersion = self.tabooVersion + 1
    self:Changed()
    self:RebuildZone(mapID)
    return true
end

-- " 3 nodes in taboo areas left out." after a route's chat line, or ""
function GP:TabooNote(route)
    local n = route.taboo or 0
    if n <= 0 then return "" end
    return (" %d node%s in taboo areas left out."):format(n, n == 1 and "" or "s")
end

-- Rebuilds every route on a map, one after another
function GP:RebuildZone(mapID)
    self.queue = self.queue or {}
    for _, route in ipairs(self:RoutesOn(mapID)) do
        local queued = false
        for _, r in ipairs(self.queue) do if r == route then queued = true end end
        if not queued then self.queue[#self.queue + 1] = route end
    end
    self:PumpQueue()
end

-- Starts the next queued rebuild if nothing's being worked out
function GP:PumpQueue()
    local q = self.queue
    while q and #q > 0 and not self.job do
        local route = table.remove(q, 1)
        local alive = false
        for _, r in ipairs(self.db.routes) do if r == route then alive = true end end
        if alive and not route.working then self:RebuildRoute(route) end
    end
end

-- Reads the route's nodes from GatherMate2 and finds the shortest loop.
-- Runs inside a job (it pauses now and then). Returns how many nodes it read.
local function Build(route)
    local raw = GP:CollectNodes(route.mapID, route.kinds)
    local w, h = Yards(route.mapID)
    local walls = WallsFor(route.mapID)
    local pts = {}
    for _, p in ipairs(raw) do
        local q = { p[1] * w, p[2] * h }
        if not (walls and walls:Inside(q)) then pts[#pts + 1] = q end   -- none from inside a taboo area
    end
    O.SetWalls(walls)
    local stops = O.Expand(O.Shortcut(pts, route.sight or 0))
    O.SetWalls(nil)
    local flat = {}
    for _, p in ipairs(stops) do
        flat[#flat + 1] = Round(p[1] / w)
        flat[#flat + 1] = Round(p[2] / h)
    end
    route.points = flat
    route.nodes = #pts
    route.taboo = #raw - #pts   -- left out: in taboo areas
    route.length = GP:RouteLength(route)
    return #pts
end

-- One route is worked out at a time, a little each frame, so a big one
-- doesn't freeze the game
local BUDGET_MS = 10
local clock = debugprofilestop or function() return GetTime() * 1000 end

function GP:Busy() return self.job ~= nil end

function GP:RunJob(fn, done)
    if self.job then return false end
    local co = coroutine.create(fn)
    self.job = co
    O.Pause = function()
        if coroutine.running() == co then coroutine.yield() end
    end
    local driver = self.jobFrame
    if not driver then
        driver = CreateFrame("Frame")
        self.jobFrame = driver
    end
    driver:SetScript("OnUpdate", function()
        local start = clock()
        repeat
            local ok, a, b = coroutine.resume(co)
            if not ok then
                driver:SetScript("OnUpdate", nil)
                self.job = nil
                O.Pause = function() end
                O.SetWalls(nil)
                Print("|cffff5050couldn't work out the route:|r " .. tostring(a))
                if self.Changed then self:Changed() end
                return
            end
            if coroutine.status(co) == "dead" then
                driver:SetScript("OnUpdate", nil)
                self.job = nil
                O.Pause = function() end
                done(a, b)
                self:PumpQueue()
                return
            end
        until clock() - start > BUDGET_MS
    end)
    if self.Changed then self:Changed() end
    return true
end

GP.FormatYards = function(v)
    v = floor((v or 0) + 0.5)
    local s = tostring(v):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (s:gsub("^,", "")) .. " yards"
end

-- How fast you travel, in yards a second, for a lap's time: the last mount
-- speed seen (db.speed), else your speed on foot (7)
GP.FOOT_SPEED = 7
function GP:Speed()
    local s = self.db and self.db.speed
    return type(s) == "number" and s > 0 and s or self.FOOT_SPEED
end

-- Remember your ground speed while it's faster than on foot (mounted). The
-- game can hide it (a secret value), then it's left alone. True if it changed.
function GP:SampleSpeed()
    if not (GetUnitSpeed and self.db) then return false end
    local ok, changed = pcall(function()
        local _, run = GetUnitSpeed("player")
        if issecretvalue and issecretvalue(run) then return false end
        if type(run) ~= "number" or run <= self.FOOT_SPEED + 0.5 or run > 100 then return false end
        run = floor(run * 10 + 0.5) / 10
        if run == self.db.speed then return false end
        self.db.speed = run
        return true
    end)
    return ok and changed or false
end

-- About how long one lap of a route takes at Speed(), in words
function GP:LapTime(route)
    local secs = (route.length or self:RouteLength(route)) / self:Speed()
    if secs < 60 then return "under a minute" end
    local mins = floor(secs / 60 + 0.5)
    if mins < 60 then return ("about %d min"):format(mins) end
    return ("about %d h %02d min"):format(floor(mins / 60), mins % 60)
end

-- The route on this map already called this (any case, spaces round it ignored), but not `except`
function GP:RouteNamed(mapID, name, except)
    local want = type(name) == "string" and name:match("^%s*(.-)%s*$"):lower()
    if not want or want == "" then return nil end
    for _, r in ipairs(self.db.routes) do
        if r ~= except and r.mapID == mapID and r.name:match("^%s*(.-)%s*$"):lower() == want then return r end
    end
end

local function NameTakenMessage(name, mapID)
    return ("there's already a route called |cffffd100%s|r in %s. Give this one another name, "
        .. "or Rebuild that one."):format(name, GP:MapName(mapID))
end

-- Is any node picked in kinds ({ [kind] = { [name] = true } }) that isn't skipped?
function GP:AnyPicked(kinds)
    for _, names in pairs(kinds or {}) do
        for name, on in pairs(names) do
            if on and not self:IsSkipped(name) then return true end
        end
    end
    return false
end

-- opts: mapID, kinds = { [kind] = { [name] = true } }, name, sight
function GP:NewRoute(opts)
    if not self:HasGatherMate() then
        Print("needs GatherMate2, where the nodes come from.")
        return nil
    end
    if not self:AnyPicked(opts.kinds) then
        Print("pick at least one kind of node.")
        return nil
    end
    if self.job then
        Print("still working out the last route. Try again in a moment.")
        return nil
    end
    local name = (type(opts.name) == "string" and opts.name:match("^%s*(.-)%s*$")) or ""
    if name == "" then name = self:RouteName(opts.mapID, opts.kinds) end
    if self:RouteNamed(opts.mapID, name) then
        Print(NameTakenMessage(name, opts.mapID))
        return nil
    end
    local route = {
        id = self.db.nextID,
        mapID = opts.mapID,
        name = name,
        kinds = opts.kinds,
        sight = opts.sight or 0,
        color = { unpack(self.COLORS[(self.db.nextColor - 1) % #self.COLORS + 1]) },
        shown = true,
        points = {},
        working = true,
    }
    self.db.nextID = self.db.nextID + 1
    self.db.nextColor = self.db.nextColor % #self.COLORS + 1
    table.insert(self.db.routes, route)
    self:RunJob(function() return Build(route) end, function(read)
        route.working = nil
        if self:NodeCount(route) < 2 then
            self:DeleteRoute(route)
            Print("GatherMate2 has " .. (read == 1 and "only one" or "no") .. " node of those kinds in "
                .. self:MapName(route.mapID) .. ", so there's no route to make.")
            return
        end
        Print(("made |cffffd100%s|r in %s: %d nodes, %s round.%s"):format(route.name, self:MapName(route.mapID),
            self:RouteNodes(route), self.FormatYards(route.length), self:TabooNote(route)))
        self:Changed()
    end)
    return route
end

-- Reads the nodes again (GatherMate2 may know more by now) and finds the loop again
function GP:RebuildRoute(route)
    if self.job then
        Print("still working out the last route. Try again in a moment.")
        return false
    end
    if not self:HasGatherMate() then
        Print("needs GatherMate2, where the nodes come from.")
        return false
    end
    local before, oldPoints, oldNodes = self:RouteNodes(route), route.points, route.nodes
    route.working = true
    return self:RunJob(function() return Build(route) end, function()
        route.working = nil
        if self:NodeCount(route) < 2 then
            route.points, route.nodes = oldPoints, oldNodes   -- (GatherMate2's data went missing: keep what was there)
            Print("GatherMate2 has no nodes for " .. route.name .. " now, so it was left as it was.")
        else
            local after = self:RouteNodes(route)
            Print(("%s: %d nodes (%s), %s round.%s"):format(route.name, after,
                after == before and "no change" or ((after > before and "+" or "") .. (after - before)),
                self.FormatYards(route.length), self:TabooNote(route)))
        end
        self:Changed()
    end)
end

-- Changes a route's options (opts as for NewRoute) and finds its loop again.
-- Turned down like NewRoute; if no loop can be made, the route stays as it was.
function GP:EditRoute(route, opts)
    if not self:HasGatherMate() then
        Print("needs GatherMate2, where the nodes come from.")
        return false
    end
    if not self:AnyPicked(opts.kinds) then
        Print("pick at least one kind of node.")
        return false
    end
    if self.job then
        Print("still working out the last route. Try again in a moment.")
        return false
    end
    local mapID = opts.mapID or route.mapID
    local name = (type(opts.name) == "string" and opts.name:match("^%s*(.-)%s*$")) or ""
    if name == "" then name = self:RouteName(mapID, opts.kinds) end
    if self:RouteNamed(mapID, name, route) then
        Print(NameTakenMessage(name, mapID))
        return false
    end
    local old = { mapID = route.mapID, name = route.name, kinds = route.kinds,
        sight = route.sight, points = route.points, nodes = route.nodes, length = route.length }
    route.mapID, route.name, route.kinds = mapID, name, opts.kinds
    route.sight = opts.sight or 0
    route.working = true
    self:RunJob(function() return Build(route) end, function(read)
        route.working = nil
        if self:NodeCount(route) < 2 then
            for k, v in pairs(old) do route[k] = v end
            Print("GatherMate2 has " .. (read == 1 and "only one" or "no") .. " node of those kinds in "
                .. self:MapName(mapID) .. ", so " .. route.name .. " was left as it was.")
        else
            Print(("changed |cffffd100%s|r in %s: %d nodes, %s round.%s"):format(route.name, self:MapName(route.mapID),
                self:RouteNodes(route), self.FormatYards(route.length), self:TabooNote(route)))
        end
        self:Changed()
    end)
    return true
end

function GP:DeleteRoute(route)
    for i, r in ipairs(self.db.routes) do
        if r == route then table.remove(self.db.routes, i) break end
    end
    self:Changed()
end

function GP:RenameRoute(route, name)
    if type(name) == "string" and name:match("%S") then
        name = name:match("^%s*(.-)%s*$")
        if self:RouteNamed(route.mapID, name, route) then
            Print(NameTakenMessage(name, route.mapID))
            return false
        end
        route.name = name
        self:Changed()
        return true
    end
    return false
end

function GP:SetRouteShown(route, on)
    route.shown = on and true or false
    self:Changed()
end

function GP:SetRouteColor(route, r, g, b)
    route.color = { r, g, b }
    self:Changed()
end

-- A node GatherMate2 just found goes into each route of its kind on that map,
-- where it adds the least walking. One already there (within 5 yards of a stop,
-- or its "route passes within" distance of the line) is left alone.
function GP:AddNode(mapID, kind, x, y, name)
    if not self.db.autoAdd or self:IsSkipped(name) then return 0 end
    local w, h = Yards(mapID)
    local walls = WallsFor(mapID)
    if walls and walls:Inside({ x * w, y * h }) then return 0 end   -- in a taboo area
    local added = 0
    for _, route in ipairs(self:RoutesOn(mapID)) do
        if not route.working and route.kinds[kind] and route.kinds[kind][name] then
            local p, n = route.points, self:NodeCount(route)
            local near, sight = 5, route.sight or 0
            local c = { x * w, y * h }
            local pts, tour, close = {}, {}, false
            for i = 1, n do
                pts[i] = { p[2 * i - 1] * w, p[2 * i] * h }
                tour[i] = i
                if O.Dist(pts[i], c) <= near then close = true end
            end
            for i = 1, (sight > 0 and n > 1) and n or 0 do
                if O.SegDist(pts[i], pts[i % n + 1], c) <= sight then close = true end
            end
            if not close then
                O.SetWalls(walls)
                local at = O.BestInsert(pts, tour, c)
                local spot = c
                if sight > 0 and n > 1 then
                    spot = O.Place(pts[at], pts[at % n + 1], c, sight)
                end
                -- with taboo areas, the corners the new legs bend round go in too
                local add = {}
                if walls then
                    for _, v in ipairs(walls:Path(pts[at], spot)) do add[#add + 1] = v end
                end
                add[#add + 1] = spot
                if walls and n > 1 then
                    for _, v in ipairs(walls:Path(spot, pts[at % n + 1])) do add[#add + 1] = v end
                end
                O.SetWalls(nil)
                for k, v in ipairs(add) do
                    table.insert(p, 2 * (at + k - 1) + 1, Round(v[1] / w))
                    table.insert(p, 2 * (at + k - 1) + 2, Round(v[2] / h))
                end
                route.length = self:RouteLength(route)
                if route.nodes then route.nodes = route.nodes + 1 end
                added = added + 1
            end
        end
    end
    if added > 0 then self:Changed() end
    return added
end

-- A node deleted in GatherMate2 leaves the routes that have it (not ones that
-- only pass near their nodes)
function GP:RemoveNode(mapID, kind, x, y, name)
    local w, h = Yards(mapID)
    local walls = WallsFor(mapID)
    local removed = 0
    for _, route in ipairs(self:RoutesOn(mapID)) do
        if not route.working and route.kinds[kind] and route.kinds[kind][name]
            and (route.sight or 0) == 0 then
            local p = route.points
            for i = 1, self:NodeCount(route) do
                local dx, dy = (p[2 * i - 1] - x) * w, (p[2 * i] - y) * h
                if sqrt(dx * dx + dy * dy) < 1 then
                    table.remove(p, 2 * i - 1)
                    table.remove(p, 2 * i - 1)
                    local n = self:NodeCount(route)
                    if walls and n >= 2 then
                        -- its neighbours now meet: round any taboo area between them
                        local a = (i - 2) % n + 1
                        local b = a % n + 1
                        local pa, pb = { p[2 * a - 1] * w, p[2 * a] * h }, { p[2 * b - 1] * w, p[2 * b] * h }
                        for k, v in ipairs(walls:Path(pa, pb)) do
                            table.insert(p, 2 * (a + k - 1) + 1, Round(v[1] / w))
                            table.insert(p, 2 * (a + k - 1) + 2, Round(v[2] / h))
                        end
                    end
                    route.length = self:RouteLength(route)
                    if route.nodes then route.nodes = route.nodes - 1 end
                    removed = removed + 1
                    break
                end
            end
        end
    end
    if removed > 0 then self:Changed() end
    return removed
end

function GP:ListenToGatherMate()
    if self.listening or not self:HasGatherMate() then return end
    local gm = _G.GatherMate2
    if type(gm.RegisterMessage) ~= "function" then return end
    local function decode(coord)
        local ok, x, y = pcall(gm.DecodeLoc, gm, coord)
        if ok then return x, y end
    end
    local listener = {}
    pcall(gm.RegisterMessage, listener, "GatherMate2NodeAdded", function(_, zone, kind, coord, name)
        local x, y = decode(coord)
        if x and type(name) == "string" then self:AddNode(zone, kind, x, y, name) end
    end)
    pcall(gm.RegisterMessage, listener, "GatherMate2NodeDeleted", function(_, zone, kind, coord, name)
        local x, y = decode(coord)
        if x and type(name) == "string" then self:RemoveNode(zone, kind, x, y, name) end
    end)
    self.listening = true
end

---------------------------------------------------------------------------
-- Lines
---------------------------------------------------------------------------
-- A pool of lines on a frame: Get() hands out the next one; Done() hides the rest
local function LinePool(frame, layer)
    local pool = { lines = {}, used = 0 }
    function pool:Begin() self.used = 0 end
    function pool:Get()
        self.used = self.used + 1
        local line = self.lines[self.used]
        if not line then
            line = frame:CreateLine(nil, layer or "OVERLAY")
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            self.lines[self.used] = line
        end
        line:Show()
        return line
    end
    function pool:Done()
        for i = self.used + 1, #self.lines do self.lines[i]:Hide() end
    end
    return pool
end
GP.LinePool = LinePool

local function Paint(line, c, alpha, width)
    line:SetVertexColor(c[1], c[2], c[3], alpha)
    line:SetThickness(width)
end

-- The color a route's line is drawn in: its own, or the one picked for that map
-- ("world" or "minimap") on the Display tab
function GP:LineColor(route, where)
    local db = self.db
    if db[where .. "RouteColor"] then return route.color end
    return db[where .. "Color"]
end

-- Display tab's color for every line on that map ("world" or "minimap")
function GP:SetLineColor(where, r, g, b)
    self.db[where .. "Color"] = { r, g, b }
    self:Changed()
end

-- Arrows along a loop whose stops are at xs[i], ys[i] (pixels, in loop order):
-- one every `spacing` pixels of the way round, the first half a spacing in,
-- each { x, y, dx, dy } with dx, dy the way to ride (length 1). reverse rides
-- the loop the other way. Fewer than 3 stops (there and back): none.
local MAX_ARROWS = 2000
local function ArrowMarks(xs, ys, n, spacing, reverse)
    local marks = {}
    if n < 3 or not (spacing > 0) then return marks end
    local nextAt, walked = spacing / 2, 0
    for k = 1, n do
        local i = reverse and (k == 1 and 1 or n - k + 2) or k
        local j = reverse and (i == 1 and n or i - 1) or i % n + 1
        local dx, dy = xs[j] - xs[i], ys[j] - ys[i]
        local len = sqrt(dx * dx + dy * dy)
        if len > 0 then
            while nextAt <= walked + len do
                local t = (nextAt - walked) / len
                marks[#marks + 1] = { xs[i] + dx * t, ys[i] + dy * t, dx / len, dy / len }
                if #marks >= MAX_ARROWS then return marks end
                nextAt = nextAt + spacing
            end
            walked = walked + len
        end
    end
    return marks
end
GP.ArrowMarks = ArrowMarks

-- One arrow (a ">" of two lines) centred on x, y, pointing along dx, dy
local function DrawArrow(pool, rel, point, x, y, dx, dy, size, color, alpha, width)
    local tx, ty = x + dx * size / 2, y + dy * size / 2
    local bx, by = tx - dx * size, ty - dy * size
    local px, py = -dy * size * 0.6, dx * size * 0.6
    for side = -1, 1, 2 do
        local line = pool:Get()
        Paint(line, color, alpha, width)
        line:SetStartPoint(point, rel, bx + px * side, by + py * side)
        line:SetEndPoint(point, rel, tx, ty)
    end
end
GP.ARROW_GAP = { world = 80, minimap = 40 }   -- pixels on screen between arrows

-- The point of a loop (xs, ys, n stops; 2 stops: one leg) nearest to px, py:
-- x, y and how far away it is
local function NearestOnLoop(xs, ys, n, px, py)
    local bx, by, best
    local legs = n == 2 and 1 or n
    for i = 1, legs do
        local j = i % n + 1
        local ax, ay = xs[i], ys[i]
        local dx, dy = xs[j] - ax, ys[j] - ay
        local len2 = dx * dx + dy * dy
        local t = len2 > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
        local x, y = ax + dx * t, ay + dy * t
        local d = (x - px) ^ 2 + (y - py) ^ 2
        if not best or d < best then bx, by, best = x, y, d end
    end
    if best then return bx, by, sqrt(best) end
end
GP.NearestOnLoop = NearestOnLoop

-- Dashes from the middle (0, 0) toward x, y, as far as `reach` pixels at most
GP.JOIN_DASH, GP.JOIN_GAP, GP.JOIN_MIN = 6, 4, 20   -- pixels, pixels, yards (closer: no line)
local function DrawJoin(pool, rel, x, y, reach, color, alpha, width)
    local d = sqrt(x * x + y * y)
    if d <= 0 then return end
    local ux, uy = x / d, y / d
    local stop, at = min(d, reach), 0
    while at < stop do
        local to = min(at + GP.JOIN_DASH, stop)
        local line = pool:Get()
        Paint(line, color, alpha, width)
        line:SetStartPoint("CENTER", rel, ux * at, uy * at)
        line:SetEndPoint("CENTER", rel, ux * to, uy * to)
        at = to + GP.JOIN_GAP
    end
end

---------------------------------------------------------------------------
-- World map: one pin over the whole map holds the lines
---------------------------------------------------------------------------
GatherPathForeverPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}
local Pin = GatherPathForeverPinMixin

function Pin:OnLoad()
    self:SetIgnoreGlobalPinScale(true)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    self.pool = LinePool(self, "OVERLAY")
    self.arrows = LinePool(self, "OVERLAY")
    self.taboo = LinePool(self, "ARTWORK")   -- taboo areas, under the routes
    self.draft = LinePool(self, "OVERLAY")   -- the area being drawn
    self:SetScript("OnUpdate", function(pin) if GP.drawing then pin:DrawDraft() end end)
end

function Pin:OnAcquired()
    self:SetPosition(0.5, 0.5)
    self:OnCanvasSizeChanged()
end

function Pin:OnCanvasSizeChanged()
    local map = self:GetMap()
    self:SetSize(map:DenormalizeHorizontalSize(1), map:DenormalizeVerticalSize(1))
end

function Pin:OnCanvasScaleChanged()
    self:Draw()
end

-- Diagonal hatching inside a polygon (xs, ys, n corners, in pixels): lines
-- along x + y = c every `spacing` pixels, as { x1, y1, x2, y2 } pieces
local MAX_HATCH = 600
local function HatchSpans(xs, ys, n, spacing)
    local out = {}
    if n < 3 or not (spacing > 0) then return out end
    local lo, hi = math.huge, -math.huge
    for i = 1, n do
        local u = xs[i] + ys[i]
        lo, hi = min(lo, u), max(hi, u)
    end
    local c = (floor(lo / spacing) + 1) * spacing
    while c < hi do
        local cuts = {}
        for i = 1, n do
            local j = i % n + 1
            local fi, fj = xs[i] + ys[i] - c, xs[j] + ys[j] - c
            if (fi > 0) ~= (fj > 0) then
                local t = fi / (fi - fj)
                cuts[#cuts + 1] = xs[i] + (xs[j] - xs[i]) * t
            end
        end
        table.sort(cuts)
        for k = 1, #cuts - 1, 2 do
            out[#out + 1] = { cuts[k], c - cuts[k], cuts[k + 1], c - cuts[k + 1] }
            if #out >= MAX_HATCH then return out end
        end
        c = c + spacing
    end
    return out
end
GP.HatchSpans = HatchSpans

GP.TABOO_COLOR = { 0.95, 0.22, 0.15 }
GP.HATCH_GAP = 12   -- pixels on screen between hatch lines

-- The taboo areas of the map shown: a red outline, hatched inside
function Pin:DrawTaboos(mapID, w, h, scale)
    local pool = self.taboo
    pool:Begin()
    local db = GP.db
    if db and (db.tabooShow or GP.drawing) and mapID then
        local c = GP.TABOO_COLOR
        for _, xy in ipairs(GP:Taboos(mapID)) do
            local n = floor(#xy / 2)
            local xs, ys = {}, {}
            for i = 1, n do xs[i], ys[i] = xy[2 * i - 1] * w, -xy[2 * i] * h end
            for i = 1, n do
                local j = i % n + 1
                local line = pool:Get()
                Paint(line, c, 0.9, 2 / scale)
                line:SetStartPoint("TOPLEFT", self, xs[i], ys[i])
                line:SetEndPoint("TOPLEFT", self, xs[j], ys[j])
            end
            for _, sp in ipairs(HatchSpans(xs, ys, n, GP.HATCH_GAP / scale)) do
                local line = pool:Get()
                Paint(line, c, 0.4, 1 / scale)
                line:SetStartPoint("TOPLEFT", self, sp[1], sp[2])
                line:SetEndPoint("TOPLEFT", self, sp[3], sp[4])
            end
        end
    end
    pool:Done()
end

-- The area being drawn: its corners joined, and on to the cursor
function Pin:DrawDraft()
    local pool = self.draft
    if not pool then return end
    pool:Begin()
    local d = GP.drawing
    local map = self:GetMap()
    if d and map and map:GetMapID() == d.mapID then
        local w, h = self:GetWidth(), self:GetHeight()
        local scale = self:GetEffectiveScale() / max(0.01, map:GetEffectiveScale())
        local pts = d.pts
        local n = floor(#pts / 2)
        local xs, ys = {}, {}
        for i = 1, n do xs[i], ys[i] = pts[2 * i - 1] * w, -pts[2 * i] * h end
        local c, gold = GP.TABOO_COLOR, { 1, 0.82, 0 }
        local function Seg(ax, ay, bx, by, color, alpha, width)
            local line = pool:Get()
            Paint(line, color, alpha, width / scale)
            line:SetStartPoint("TOPLEFT", self, ax, ay)
            line:SetEndPoint("TOPLEFT", self, bx, by)
        end
        for i = 1, n - 1 do Seg(xs[i], ys[i], xs[i + 1], ys[i + 1], c, 1, 2) end
        -- each corner a small gold square
        for i = 1, n do
            local r = 3 / scale
            Seg(xs[i] - r, ys[i], xs[i] + r, ys[i], gold, 1, 6)
        end
        if n > 0 and map.GetNormalizedCursorPosition then
            local ok, cx, cy = pcall(map.GetNormalizedCursorPosition, map)
            if ok and cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                Seg(xs[n], ys[n], cx * w, -cy * h, c, 0.7, 1.5)
                if n >= 2 then Seg(cx * w, -cy * h, xs[1], ys[1], c, 0.35, 1) end
            end
        end
    end
    pool:Done()
end

-- Where a route's map sits on the map shown: offsets and sizes (0..1), or nil
local function Placement(routeMap, shownMap)
    if routeMap == shownMap then return 0, 0, 1, 1, true end
    if not C_Map.GetMapRectOnMap then return nil end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, routeMap, shownMap)
    if not ok or not minX or maxX <= minX or maxY <= minY then return nil end
    return minX, minY, maxX - minX, maxY - minY, false
end
GP.Placement = Placement

function Pin:Draw()
    local pool = self.pool
    if not pool then return end
    local arrows = self.arrows
    pool:Begin()
    arrows:Begin()
    local db = GP.db
    local map = self:GetMap()
    local shownMap = map and map:GetMapID()
    if map and shownMap and map:IsShown() then
        local scale = self:GetEffectiveScale() / max(0.01, map:GetEffectiveScale())
        self:DrawTaboos(shownMap, self:GetWidth(), self:GetHeight(), scale)
        self:DrawDraft()
    end
    if db and db.worldMap and shownMap and map:IsShown() then
        local w, h = self:GetWidth(), self:GetHeight()
        -- the canvas is zoomed; keep lines the same width on screen
        local scale = self:GetEffectiveScale() / max(0.01, map:GetEffectiveScale())
        local alpha = db.worldAlpha / 100
        for _, route in ipairs(db.routes) do
            local p, n = route.points, GP:NodeCount(route)
            if route.shown and not route.working and n >= 2 then
                local ox, oy, sx, sy, own = Placement(route.mapID, shownMap)
                if ox then
                    -- thinner on a bigger map, where the route is small
                    local width = (own and db.worldWidth or max(1, db.worldWidth * 0.5)) / scale
                    local color = GP:LineColor(route, "world")
                    local xs, ys = {}, {}
                    for i = 1, n do
                        xs[i], ys[i] = (ox + p[2 * i - 1] * sx) * w, -(oy + p[2 * i] * sy) * h
                    end
                    for i = 1, n do
                        local j = i % n + 1
                        if not (n == 2 and i == 2) then
                            local line = pool:Get()
                            Paint(line, color, alpha, width)
                            line:SetStartPoint("TOPLEFT", self, xs[i], ys[i])
                            line:SetEndPoint("TOPLEFT", self, xs[j], ys[j])
                        end
                    end
                    if db.arrows then
                        local size = max(8 / scale, width * 3)
                        for _, a in ipairs(ArrowMarks(xs, ys, n, GP.ARROW_GAP.world / scale, db.arrowsReverse)) do
                            DrawArrow(arrows, self, "TOPLEFT", a[1], a[2], a[3], a[4], size, color, alpha, width)
                        end
                    end
                end
            end
        end
    end
    pool:Done()
    arrows:Done()
end

local Provider = CreateFromMixins and MapCanvasDataProviderMixin and CreateFromMixins(MapCanvasDataProviderMixin) or {}

function Provider:OnAdded(map)
    MapCanvasDataProviderMixin.OnAdded(self, map)
    self.pin = map:AcquirePin("GatherPathForeverPinTemplate")
end

function Provider:OnRemoved(map)
    map:RemoveAllPinsByTemplate("GatherPathForeverPinTemplate")
    self.pin = nil
    MapCanvasDataProviderMixin.OnRemoved(self, map)
end

function Provider:RemoveAllData()
    if self.pin and self.pin.pool then
        self.pin.pool:Begin()
        self.pin.pool:Done()
        self.pin.arrows:Begin()
        self.pin.arrows:Done()
        self.pin.taboo:Begin()
        self.pin.taboo:Done()
    end
end

function Provider:RefreshAllData()
    if self.pin then self.pin:Draw() end
end

function Provider:OnMapChanged()
    self:RefreshAllData()
    if GP.drawing then GP:UpdateDrawBar() end
end

function GP:SetupWorldMap()
    if self.provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
    self.provider = Provider
    WorldMapFrame:AddDataProvider(Provider)
end

function GP:DrawWorldMap()
    if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
        self.provider:RefreshAllData()
    end
end

---------------------------------------------------------------------------
-- Drawing a taboo area on the world map: left-click adds a corner,
-- right-click takes the last one back, Finish keeps it. The map still pans
-- and zooms; clicks only become corners on the zone being drawn in.
---------------------------------------------------------------------------
local function TabooClick(map, button, cx, cy)
    local d = GP.drawing
    if not d or not map or map:GetMapID() ~= d.mapID then return false end
    if button == "LeftButton" and cx and cy then
        d.pts[#d.pts + 1] = Round(max(0, min(1, cx)))
        d.pts[#d.pts + 1] = Round(max(0, min(1, cy)))
    elseif button == "RightButton" then
        if #d.pts == 0 then return false end   -- nothing to take back: zoom out as usual
        d.pts[#d.pts] = nil
        d.pts[#d.pts] = nil
    else
        return false
    end
    GP:UpdateDrawBar()
    GP:DrawWorldMap()
    return true
end
GP.TabooClick = TabooClick

function GP:StartTaboo(mapID)
    if not mapID then return false end
    if InCombatLockdown and InCombatLockdown() then
        Print("can't open the world map to draw while you're in combat.")
        return false
    end
    if not (WorldMapFrame and WorldMapFrame.AddCanvasClickHandler) then
        Print("can't draw on this world map.")
        return false
    end
    self:SetupWorldMap()
    if not (self.drawing and self.drawing.mapID == mapID) then
        self.drawing = { mapID = mapID, pts = {} }
    end
    if not self.clickHandler then
        self.clickHandler = TabooClick
        WorldMapFrame:AddCanvasClickHandler(TabooClick, 100)
    end
    if self.config then self.config:Hide() end
    if OpenWorldMap then
        pcall(OpenWorldMap, mapID)
    else
        if not WorldMapFrame:IsShown() and ShowUIPanel then pcall(ShowUIPanel, WorldMapFrame) end
        if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    end
    self:UpdateDrawBar()
    self:DrawWorldMap()
    return true
end

local function EndDrawing(self)
    self.drawing = nil
    if self.clickHandler and WorldMapFrame and WorldMapFrame.RemoveCanvasClickHandler then
        WorldMapFrame:RemoveCanvasClickHandler(self.clickHandler, 100)
    end
    self.clickHandler = nil
    if self.drawBar then self.drawBar:Hide() end
    self:DrawWorldMap()
end

function GP:FinishTaboo()
    local d = self.drawing
    if not d then return false end
    if #d.pts < 6 then
        Print("a taboo area needs at least 3 corners. Left-click the map to add them.")
        return false
    end
    if not self:AddTaboo(d.mapID, d.pts) then return false end
    local mapID = d.mapID
    EndDrawing(self)
    local n = #self:RoutesOn(mapID)
    Print(("taboo area added in %s.%s"):format(self:MapName(mapID),
        n > 0 and " Your routes there are being worked out again to go round it." or ""))
    if self.TabooTabInWindow then self:TabooTabInWindow(mapID) end
    return true
end

function GP:CancelTaboo()
    local d = self.drawing
    if not d then return end
    EndDrawing(self)
    if self.TabooTabInWindow then self:TabooTabInWindow(d.mapID) end
end

-- The bar over the world map while drawing
function GP:UpdateDrawBar()
    local d = self.drawing
    local bar = self.drawBar
    if not d then
        if bar then bar:Hide() end
        return
    end
    if not bar then
        local parent = WorldMapFrame
        bar = CreateFrame("Frame", nil, parent)
        bar:SetSize(560, 64)
        bar:SetPoint("TOP", parent.ScrollContainer or parent, "TOP", 0, -8)
        bar:SetFrameStrata("DIALOG")
        bar:EnableMouse(true)
        T.Panel(bar, 0.92)
        bar.title = T.Text(bar, "", "GameFontNormal", T.C.gold)
        bar.title:SetPoint("TOPLEFT", 12, -10)
        bar.help = T.Text(bar, "", "GameFontHighlightSmall")
        bar.help:SetPoint("TOPLEFT", 12, -30)
        bar.help:SetWidth(400)
        bar.help:SetWordWrap(true)
        bar.finish = T.FlatButton(bar, "Finish", 110, 22)
        bar.finish:SetPoint("TOPRIGHT", -10, -8)
        bar.finish:SetScript("OnClick", function(b) if not b.disabled then GP:FinishTaboo() end end)
        T.Disabler(bar.finish, { bar.finish })
        bar.cancel = T.FlatButton(bar, "Cancel", 110, 22)
        bar.cancel:SetPoint("TOPRIGHT", -10, -34)
        bar.cancel:SetScript("OnClick", function() GP:CancelTaboo() end)
        self.drawBar = bar
    end
    local corners = floor(#d.pts / 2)
    bar.title:SetText(("Taboo area in %s  -  %d corner%s"):format(self:MapName(d.mapID), corners, corners == 1 and "" or "s"))
    local shown = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if shown ~= d.mapID then
        bar.help:SetText(("Go back to %s on the map to draw there."):format(self:MapName(d.mapID)))
    else
        bar.help:SetText("Left-click the map for each corner, right-click to take the last one back. "
            .. "Scroll to zoom, drag to move the map.")
    end
    bar.finish:SetDisabled(corners < 3)
    bar:Show()
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
-- The part of the segment a-b inside a circle of radius r round 0,0
local function ClipCircle(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local a = dx * dx + dy * dy
    if a == 0 then return nil end
    local b = 2 * (ax * dx + ay * dy)
    local c = ax * ax + ay * ay - r * r
    local disc = b * b - 4 * a * c
    if disc <= 0 then return nil end
    local s = sqrt(disc)
    local t1, t2 = (-b - s) / (2 * a), (-b + s) / (2 * a)
    if t1 >= 1 or t2 <= 0 then return nil end
    t1, t2 = max(t1, 0), min(t2, 1)
    return ax + dx * t1, ay + dy * t1, ax + dx * t2, ay + dy * t2
end
GP.ClipCircle = ClipCircle

-- The part of the segment a-b inside the square -r..r
local function ClipSquare(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local t1, t2 = 0, 1
    local function edge(p, q)
        if p == 0 then return q >= 0 end
        local t = q / p
        if p < 0 then
            if t > t2 then return false end
            if t > t1 then t1 = t end
        else
            if t < t1 then return false end
            if t < t2 then t2 = t end
        end
        return true
    end
    if edge(-dx, ax + r) and edge(dx, r - ax) and edge(-dy, ay + r) and edge(dy, r - ay) then
        return ax + dx * t1, ay + dy * t1, ax + dx * t2, ay + dy * t2
    end
    return nil
end
GP.ClipSquare = ClipSquare

local function MinimapIsRound()
    local shape = GetMinimapShape and GetMinimapShape()
    return shape == nil or shape == "ROUND"
end

function GP:SetupMinimap()
    if self.mm or not Minimap then return end
    local f = CreateFrame("Frame", nil, Minimap)
    f:SetAllPoints(Minimap)
    f:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    f.pool = LinePool(f, "ARTWORK")
    f.ring = LinePool(f, "ARTWORK")
    f.arrows = LinePool(f, "ARTWORK")
    f.join = LinePool(f, "ARTWORK")
    f.speedWait = 0
    f.wait = 0
    f:SetScript("OnUpdate", function(frame, elapsed)
        frame.wait = frame.wait - elapsed
        if frame.wait > 0 then return end
        frame.wait = 0.03
        self:DrawMinimap()
        frame.speedWait = frame.speedWait - 1
        if frame.speedWait <= 0 then
            frame.speedWait = 60   -- about every 2 seconds
            if self:SampleSpeed() and self.config and self.config:IsShown() and self.RefreshConfig then
                self:RefreshConfig()
            end
        end
    end)
    self.mm = f
end

-- The range circle: db.rangeYards round you (the middle of the minimap), so
-- you can see how far Find Herbs and Find Minerals show nodes. It doesn't
-- turn or move, so it's only redrawn when the zoom or a setting changes.
local RING_SIDES = 64
function GP:DrawRange(force, radius, half)
    local f, db = self.mm, self.db
    local pool = f.ring
    if not (db and db.range and radius and radius > 0 and half > 0) then
        if f.ringKey then pool:Begin(); pool:Done(); f.ringKey = nil end
        return
    end
    local rc = db.rangeColor
    local key = ("%.1f:%.1f:%d:%d:%.3f:%.3f:%.3f:%s"):format(radius, half, db.rangeYards, db.rangeAlpha,
        rc[1], rc[2], rc[3], tostring(MinimapIsRound()))
    if not force and key == f.ringKey then return end
    f.ringKey = key
    local r = db.rangeYards * half / radius
    local clip = MinimapIsRound() and ClipCircle or ClipSquare
    local alpha = db.rangeAlpha / 100
    pool:Begin()
    for i = 1, RING_SIDES do
        local a1, a2 = (i - 1) / RING_SIDES * 2 * math.pi, i / RING_SIDES * 2 * math.pi
        local ax, ay, bx, by = clip(r * cos(a1), r * sin(a1), r * cos(a2), r * sin(a2), half - 1)
        if ax then
            local line = pool:Get()
            Paint(line, rc, alpha, 2)
            line:SetStartPoint("CENTER", f, ax, ay)
            line:SetEndPoint("CENTER", f, bx, by)
        end
    end
    pool:Done()
end

-- Redraws the minimap's lines if you've moved, turned or zoomed (or force)
function GP:DrawMinimap(force)
    local f = self.mm
    if not f then return end
    local pool = f.pool
    local db = self.db
    local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    local half = Minimap:GetWidth() / 2
    self:DrawRange(force, radius, half)
    if not (db and db.minimap) then
        if f.drew then
            pool:Begin(); pool:Done()
            f.arrows:Begin(); f.arrows:Done()
            f.join:Begin(); f.join:Done()
            f.drew = false; f.last = nil
        end
        return
    end
    if not radius or radius <= 0 or half <= 0 then return end
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    if rotate and not facing then facing = 0 end

    -- your place on each map that has a route showing
    local mc = db.minimapColor
    local maps, key = {}, ("%.1f:%.3f:%.1f:%d:%d:%s:%.3f:%.3f:%.3f:%s:%s"):format(radius, facing, half, db.minimapWidth,
        db.minimapAlpha, tostring(db.minimapRouteColor), mc[1], mc[2], mc[3], tostring(db.arrows), tostring(db.arrowsReverse)) .. ":" .. tostring(db.joinLine)
    for _, route in ipairs(db.routes) do
        if route.shown and not route.working and maps[route.mapID] == nil then
            local x, y = PlayerPos(route.mapID)
            maps[route.mapID] = x and { x, y } or false
            if x then key = key .. (":%d:%.5f:%.5f"):format(route.mapID, x, y) end
        end
    end
    if not force and key == f.last then return end
    f.last = key

    local pxPerYard = half / radius
    local inside = half - 1
    local clip = MinimapIsRound() and ClipCircle or ClipSquare
    local c, s = cos(facing), sin(facing)
    local alpha = db.minimapAlpha / 100
    local round = MinimapIsRound()
    local size = max(7, db.minimapWidth * 3)
    local arrows = f.arrows
    local join   -- the nearest point of any route: { x, y, distance, color }
    pool:Begin()
    arrows:Begin()
    for _, route in ipairs(db.routes) do
        local at = maps[route.mapID]
        local n = self:NodeCount(route)
        if at and route.shown and not route.working and n >= 2 then
            local w, h = Yards(route.mapID)
            local p = route.points
            local color = self:LineColor(route, "minimap")
            -- every node, in pixels from the minimap's middle (right and up)
            local sx, sy = {}, {}
            for i = 1, n do
                local dx = (p[2 * i - 1] - at[1]) * w * pxPerYard   -- east
                local dy = (p[2 * i] - at[2]) * h * pxPerYard       -- south
                if rotate then dx, dy = dx * c - dy * s, dx * s + dy * c end
                sx[i], sy[i] = dx, -dy
            end
            for i = 1, n do
                local j = i % n + 1
                if not (n == 2 and i == 2) then
                    local ax, ay, bx, by = clip(sx[i], sy[i], sx[j], sy[j], inside)
                    if ax then
                        local line = pool:Get()
                        Paint(line, color, alpha, db.minimapWidth)
                        line:SetStartPoint("CENTER", f, ax, ay)
                        line:SetEndPoint("CENTER", f, bx, by)
                    end
                end
            end
            if db.joinLine then
                local x, y, d = NearestOnLoop(sx, sy, n, 0, 0)
                if x and (not join or d < join[3]) then join = { x, y, d, color } end
            end
            if db.arrows then
                -- only arrows wholly on the minimap
                local room = inside - size
                for _, a in ipairs(ArrowMarks(sx, sy, n, self.ARROW_GAP.minimap, db.arrowsReverse)) do
                    local x, y = a[1], a[2]
                    if (round and x * x + y * y <= room * room) or (not round and math.abs(x) <= room and math.abs(y) <= room) then
                        DrawArrow(arrows, f, "CENTER", x, y, a[3], a[4], size, color, alpha, db.minimapWidth)
                    end
                end
            end
        end
    end
    pool:Done()
    arrows:Done()
    f.join:Begin()
    -- off the route: dashes from you toward it, up to the minimap's edge
    if join and join[3] > self.JOIN_MIN * pxPerYard then
        local reach = inside
        if not round then
            -- to the square's edge in that direction
            local ax, ay = math.abs(join[1]) / join[3], math.abs(join[2]) / join[3]
            reach = inside / max(ax, ay, 0.001)
        end
        DrawJoin(f.join, f, join[1], join[2], reach, join[4], alpha, max(1, db.minimapWidth - 1))
    end
    f.join:Done()
    f.drew = true
end

---------------------------------------------------------------------------
-- Redraw everything after a change
---------------------------------------------------------------------------
function GP:Changed()
    self:DrawWorldMap()
    self:DrawMinimap(true)
    if self.RefreshConfig then self:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
function GP:PositionMinimapButton()
    local angle = math.rad(self.db.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", cos(angle) * radius, sin(angle) * radius)
end

function GP:BuildMinimapButton()
    local b = CreateFrame("Button", "GatherPathForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(22, 22)
    icon:SetTexture(self.ICON)
    icon:SetPoint("TOPLEFT", 5, -4)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GP:ToggleLines()
        else
            GP:OpenConfig()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            GP.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            GP:PositionMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(GP.LOGO_TEXT .. " " .. T.NAME)
        GameTooltip:AddLine("Left-click: routes and options", 1, 1, 1)
        GameTooltip:AddLine("Right-click: show or hide the lines", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.minimapButton = b
    self:PositionMinimapButton()
end

function GP:UpdateMinimapButton()
    if self.minimapButton then self.minimapButton:SetShown(self.db.minimapButton) end
end

-- Right-click on the button: all lines off, or back as they were
function GP:ToggleLines()
    local db = self.db
    if db.worldMap or db.minimap then
        db.hiddenWas = { worldMap = db.worldMap, minimap = db.minimap }
        db.worldMap, db.minimap = false, false
        Print("lines hidden. Right-click the button again to show them.")
    else
        local was = db.hiddenWas or {}
        db.worldMap = was.worldMap ~= false
        db.minimap = was.minimap ~= false
        db.hiddenWas = nil
        Print("lines shown.")
    end
    self:Changed()
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
local function Help()
    Print("commands:")
    print("  |cffffd100/gpf|r  routes and options")
    print("  |cffffd100/gpf new|r  make a new route")
    print("  |cffffd100/gpf show|r, |cffffd100/gpf hide|r  show or hide all the lines")
    print("  |cffffd100/gpf skipped|r  the nodes on your skip list")
end

SLASH_GATHERPATHFOREVER1 = "/gpf"
SLASH_GATHERPATHFOREVER2 = "/gatherpath"
SlashCmdList.GATHERPATHFOREVER = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "options" or cmd == "config" then
        GP:OpenConfig()
    elseif cmd == "new" then
        GP:OpenConfig("new")
    elseif cmd == "skipped" or cmd == "skip" then
        local list = GP:SkippedNames()
        if #list == 0 then
            Print("no nodes are skipped. Right-click a node on the New route tab to skip it in every route.")
        else
            Print("skipped (right-click one on the New route tab to stop skipping it): " .. table.concat(list, ", "))
        end
    elseif cmd == "show" or cmd == "hide" then
        local on = cmd == "show"
        if (GP.db.worldMap or GP.db.minimap) ~= on then GP:ToggleLines() end
    else
        Help()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(events.RegisterEvent, events, "ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            GP:LoadSettings()
        elseif arg1 == "GatherMate2" then
            GP:ListenToGatherMate()
        elseif arg1 == "Blizzard_WorldMap" then
            GP:SetupWorldMap()
        end
    elseif event == "PLAYER_LOGIN" then
        GP:SetupWorldMap()
        GP:SetupMinimap()
        GP:BuildMinimapButton()
        GP:UpdateMinimapButton()
        GP:ListenToGatherMate()
        if not GP:HasGatherMate() then
            Print("needs |cffffd100GatherMate2|r for its herb and ore nodes. Install it from CurseForge, then /reload.")
        end
    else
        GP:DrawMinimap(true)
        if GP.RefreshConfig then GP:RefreshConfig() end
    end
end)
