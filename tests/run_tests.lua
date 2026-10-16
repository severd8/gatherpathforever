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
    -- every size from 2 up comes back whole
    for n = 2, 30 do
        local pts = {}
        for i = 1, n do pts[i] = { math.random() * 500, math.random() * 500 } end
        check(isTour(O.Solve(pts), n), n .. " nodes come back whole")
    end
    -- quick: on 600 nodes the old solver handed the frame back 1816 times
    local pts = {}
    for i = 1, 600 do pts[i] = { math.random() * 2000, math.random() * 1500 } end
    local pauses = 0
    O.Pause = function() pauses = pauses + 1 end
    local tour = O.Solve(pts)
    O.Pause = function() end
    check(isTour(tour, 600), "600 nodes")
    check(pauses < 700, "600 nodes take well under half the work they used to (" .. pauses .. ")")
    -- and no longer than untangling every crossing the slow way
    pts = {}
    for i = 1, 250 do pts[i] = { math.random() * 2000, math.random() * 1500 } end
    tour = O.Solve(pts)
    local plain = {}
    for i = 1, #pts do plain[i] = i end
    local better = true
    while better do
        better = false
        for i = 1, #plain - 2 do
            for j = i + 2, #plain do
                if not (i == 1 and j == #plain) then
                    local a, b = pts[plain[i]], pts[plain[i + 1]]
                    local c, d = pts[plain[j]], pts[plain[j % #plain + 1]]
                    if O.Dist(a, c) + O.Dist(b, d) < O.Dist(a, b) + O.Dist(c, d) - 1e-6 then
                        local x, y = i + 1, j
                        while x < y do plain[x], plain[y] = plain[y], plain[x]; x, y = x + 1, y - 1 end
                        better = true
                    end
                end
            end
        end
    end
    -- (0.891 now; 0.906 without the shakes, 0.910 keeping shakes that didn't help)
    check(O.Length(pts, tour) < O.Length(pts, plain) * 0.90, "a tenth shorter than untangling every crossing")
    -- the same nodes give the same route every time
    local again = O.Solve(pts)
    local same = true
    for i = 1, #pts do same = same and again[i] == tour[i] end
    check(same, "the same route every time")
end
do
    local g = O.Group({ { 0, 0 }, { 10, 0 }, { 20, 0 }, { 200, 0 } }, 12)
    check(#g == 3, "nodes within 12 yards of the first group together (not a whole chain)")
    check(near(g[1][1], 5) and g[1].count == 2 and near(g[1].reach, 5), "in the middle of them")
    check(g[3].count == 1 and g[3].reach == 0, "a lone node is its own spot")
    g = O.Group({ { 0, 0 }, { 10, 0 }, { 10, 0 }, { 10, 0 }, { -10, 0 } }, 10)
    check(#g == 1 and g[1].reach <= 10, "never leaves a node further than the radius from its spot")
    check(#O.Group({ { 0, 0 }, { 10, 0 } }, 0) == 2, "radius 0 keeps every node")
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
            -- clustered too (herbs grow in patches)
            local patch = {}
            for c = 1, 15 do
                local cx, cy = math.random() * 1200, math.random() * 900
                for _ = 1, 4 do patch[#patch + 1] = { cx + math.random() * 30, cy + math.random() * 30 } end
            end
            check(covered(patch, O.Shortcut(patch, r), r), "patches covered at " .. r)
            check(loopLength(s2) <= full + 0.01, "never longer than going to every node")
        end
    end
    check(#O.Shortcut({ { 0, 0 }, { 10, 0 } }, 50) == 2, "two nodes stay two stops")
    -- patches of nodes: one stop each, and the route only comes within reach of them
    local patches = {}
    for c = 0, 4 do
        for k = 0, 4 do patches[#patches + 1] = { c * 400 + (k % 2) * 12, (c % 2) * 300 + math.floor(k / 2) * 12 } end
    end
    local ps = O.Shortcut(patches, 60)
    check(#ps <= 5 and covered(patches, ps, 60), "a patch of nodes is one stop")
    check(loopLength(ps) < O.Length(patches, O.Solve(patches)) - 300, "and cuts the corners")
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
        local e = rawget(sw, "entry")
        if e and e.name == name and sw:IsShown() then return sw end
    end
end
check(ui.newZone.getter() == nil and not SwitchFor("Peacebloom") and ui.newNote:GetText():find("Pick a zone", 1, true),
    "starts with no zone picked")
check(not ui.cancelButton:IsShown(), "no Cancel when making a new route")
Click(ui.myZone)
check(ui.newZone.getter() == E, "My zone picks the zone you're in")
check(SwitchFor("Peacebloom") and SwitchFor("Copper Vein") and SwitchFor("Silverleaf"), "a switch per kind of node")
check(SwitchFor("Peacebloom").label:GetText():find("(5)", 1, true), "with how many there are")
Click(SwitchFor("Peacebloom"))
Click(SwitchFor("Silverleaf"))
check(SwitchFor("Peacebloom"):IsOn() and not ui.makeButton.disabled)
check(ui.sightSlider:GetValue() == 100, "new routes pass within 100 yards unless you change it")
ui.sightSlider:SetValue(0)   -- this route goes right up to every node
check(ui.mergeSlider == nil, "no Combine nodes within slider (Route passes within groups nodes itself)")
ui.newName:SetText("Picked")

STEP("New route always opens blank")
GP:OpenConfig("routes")
GP.db.sight = 90   -- what 1.1.0 remembered from the last route
GP:OpenConfig("new")
check(ui.newZone.getter() == nil and ui.newName:GetText() == "" and not SwitchFor("Peacebloom"), "no zone, name or picks")
check(ui.sightSlider:GetValue() == 100, "slider back at its default")
GP.config:Hide()
GP:OpenConfig("new")
Click(ui.myZone)
check(not SwitchFor("Peacebloom"):IsOn(), "closing the window clears the picks too")
Click(SwitchFor("Peacebloom"))
GP.config:Hide()
GP.config:Show()
check(ui.newZone.getter() == nil, "and showing it again on New route")
GP:OpenConfig("routes")
ui.routesZone.Choose(E)
Click(ui.routesNew)
check(GP.config.currentTab == "new" and ui.newZone.getter() == E, "New route on Routes starts on the zone picked there")
check(not SwitchFor("Peacebloom"):IsOn() and ui.newName:GetText() == "Elwynn Forest - " and ui.sightSlider:GetValue() == 100,
    "the rest blank, the name started with the zone")
GP.config.tabButtons.new:GetScript("OnClick")()
check(ui.newZone.getter() == nil, "the New route tab itself still starts with no zone")
check(ui.newName:GetText() == "" and ui.newHint:IsShown(), "no zone, no name yet")
Click(ui.myZone)
check(ui.newName:GetText() == "Elwynn Forest - ", "the name starts with the zone")
ui.newZone.Choose(W)
check(ui.newName:GetText() == "Westfall - ", "and follows a zone change")
ui.newName:SetText("Westfall - mine")
ui.newZone.Choose(E)
check(ui.newZone.getter() == E and ui.newName:GetText() == "Westfall - mine", "but not over a name you typed")
ui.newName:SetText("Elwynn Forest - ")

STEP("Select all")
local herbHead
for _, h in ipairs(ui.kindHeads) do if h:IsShown() and h:GetText() == "HERBS" then herbHead = h end end
check(herbHead and herbHead.all:IsShown() and herbHead.all:GetText() == "Select all", "a Select all by each kind")
Click(herbHead.all)
check(SwitchFor("Peacebloom"):IsOn() and SwitchFor("Silverleaf"):IsOn() and not SwitchFor("Copper Vein"):IsOn(),
    "switches on every node of that kind, no other")
check(herbHead.all:GetText() == "Clear all", "then reads Clear all")
for _, h in ipairs(ui.kindHeads) do
    local pt = h.all.__points[#h.all.__points]
    check(pt[3] <= 0 and pt[2] + 84 <= 540 - 30, "Select all sits inside the list (not cut off at its top)")
end
check(GP.config.__h == 556 + 120, "the window is taller than the other addons', for a longer list")
Click(herbHead.all)
check(not SwitchFor("Peacebloom"):IsOn() and not SwitchFor("Silverleaf"):IsOn(), "which switches them off")
check(herbHead.all:GetText() == "Select all")
check(ui.makeButton.disabled, "nothing picked again")

STEP("make a route from the window, named after its zone")
Click(SwitchFor("Peacebloom"))
Click(SwitchFor("Silverleaf"))
check(ui.newHint:IsShown() and ui.newHint:GetText() == "Peacebloom and Silverleaf", "the rest of the name greyed after the zone")
ui.sightSlider:SetValue(0)
Click(ui.makeButton)
check(GP:Busy(), "working it out over a few frames")
check(GP.config.currentTab == "routes", "then shows the routes")
RunJobs()
local route = GP.db.routes[1]
check(#GP.db.routes == 1 and route.name == "Elwynn Forest - Peacebloom and Silverleaf", "named from the zone and what was picked")
check(GP:NodeCount(route) == 7, "7 nodes")
check(logHas("made |cffffd100Elwynn Forest - Peacebloom and Silverleaf|r in Elwynn Forest: 7 nodes"), "says so in chat")
check(route.shown and route.color and route.mapID == E)
-- the length is the loop's, in yards
local pts, tour = {}, {}
for i = 1, 7 do pts[i] = { route.points[2 * i - 1] * 1600, route.points[2 * i] * 1066 }; tour[i] = i end
check(near(route.length, O.Length(pts, tour), 0.01), "length in yards")
check(ui.routeRows[1]:IsShown() and ui.routeRows[1].route == route, "listed")
check(ui.routeRows[1].info:GetText():find("7 nodes", 1, true))
check(ui.routeRows[1].name:GetText() == route.name)

STEP("with a route listed, the rest of the window still fills in")
-- 1.2.0: the routes list stopped on Rebuild (it had no SetDisabled), so New route
-- was left with an empty zone menu and sliders without their values
GP:OpenConfig("new")
check(#ui.newZone.keys > 0, "New route's zone menu has the zones")
check(ui.newZone:GetText() == "Pick a zone", "and reads Pick a zone")
check(ui.sightSlider.valueText:GetText() == "100 yards", "passes within shows its value")
check(ui.newNote:GetText():find("Pick a zone above", 1, true), "the list says what to do")
GP:NewRoute({ mapID = E, kinds = { Herb = { Peacebloom = true } }, name = "busy" })
GP:OpenConfig("routes")
check(ui.routeRows[1].rebuild.disabled, "Rebuild greys out while a loop is worked out")
Click(ui.routeRows[1].rebuild)
RunJobs()
for i = #GP.db.routes, 1, -1 do if GP.db.routes[i].name == "busy" then GP:DeleteRoute(GP.db.routes[i]) end end
GP:OpenConfig("routes")
check(not ui.routeRows[1].rebuild.disabled, "and comes back after")

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
check(GP:NodeCount(route) == 7 and logHas("Elwynn Forest - Peacebloom and Silverleaf: 7 nodes"), "Rebuild reads the nodes again")

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
    and nearRow.info:GetText():find("\nPasses within 50 yards", 1, true), "listed with its distance, on a second line")
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

STEP("edit a route")
GP:OpenConfig("routes")
local color, id = route.color, route.id
Click(ui.routeRows[1].edit)
local newPage = GP.config.pages.new
check(GP.config.currentTab == "new" and newPage.title:GetText() == "Edit route", "Edit opens the route's options")
check(ui.newZone.getter() == E and ui.newName:GetText() == "Elwynn herbs", "its zone and name")
check(SwitchFor("Peacebloom"):IsOn() and SwitchFor("Silverleaf"):IsOn() and not SwitchFor("Copper Vein"):IsOn(), "its nodes")
check(ui.sightSlider:GetValue() == 0, "its pass within")
check(ui.makeButton:GetText() == "Save changes" and ui.cancelButton:IsShown())
Click(SwitchFor("Silverleaf"))
Click(ui.cancelButton)
check(GP.config.currentTab == "routes" and route.kinds["Herb Gathering"].Silverleaf and not GP:Busy(), "Cancel leaves it")
GP:OpenConfig("new")
check(newPage.title:GetText() == "New route" and ui.newZone.getter() == nil and ui.newName:GetText() == ""
    and ui.makeButton:GetText() == "Make route", "New route is blank again after an edit")

GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } })
RunJobs()
local copper = GP.db.routes[2]
GP:OpenConfig("routes")
Click(ui.routeRows[1].edit)
ui.newName:SetText("copper vein")
Click(ui.makeButton)
check(GP.config.currentTab == "new" and not GP:Busy() and route.name == "Elwynn herbs"
    and logHas("already a route called |cffffd100copper vein|r"), "not to another route's name")
check(SwitchFor("Peacebloom"):IsOn() and ui.newName:GetText() == "copper vein", "and keeps what was picked")

ui.newName:SetText("Just Peacebloom")
Click(SwitchFor("Silverleaf"))
ui.sightSlider:SetValue(50)
Click(ui.makeButton)
check(GP:Busy() and route.working and GP.config.currentTab == "routes", "Save changes works it out again")
check(ui.routeRows[1].edit.disabled, "no Edit while it's being worked out")
RunJobs()
check(#GP.db.routes == 2 and route.name == "Just Peacebloom" and route.sight == 50 and route.nodes == 7
    and not route.kinds["Herb Gathering"].Silverleaf, "changed in place")
check(route.id == id and route.color == color and GP.db.routes[1] == route, "the same route, same color")
check(logHas("changed |cffffd100Just Peacebloom|r in Elwynn Forest: 7 nodes"), "says so in chat")
check(not ui.routeRows[1].edit.disabled)

Click(ui.routeRows[1].edit)
ui.newName:SetText("")
Click(SwitchFor("Silverleaf"))
ui.sightSlider:SetValue(0)
Click(ui.makeButton)
RunJobs()
check(route.name == "Elwynn Forest - Peacebloom and Silverleaf" and GP:NodeCount(route) == #GP:CollectNodes(E, route.kinds),
    "a blank name is made from the nodes")
check(GP:EditRoute(route, { kinds = route.kinds, name = "Elwynn herbs", sight = 0 }))
RunJobs()
check(route.name == "Elwynn herbs" and route.mapID == E, "its own zone when none is given")
check(GP:EditRoute(route, { kinds = route.kinds, name = " elwynn HERBS", sight = 0 }), "keeping its own name is fine")
RunJobs()
check(route.name == "elwynn HERBS")
GP:RenameRoute(route, "Elwynn herbs")

local before = route.points
check(GP:EditRoute(route, { mapID = E, kinds = { Mining = { ["Tin Vein"] = true } }, name = "Tin" }))
RunJobs()
check(route.points == before and route.name == "Elwynn herbs" and route.kinds["Herb Gathering"].Peacebloom
    and route.sight == 0 and logHas("was left as it was"), "no nodes there: left as it was")
check(not GP:EditRoute(route, { kinds = {} }) and logHas("pick at least one"), "nothing picked: no change")

GP:OpenConfig("routes")
Click(ui.routeRows[2].edit)
GP:DeleteRoute(copper)
check(ui.newZone.getter() == nil and newPage.title:GetText() == "New route", "the route deleted meanwhile: blank")
GP:OpenConfig("routes")

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

STEP("range circle on the minimap")
check(GP.db.range == false and #Shown(GP.mm.ring) == 0, "off to start")
check(GP.db.rangeYards == 100 and ui.rangeYards and ui.rangeAlpha, "100 yards, with sliders")
Click(ui.rangeSwitch)
check(GP.db.range == true)
local ring = Shown(GP.mm.ring)
check(#ring == 64, "a full circle: the minimap shows 150 yards, so 100 fits")
local r = 100 * 70 / 150
for _, l in ipairs(ring) do
    check(near(math.sqrt(l.__from[1] ^ 2 + l.__from[2] ^ 2), r, 0.01), "100 yards from you")
end
local rc = GP.db.rangeColor
check(ring[1].__color[1] == rc[1] and near(ring[1].__color[4], 0.6), "in its color and opacity")
check(ui.rangeColor.fill.__color[1] == rc[1], "the square shows the color")
GP.db.rangeColor, GP.db.rangeAlpha = { 1, 0, 0.5 }, 30
GP:Changed()
ring = Shown(GP.mm.ring)
check(ring[1].__color[1] == 1 and ring[1].__color[3] == 0.5 and near(ring[1].__color[4], 0.3), "a new color and opacity")
check(ui.rangeColor.fill.__color[3] == 0.5)
Click(ui.minimapSwitch)
check(#Shown(GP.mm.pool) == 0 and #Shown(GP.mm.ring) == 64, "stays with the route lines off")
Click(ui.minimapSwitch)
GP.db.rangeYards = 200
GP:Changed()
check(#Shown(GP.mm.ring) == 0, "beyond the minimap's edge: nothing drawn")
VIEW_RADIUS = 300
GP:DrawMinimap()
check(#Shown(GP.mm.ring) == 64, "zoomed out it's back without forcing a redraw")
VIEW_RADIUS = 150
GP.db.rangeYards = 100
Click(ui.rangeSwitch)
check(#Shown(GP.mm.ring) == 0, "and off again")
GP.db.rangeColor, GP.db.rangeAlpha = { 0.25, 0.80, 1.00 }, 60

STEP("line color and opacity, each map on its own")
WorldMapFrame:SetMapID(E)
PLAYER.x, PLAYER.y = 0.5, 0.5
local herbs = GP.db.routes[1]
local function firstLine(pool) return Shown(pool)[1] end
GP:Changed()
check(GP.db.worldRouteColor and GP.db.minimapRouteColor, "routes keep their own color to start")
check(ui.worldColor.disabled and ui.minimapColor.disabled, "so the one-color squares are greyed out")
check(firstLine(pin.pool).__color[1] == herbs.color[1], "world map: the route's color")
Click(ui.worldRouteColor)
check(GP.db.worldRouteColor == false and not ui.worldColor.disabled, "own color off: the square can be clicked")
GP:SetLineColor("world", 0.1, 0.2, 0.3)
local c = firstLine(pin.pool).__color
check(c[1] == 0.1 and c[2] == 0.2 and c[3] == 0.3, "world map lines take the picked color")
check(ui.worldColor.fill.__color[1] == 0.1, "and the square shows it")
local m = firstLine(GP.mm.pool)
check(m and m.__color[1] == herbs.color[1], "the minimap keeps the route's color")
GP.db.worldAlpha = 40
GP:Changed()
check(near(firstLine(pin.pool).__color[4], 0.4), "world map opacity")
check(near(firstLine(GP.mm.pool).__color[4], 0.85), "the minimap's opacity is its own")
Click(ui.minimapRouteColor)
GP:SetLineColor("minimap", 0.9, 0.8, 0.7)
GP.db.minimapAlpha = 60
GP:Changed()
c = firstLine(GP.mm.pool).__color
check(c[1] == 0.9 and c[3] == 0.7 and near(c[4], 0.6), "minimap lines take their own color and opacity")
check(firstLine(pin.pool).__color[1] == 0.1, "world map unchanged")
Click(ui.worldRouteColor)
check(firstLine(pin.pool).__color[1] == herbs.color[1], "own color back on")
Click(ui.minimapRouteColor)
GP.db.worldAlpha, GP.db.minimapAlpha = 85, 85
GP:Changed()

---------------------------------------------------------------------------
STEP("saved routes come back, and junk is dropped")
local saved = GatherPathForeverDB
saved.routes[#saved.routes + 1] = "junk"
saved.routes[#saved.routes + 1] = { mapID = E }
saved.worldWidth = 99
GP:LoadSettings()
check(#GP.db.routes == 1 and GP.db.routes[1].name == "Elwynn herbs", "the real route stays")
check(GP.db.worldWidth == 10, "out-of-range settings are kept in range")
saved.rangeYards, saved.rangeColor = 999, "junk"
GP:LoadSettings()
check(GP.db.rangeYards == 200 and GP.db.rangeColor[2] == 0.80, "the range circle's settings too")
saved.sight, saved.sight100 = 50, nil
GP:LoadSettings()
check(GP.db.sight == 100, "1.1.0's 50 yards becomes the new 100")
GP.db.sight = 50
GP:LoadSettings()
check(GP.db.sight == 50, "but 50 picked later stays")
local points = #GP.db.routes[1].points
GP.db.routes[1].merge, GP.db.merge = 20, 20   -- from before 1.3.0
GP:LoadSettings()
check(GP.db.routes[1].merge == nil and GP.db.merge == nil, "the old merge setting is gone")
check(#GP.db.routes[1].points == points, "and the route's loop is left as it was")
saved.alpha, saved.worldAlpha, saved.minimapAlpha = 50, nil, nil   -- one Opacity before 1.5.0
saved.worldColor, saved.minimapColor = "junk", { 2, -1, 0.5 }
GP:LoadSettings()
check(GP.db.worldAlpha == 50 and GP.db.minimapAlpha == 50 and GP.db.alpha == nil, "the old opacity carries over to both")
check(GP.db.worldColor[1] == 1 and GP.db.worldColor[2] == 0.82, "a broken color goes back to gold")
local mc = GP.db.minimapColor
check(mc[1] == 1 and mc[2] == 0 and mc[3] == 0.5, "a color is kept between 0 and 1")
saved.alpha = 30
GP:LoadSettings()
check(GP.db.worldAlpha == 50, "but only once")

STEP("without GatherMate2")
GatherMate2 = nil
check(not GP:HasGatherMate())
check(GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } }) == nil and logHas("needs GatherMate2"))
GP:OpenConfig("new")
check(#GP:ZoneNodes(E) == 0)
GP:OpenConfig("routes")
check(GP:NodeCount(GP.db.routes[1]) == 9, "routes already made still work")

LOG[#LOG + 1] = "PASSED"
