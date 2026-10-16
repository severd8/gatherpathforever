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
    autoAdd = true,        -- nodes GatherMate2 finds later join the routes they belong to
    minimapButton = true,
    minimapAngle = 200,
    sight = 100,           -- where New route's "route passes within" starts (yards, 0 = go to every node)
    nextColor = 1,
}
GP.RANGES = {
    worldWidth = { 1, 10 },
    minimapWidth = { 1, 8 },
    worldAlpha = { 10, 100 },
    minimapAlpha = { 10, 100 },
    rangeYards = { 20, 200 },
    rangeAlpha = { 10, 100 },
    sight = { 0, 150 },
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

-- What GatherMate2 knows on a map: { { kind =, name =, count = }, ... }, by kind then name
function GP:ZoneNodes(mapID)
    local list = {}
    for _, kind in ipairs(self:Kinds()) do
        local counts = {}
        self:EachNode(mapID, kind, function(_, _, name) counts[name] = (counts[name] or 0) + 1 end)
        local names = {}
        for name in pairs(counts) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            list[#list + 1] = { kind = kind, name = name, count = counts[name] }
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

-- The nodes a route is made from, as { x, y } map positions
function GP:CollectNodes(mapID, kinds)
    local pts = {}
    for kind, names in pairs(kinds) do
        self:EachNode(mapID, kind, function(x, y, name)
            if names[name] then pts[#pts + 1] = { x, y } end
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
    for _, n in ipairs(all) do perKind[n.kind] = (perKind[n.kind] or 0) + 1 end
    for _, kind in ipairs(self:Kinds()) do
        local picked = kinds[kind]
        if picked and next(picked) then
            local list = {}
            for name in pairs(picked) do list[#list + 1] = name end
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

-- Reads the route's nodes from GatherMate2 and finds the shortest loop.
-- Runs inside a job (it pauses now and then). Returns how many nodes it read.
local function Build(route)
    local raw = GP:CollectNodes(route.mapID, route.kinds)
    local w, h = Yards(route.mapID)
    local pts = {}
    for i, p in ipairs(raw) do pts[i] = { p[1] * w, p[2] * h } end
    local stops = O.Shortcut(pts, route.sight or 0)
    local flat = {}
    for _, p in ipairs(stops) do
        flat[#flat + 1] = Round(p[1] / w)
        flat[#flat + 1] = Round(p[2] / h)
    end
    route.points = flat
    route.nodes = #raw
    route.length = GP:RouteLength(route)
    return #raw
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
                Print("|cffff5050couldn't work out the route:|r " .. tostring(a))
                if self.Changed then self:Changed() end
                return
            end
            if coroutine.status(co) == "dead" then
                driver:SetScript("OnUpdate", nil)
                self.job = nil
                O.Pause = function() end
                done(a, b)
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

-- opts: mapID, kinds = { [kind] = { [name] = true } }, name, sight
function GP:NewRoute(opts)
    if not self:HasGatherMate() then
        Print("needs GatherMate2, where the nodes come from.")
        return nil
    end
    local any = false
    for _, names in pairs(opts.kinds or {}) do if next(names) then any = true end end
    if not any then
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
        Print(("made |cffffd100%s|r in %s: %d nodes, %s round."):format(route.name, self:MapName(route.mapID),
            self:RouteNodes(route), self.FormatYards(route.length)))
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
            Print(("%s: %d nodes (%s), %s round."):format(route.name, after,
                after == before and "no change" or ((after > before and "+" or "") .. (after - before)),
                self.FormatYards(route.length)))
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
    local any = false
    for _, names in pairs(opts.kinds or {}) do if next(names) then any = true end end
    if not any then
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
            Print(("changed |cffffd100%s|r in %s: %d nodes, %s round."):format(route.name, self:MapName(route.mapID),
                self:RouteNodes(route), self.FormatYards(route.length)))
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
    if not self.db.autoAdd then return 0 end
    local w, h = Yards(mapID)
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
                local at = O.BestInsert(pts, tour, c)
                local spot = c
                if sight > 0 and n > 1 then
                    spot = O.Place(pts[at], pts[at % n + 1], c, sight)
                end
                table.insert(p, 2 * at + 1, Round(spot[1] / w))
                table.insert(p, 2 * at + 2, Round(spot[2] / h))
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

---------------------------------------------------------------------------
-- World map: one pin over the whole map holds the lines
---------------------------------------------------------------------------
GatherPathForeverPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}
local Pin = GatherPathForeverPinMixin

function Pin:OnLoad()
    self:SetIgnoreGlobalPinScale(true)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    self.pool = LinePool(self, "OVERLAY")
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
    pool:Begin()
    local db = GP.db
    local map = self:GetMap()
    local shownMap = map and map:GetMapID()
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
                    for i = 1, n do
                        local j = i % n + 1
                        if not (n == 2 and i == 2) then
                            local line = pool:Get()
                            Paint(line, color, alpha, width)
                            line:SetStartPoint("TOPLEFT", self, (ox + p[2 * i - 1] * sx) * w, -(oy + p[2 * i] * sy) * h)
                            line:SetEndPoint("TOPLEFT", self, (ox + p[2 * j - 1] * sx) * w, -(oy + p[2 * j] * sy) * h)
                        end
                    end
                end
            end
        end
    end
    pool:Done()
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
    end
end

function Provider:RefreshAllData()
    if self.pin then self.pin:Draw() end
end

function Provider:OnMapChanged()
    self:RefreshAllData()
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
    f.wait = 0
    f:SetScript("OnUpdate", function(frame, elapsed)
        frame.wait = frame.wait - elapsed
        if frame.wait > 0 then return end
        frame.wait = 0.03
        self:DrawMinimap()
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
        if f.drew then pool:Begin(); pool:Done(); f.drew = false; f.last = nil end
        return
    end
    if not radius or radius <= 0 or half <= 0 then return end
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    if rotate and not facing then facing = 0 end

    -- your place on each map that has a route showing
    local mc = db.minimapColor
    local maps, key = {}, ("%.1f:%.3f:%.1f:%d:%d:%s:%.3f:%.3f:%.3f"):format(radius, facing, half, db.minimapWidth,
        db.minimapAlpha, tostring(db.minimapRouteColor), mc[1], mc[2], mc[3])
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
    pool:Begin()
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
        end
    end
    pool:Done()
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
end

SLASH_GATHERPATHFOREVER1 = "/gpf"
SLASH_GATHERPATHFOREVER2 = "/gatherpath"
SlashCmdList.GATHERPATHFOREVER = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "options" or cmd == "config" then
        GP:OpenConfig()
    elseif cmd == "new" then
        GP:OpenConfig("new")
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
