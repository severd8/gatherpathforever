-- GatherPath Forever tests. Run from the repo root: lua5.1 tests/run.lua

local function STEP(name) LOG[#LOG + 1] = "STEP " .. name end
local function check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function logHas(text)
    for i = #LOG, 1, -1 do if LOG[i]:find(text, 1, true) then return true end end
    return false
end

---------------------------------------------------------------------------
STEP("route solver")
local O = loadfile("Optimize.lua")("GatherPathForever", {})
math.randomseed(7)
local function perms(a, n, f)
    if n == 0 then f(a) return end
    for i = 1, n do a[n], a[i] = a[i], a[n]; perms(a, n - 1, f); a[n], a[i] = a[i], a[n] end
end
local function isTour(t, n)
    if #t ~= n then return false end
    local seen = {}
    for _, v in ipairs(t) do if seen[v] or v < 1 or v > n then return false end seen[v] = true end
    return true
end
for _ = 1, 25 do
    local pts = {}
    for i = 1, 8 do pts[i] = { math.random() * 1000, math.random() * 700 } end
    local tour = O.Solve(pts)
    check(isTour(tour, 8), "the tour visits every node once")
    local best = math.huge
    local rest = { 2, 3, 4, 5, 6, 7, 8 }
    perms(rest, 7, function(p)
        local t = { 1 }
        for i = 1, 7 do t[i + 1] = p[i] end
        best = math.min(best, O.Length(pts, t))
    end)
    check(O.Length(pts, tour) <= best * 1.02, "8 nodes: within 2% of the shortest loop")
end
do
    -- a ring of nodes, shuffled: the answer is the ring
    local pts = {}
    for i = 1, 40 do
        local a = (i / 40) * 2 * math.pi
        pts[i] = { 500 + 300 * math.cos(a), 500 + 300 * math.sin(a) }
    end
    for i = #pts, 2, -1 do local j = math.random(i); pts[i], pts[j] = pts[j], pts[i] end
    local tour = O.Solve(pts)
    check(isTour(tour, 40))
    local ring = 40 * 2 * 300 * math.sin(math.pi / 40)
    check(near(O.Length(pts, tour), ring, 0.01), "a shuffled ring comes back as the ring")
    -- bigger sets still come back whole
    local big = {}
    for i = 1, 250 do big[i] = { math.random() * 2000, math.random() * 1500 } end
    check(isTour(O.Solve(big), 250), "250 nodes")
    check(#O.Solve({}) == 0 and #O.Solve({ { 1, 1 } }) == 1, "0 and 1 nodes")
end
do
    local merged = O.Merge({ { 0, 0 }, { 10, 0 }, { 20, 0 }, { 200, 0 } }, 12)
    check(#merged == 2, "nodes in a chain 10 yards apart merge into one")
    check(near(merged[1][1], 10) and merged[1].count == 3, "in the middle of them")
    check(#O.Merge({ { 0, 0 }, { 10, 0 } }, 0) == 2, "merge off keeps every node")
    local pts = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } }
    local at, cost = O.BestInsert(pts, { 1, 2, 3, 4 }, { 50, -10 })
    check(at == 1 and cost > 0 and cost < 5, "a new node goes in the leg it's beside")
end
do
    -- passing within a distance of each node
    local function covered(nodes, stops, r)
        for _, c in ipairs(nodes) do
            local best = math.huge
            for i = 1, #stops do
                best = math.min(best, O.SegDist(stops[i], stops[i % #stops + 1], c))
            end
            if best > r + 0.5 then return false end
        end
        return true
    end
    local function loopLength(stops)
        local t = {}
        for i = 1, #stops do t[i] = i end
        return O.Length(stops, t)
    end
    local p = O.Place({ 0, 0 }, { 100, 0 }, { 50, 30 }, 40)
    check(near(p[1], 50) and near(p[2], 0), "a line that passes close enough is walked straight")
    p = O.Place({ 0, 0 }, { 100, 0 }, { 50, 100 }, 40)
    check(near(p[1], 50, 0.01) and near(p[2], 60, 0.01), "else the closest spot on the circle")
    check(near(O.SegDist({ 0, 0 }, { 10, 0 }, { 20, 0 }), 10) and near(O.SegDist({ 0, 0 }, { 10, 0 }, { 5, 3 }), 3))
    -- a square of nodes 200 apart, 40 yards: each corner cut
    local sq = { { 0, 0 }, { 200, 0 }, { 200, 200 }, { 0, 200 } }
    local stops = O.Shortcut(sq, 40)
    check(#stops == 4 and covered(sq, stops, 40), "every node still within reach")
    check(near(loopLength(stops), 4 * (200 - 80 / math.sqrt(2)), 1), "each corner cut 40 yards in")
    check(near(loopLength(O.Shortcut(sq, 0)), 800, 0.01), "off: right up to every node")
    -- a zigzag along a line: one straight run instead
    local zig = {}
    for i = 0, 10 do zig[#zig + 1] = { i * 50, (i % 2 == 0) and 0 or 60 } end
    stops = O.Shortcut(zig, 40)
    check(covered(zig, stops, 40), "zigzag covered")
    check(#stops < #zig, "stops on a straight line are dropped")
    check(loopLength(stops) < O.Length(zig, O.Solve(zig)) * 0.9, "and it's shorter")
    -- random fields: always covered, never longer
    for _ = 1, 15 do
        local f = {}
        for i = 1, 60 do f[i] = { math.random() * 1200, math.random() * 900 } end
        local full = O.Length(f, O.Solve(f))
        for _, r in ipairs({ 20, 50, 120 }) do
            local s2 = O.Shortcut(f, r)
            check(#s2 >= 2 and covered(f, s2, r), "random nodes covered at " .. r)
            check(loopLength(s2) <= full + 0.01, "never longer than going to every node")
        end
    end
    check(#O.Shortcut({ { 0, 0 }, { 10, 0 } }, 50) == 2, "two nodes stay two stops")
end

---------------------------------------------------------------------------
STEP("load with GatherMate2")
local E, W = 1429, 1436
local gm = FakeGatherMate({
    -- Peacebloom round a square in Elwynn
    { E, "Herb Gathering", 1, 0.40, 0.40 }, { E, "Herb Gathering", 1, 0.60, 0.40 },
    { E, "Herb Gathering", 1, 0.60, 0.60 }, { E, "Herb Gathering", 1, 0.40, 0.60 },
    { E, "Herb Gathering", 1, 0.50, 0.40 },
    { E, "Herb Gathering", 2, 0.45, 0.50 }, { E, "Herb Gathering", 2, 0.55, 0.50 },
    { E, "Mining", 10, 0.30, 0.30 }, { E, "Mining", 10, 0.70, 0.70 }, { E, "Mining", 10, 0.30, 0.70 },
    { W, "Mining", 11, 0.5, 0.5 },
})
local ns = LoadAddon(".")
local GP = ns.GP
FireEvent("ADDON_LOADED", "GatherPathForever")
FireEvent("PLAYER_LOGIN")
check(GP.db and GP.db.worldMap and GP.db.minimap, "defaults are in")
check(GP:HasGatherMate(), "GatherMate2 found")
check(not logHas("needs |cffffd100GatherMate2"), "no warning with GatherMate2 there")
check(GP.provider and #WorldMapFrame.__providers == 1, "the world map has our lines")
check(GP.mm and GP.minimapButton, "minimap lines and button")

STEP("what GatherMate2 knows")
local nodes = GP:ZoneNodes(E)
check(#nodes == 3, "Elwynn: Peacebloom, Silverleaf, Copper Vein")
check(nodes[1].name == "Peacebloom" and nodes[1].count == 5 and nodes[1].kind == "Herb Gathering", "herbs first, by name")
check(nodes[2].name == "Silverleaf" and nodes[2].count == 2)
check(nodes[3].name == "Copper Vein" and nodes[3].kind == "Mining" and nodes[3].count == 3)
local zones = GP:GatherZones()
check(#zones == 2 and zones[1] == E and zones[2] == W, "zones with nodes, by name")
check(GP:RouteName(E, { ["Herb Gathering"] = { Peacebloom = true } }) == "Peacebloom")
check(GP:RouteName(E, { ["Herb Gathering"] = { Peacebloom = true, Silverleaf = true } }) == "Peacebloom and Silverleaf")
check(GP:RouteName(E, { ["Herb Gathering"] = { Peacebloom = true, Silverleaf = true }, Mining = { ["Copper Vein"] = true } })
    == "Peacebloom, Silverleaf and 1 more")

---------------------------------------------------------------------------
STEP("make a route from the window")
local function RunJobs()
    for _ = 1, 10000 do
        if not GP:Busy() then return end
        Tick(0.016)
    end
    error("the job never finished")
end
GP:OpenConfig("new")
check(GP.config:IsShown() and GP.config.currentTab == "new")
local ui = GP.ui
check(ui.makeButton.disabled, "Make route waits for a pick")
local function SwitchFor(name)
    for _, sw in ipairs(ui.kindSwitches) do
        if sw.entry and sw.entry.name == name and sw:IsShown() then return sw end
    end
end
check(SwitchFor("Peacebloom") and SwitchFor("Copper Vein") and SwitchFor("Silverleaf"), "a switch per kind of node")
check(SwitchFor("Peacebloom").label:GetText():find("(5)", 1, true), "with how many there are")
Click(SwitchFor("Peacebloom"))
Click(SwitchFor("Silverleaf"))
check(SwitchFor("Peacebloom"):IsOn() and not ui.makeButton.disabled)
check(GP.db.sight == 100 and ui.sightSlider, "new routes pass within 100 yards unless you change it")
GP.db.sight = 0   -- this route goes right up to every node
Click(ui.makeButton)
check(GP:Busy(), "working it out over a few frames")
check(GP.config.currentTab == "routes", "then shows the routes")
RunJobs()
local route = GP.db.routes[1]
check(#GP.db.routes == 1 and route.name == "Peacebloom and Silverleaf", "named from what was picked")
check(GP:NodeCount(route) == 7, "7 nodes")
check(logHas("made |cffffd100Peacebloom and Silverleaf|r in Elwynn Forest: 7 nodes"), "says so in chat")
check(route.shown and route.color and route.mapID == E)
-- the length is the loop's, in yards
local pts, tour = {}, {}
for i = 1, 7 do pts[i] = { route.points[2 * i - 1] * 1600, route.points[2 * i] * 1066 }; tour[i] = i end
check(near(route.length, O.Length(pts, tour), 0.01), "length in yards")
check(ui.routeRows[1]:IsShown() and ui.routeRows[1].route == route, "listed")
check(ui.routeRows[1].info:GetText():find("7 nodes", 1, true))
check(ui.routeRows[1].name:GetText() == route.name)

STEP("a second route takes the next color")
GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } })
RunJobs()
local ore = GP.db.routes[2]
check(ore.name == "Copper Vein" and GP:NodeCount(ore) == 3)
check(ore.color[1] ~= route.color[1] or ore.color[3] ~= route.color[3], "a different color")
check(not GP:NewRoute({ mapID = E, kinds = {} }) and logHas("pick at least one"), "nothing picked: no route")
GP:NewRoute({ mapID = E, kinds = { Mining = { ["Tin Vein"] = true } } })
RunJobs()
check(#GP.db.routes == 2 and logHas("no node of those kinds"), "no nodes there: no route")

STEP("one name per route in a zone")
check(GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } }) == nil and #GP.db.routes == 2
    and logHas("already a route called |cffffd100Copper Vein|r in Elwynn Forest"), "the same made-up name: no copy")
check(GP:NewRoute({ mapID = E, kinds = { Mining = { ["Tin Vein"] = true } }, name = "  copper VEIN " }) == nil
    and #GP.db.routes == 2, "a typed name, any case: no copy")
GP:OpenConfig("new")
ui.newZone.setter(E)
Click(SwitchFor("Copper Vein"))
ui.newName:SetText("Copper Vein")
Click(ui.makeButton)
check(#GP.db.routes == 2 and not GP:Busy() and GP.config.currentTab == "new"
    and ui.newName:GetText() == "Copper Vein", "from the window: stays on New route with the name kept")
Click(SwitchFor("Copper Vein"))
ui.newName:SetText("")
local away = GP:NewRoute({ mapID = W, kinds = { Mining = { ["Copper Vein"] = true } } })
check(away and away.name == "Copper Vein", "the same name in another zone is fine")
RunJobs()

---------------------------------------------------------------------------
STEP("world map lines")
local pin = GP.provider.pin
WorldMapFrame:Show()
GP:DrawWorldMap()
local function Shown(pool)
    local list = {}
    for _, l in ipairs(pool.lines) do if l.__shown then list[#list + 1] = l end end
    return list
end
local lines = Shown(pin.pool)
check(#lines == 7 + 3, "one line per leg of each loop")
-- every line is between two of the route's nodes, on the 1000 x 667 canvas
local first = lines[1]
check(near(first.__from[1], route.points[1] * 1000, 0.01) and near(first.__from[2], -route.points[2] * 667, 0.01))
check(near(first.__to[1], route.points[3] * 1000, 0.01))
check(near(first.__color[4], 0.85) and first.__color[1] == route.color[1], "the route's color, at the opacity")
check(first.__thickness == 4)
GP:SetRouteShown(ore, false)
check(#Shown(pin.pool) == 7, "a hidden route isn't drawn")
WorldMapFrame:SetMapID(W)
check(#Shown(pin.pool) == 0, "not on another zone's map")
WorldMapFrame:SetMapID(1415)
lines = Shown(pin.pool)
check(#lines == 7, "on the continent's map")
check(near(lines[1].__from[1], (0.40 + route.points[1] * 0.08) * 1000, 0.01), "placed where Elwynn is on it")
check(lines[1].__thickness == 2, "thinner there")
GP:SetRouteShown(ore, true)
WorldMapFrame:SetMapID(E)
GP.db.worldMap = false
GP:Changed()
check(#Shown(pin.pool) == 0, "world map lines off")
GP.db.worldMap = true
GP:Changed()

---------------------------------------------------------------------------
STEP("minimap lines")
-- the minimap is 140 wide (70 round), showing 150 yards round you
PLAYER.x, PLAYER.y = 0.5, 0.5
GP.db.routes[2].shown = false
GP:DrawMinimap(true)
local mm = Shown(GP.mm.pool)
check(#mm > 0, "lines near you")
local function inside(x, y) return math.sqrt(x * x + y * y) <= 69.01 end
for _, l in ipairs(mm) do
    check(inside(l.__from[1], l.__from[2]) and inside(l.__to[1], l.__to[2]), "kept inside the round minimap")
end
check(mm[1].__thickness == 3)
-- straight east of you, 100 yards: 100 * 70/150 pixels to the right
route.points = { 0.5 + 100 / 1600, 0.5, 0.5 + 100 / 1600, 0.5 + 50 / 1066 }
route.length = GP:RouteLength(route)
GP:DrawMinimap(true)
mm = Shown(GP.mm.pool)
check(#mm == 1, "two nodes: one line")
check(near(mm[1].__from[1], 100 * 70 / 150, 0.01) and near(mm[1].__from[2], 0, 0.01), "east is right")
check(near(mm[1].__to[2], -50 * 70 / 150, 0.01), "south is down")
-- turning: the minimap turns with you, so facing west puts the east node below you
CVARS.rotateMinimap = "1"
FACING = math.pi / 2
GP:DrawMinimap(true)
mm = Shown(GP.mm.pool)
check(near(mm[1].__from[1], 0, 0.01) and near(mm[1].__from[2], -100 * 70 / 150, 0.01), "facing west: east is behind you")
FACING = math.pi
GP:DrawMinimap(true)
mm = Shown(GP.mm.pool)
check(near(mm[1].__from[1], -100 * 70 / 150, 0.01), "facing south: east is on your left")
CVARS.rotateMinimap, FACING = "0", 0
-- far away: nothing
route.points = { 0.9, 0.9, 0.95, 0.9 }
GP:DrawMinimap(true)
check(#Shown(GP.mm.pool) == 0, "a route out of sight draws nothing")
-- a line crossing the minimap is cut at the edge
check(GP.ClipCircle(-100, 0, 100, 0, 50) == -50, "cut at the circle")
local ax, ay, bx, by = GP.ClipSquare(-100, 10, 100, 10, 50)
check(ax == -50 and bx == 50 and ay == 10, "and at a square minimap's edge")
check(GP.ClipCircle(-100, 60, 100, 60, 50) == nil, "a line passing by isn't drawn")
-- you in another zone
PLAYER.map = W
GP:DrawMinimap(true)
check(#Shown(GP.mm.pool) == 0, "not while you're in another zone")
PLAYER.map = E
GP.db.routes[2].shown = true
GP:RebuildRoute(route)
RunJobs()
check(GP:NodeCount(route) == 7 and logHas("Peacebloom and Silverleaf: 7 nodes"), "Rebuild reads the nodes again")

---------------------------------------------------------------------------
STEP("nodes GatherMate2 finds later")
gm:Add(E, "Herb Gathering", 1, 0.62, 0.50)
check(GP:NodeCount(route) == 8, "a new Peacebloom joins the route")
local found = false
for i = 1, 8 do
    if near(route.points[2 * i - 1], 0.62) and near(route.points[2 * i], 0.5) then found = true end
end
check(found)
check(near(route.length, GP:RouteLength(route)), "length kept up to date")
gm:Add(E, "Herb Gathering", 3, 0.62, 0.55)
check(GP:NodeCount(route) == 8, "Earthroot isn't in that route")
gm:Add(E, "Herb Gathering", 1, 0.6201, 0.5001)
check(GP:NodeCount(route) == 8, "one on top of a node already there isn't added twice")
gm:Add(W, "Herb Gathering", 1, 0.3, 0.3)
check(GP:NodeCount(route) == 8, "nor one in another zone")
gm:Delete(E, "Herb Gathering", 0.62, 0.50)
check(GP:NodeCount(route) == 7, "a node deleted in GatherMate2 leaves")
GP.db.autoAdd = false
gm:Add(E, "Herb Gathering", 1, 0.66, 0.66)
check(GP:NodeCount(route) == 7, "Add new nodes off")
GP.db.autoAdd = true

---------------------------------------------------------------------------
STEP("a route that passes near its nodes")
GP:NewRoute({ mapID = E, kinds = { ["Herb Gathering"] = { Peacebloom = true } }, name = "Every" })
RunJobs()
local every = GP.db.routes[#GP.db.routes]
GP:NewRoute({ mapID = E, kinds = { ["Herb Gathering"] = { Peacebloom = true } }, name = "Near", sight = 50 })
RunJobs()
local nearRoute = GP.db.routes[#GP.db.routes]
check(nearRoute.sight == 50 and nearRoute.nodes == 7, "7 nodes")
check(nearRoute.length < every.length - 100, "shorter than going to every node")
check(logHas("made |cffffd100Near|r in Elwynn Forest: 7 nodes"), "counts nodes, not stops")
GP:DeleteRoute(every)
GP:OpenConfig("routes")
local nearRow
for _, r in ipairs(ui.routeRows) do if r.route == nearRoute then nearRow = r end end
check(nearRow and nearRow.info:GetText():find("7 nodes", 1, true)
    and nearRow.info:GetText():find("passes within 50 yards", 1, true), "listed with its distance")
local stopsBefore = GP:NodeCount(nearRoute)
gm:Add(E, "Herb Gathering", 1, 0.5, 0.43)
check(GP:NodeCount(nearRoute) == stopsBefore, "a new node the route already passes near isn't added")
gm:Add(E, "Herb Gathering", 1, 0.5, 0.9)
check(GP:NodeCount(nearRoute) == stopsBefore + 1 and nearRoute.nodes == 8, "a far one is")
local w, h = 1600, 1066
local added
for i = 1, GP:NodeCount(nearRoute) do
    local dx, dy = (nearRoute.points[2 * i - 1] - 0.5) * w, (nearRoute.points[2 * i] - 0.9) * h
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= 50.5 and d > 1 then added = true end
end
check(added, "a stop within 50 yards of it, not on it")
gm:Delete(E, "Herb Gathering", 0.5, 0.9)
check(GP:NodeCount(nearRoute) == stopsBefore + 1, "deleting leaves it for Rebuild")
GP:DeleteRoute(nearRoute)
gm:Delete(E, "Herb Gathering", 0.5, 0.43)
check(GP:NodeCount(route) == 7, "the route to every node is back as it was")

---------------------------------------------------------------------------
STEP("rename, hide, delete")
GP:OpenConfig("routes")
local row = ui.routeRows[1]
row.name:SetFocus()
row.name:SetText("  Elwynn herbs ")
row.name:ClearFocus()
check(route.name == "Elwynn herbs", "renamed (spaces trimmed)")
row.name:SetFocus()
row.name:SetText("   ")
row.name:ClearFocus()
check(route.name == "Elwynn herbs" and row.name:GetText() == "Elwynn herbs", "a blank name is ignored")
row.name:SetFocus()
row.name:SetText("copper vein")
row.name:ClearFocus()
check(route.name == "Elwynn herbs" and row.name:GetText() == "Elwynn herbs"
    and logHas("already a route called |cffffd100copper vein|r"), "not to another route's name")
check(GP:RenameRoute(route, "ELWYNN HERBS") and route.name == "ELWYNN HERBS", "its own name in new case is fine")
GP:RenameRoute(route, "Elwynn herbs")
Click(row.show)
check(route.shown == false and not row.show:IsOn(), "hidden")
Click(row.show)
check(route.shown)
Click(ui.routeRows[2].delete)
check(GP.confirmWindow:IsShown() and #GP.db.routes == 2, "asks first")
Click(GP.confirmWindow.yes)
check(#GP.db.routes == 1 and GP.db.routes[1] == route, "deleted")
check(not ui.routeRows[2]:IsShown(), "and gone from the list")

STEP("hide every line from the minimap button")
Click(GP.minimapButton, "RightButton")
check(not GP.db.worldMap and not GP.db.minimap, "all off")
Click(GP.minimapButton, "RightButton")
check(GP.db.worldMap and GP.db.minimap, "back on")
GP.db.minimap = false
SlashCmdList.GATHERPATHFOREVER("hide")
check(not GP.db.worldMap and not GP.db.minimap)
SlashCmdList.GATHERPATHFOREVER("show")
check(GP.db.worldMap and GP.db.minimap == false, "back as they were")
GP.db.minimap = true

STEP("display tab")
GP:OpenConfig("display")
Click(ui.minimapSwitch)
check(GP.db.minimap == false)
Click(ui.minimapSwitch)
check(GP.db.minimap == true)

---------------------------------------------------------------------------
STEP("saved routes come back, and junk is dropped")
local saved = GatherPathForeverDB
saved.routes[#saved.routes + 1] = "junk"
saved.routes[#saved.routes + 1] = { mapID = E }
saved.worldWidth = 99
GP:LoadSettings()
check(#GP.db.routes == 1 and GP.db.routes[1].name == "Elwynn herbs", "the real route stays")
check(GP.db.worldWidth == 10, "out-of-range settings are kept in range")
saved.sight, saved.sight100 = 50, nil
GP:LoadSettings()
check(GP.db.sight == 100, "1.1.0's 50 yards becomes the new 100")
GP.db.sight = 50
GP:LoadSettings()
check(GP.db.sight == 50, "but 50 picked later stays")

STEP("without GatherMate2")
GatherMate2 = nil
check(not GP:HasGatherMate())
check(GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } }) == nil and logHas("needs GatherMate2"))
GP:OpenConfig("new")
check(#GP:ZoneNodes(E) == 0)
GP:OpenConfig("routes")
check(GP:NodeCount(GP.db.routes[1]) == 7, "routes already made still work")

LOG[#LOG + 1] = "PASSED"
