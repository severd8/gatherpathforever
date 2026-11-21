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
STEP("timed runs in the solver")
do
    local function Loop(ps)
        local t, n = 0, #ps
        for i = 1, n do t = t + O.Euclid(ps[i], ps[i % n + 1]) end
        return t
    end
    -- a busy patch (30 nodes in 120 x 120 yards) far from 30 nodes spread over 2000 x 2000
    local rnd = 12345
    local function R() rnd = (rnd * 1103515245 + 12345) % 2147483648; return rnd / 2147483648 end
    local pts, busy = {}, {}
    for i = 1, 30 do local p = { 3000 + R() * 120, 3000 + R() * 120 }; pts[#pts + 1] = p; busy[p] = true end
    for i = 1, 30 do pts[#pts + 1] = { R() * 2000, R() * 2000 } end
    local groups = O.Group(pts, 50)
    local members = 0
    for _, g in ipairs(groups) do members = members + #g.members; check(#g.members == g.count) end
    check(members == #pts, "every node is in one group's members")
    -- 800 yards: room for the patch, nothing like the whole field
    local sub, k, len = O.Budget(pts, 800, 0)
    check(k == #sub and k >= 25, "most of the busy patch fits")
    local inPatch = 0
    for _, p in ipairs(sub) do if busy[p] then inPatch = inPatch + 1 end end
    check(inPatch == k, "only nodes from the busy patch")
    check(len <= 800, "the loop fits the time")
    local solved = {}
    for i, p in ipairs(sub) do solved[i] = p end
    local t = O.Solve(solved)
    check(O.Length(solved, t) <= 800 + 1e-6, "and so does the solved loop")
    -- on a spread field too, every budget's nodes make a loop that fits it
    local spread = {}
    for i = 1, 120 do spread[i] = { R() * 1500, R() * 1500 } end
    for _, L in ipairs({ 300, 600, 1200, 2400 }) do
        local s1, k1, l1 = O.Budget(spread, L, 0)
        local idx = {}
        for i = 1, #s1 do idx[i] = i end
        check(l1 <= L and k1 >= 3, L .. " yards: fits")
        check(O.Length(s1, O.Solve(s1)) <= l1 + 1e-6, "its length is the loop's (" .. L .. ")")
    end
    local sub2 = O.Budget(pts, 800, 0)
    check(#sub2 == #sub, "the same nodes every time")
    -- with passes within
    local subS = O.Budget(pts, 400, 100)
    local stops = O.Shortcut(subS, 100)
    check(#subS >= 25 and Loop(stops) <= 400, "passes within: the patch in a short loop")
    -- the whole field fits a big budget
    local all, n = O.Budget(pts, 1e7, 0)
    check(n == #pts and all[1], "a long enough time takes every node")
    -- more time, more nodes
    local _, kSmall = O.Budget(pts, 300, 0)
    local _, kBig = O.Budget(pts, 3000, 0)
    check(kSmall < k and k <= kBig, "more time takes in more nodes")
    check(#O.Budget({ { 0, 0 } }, 100, 0) == 1, "one node: nothing to do")
    -- worth the ride: 6 nodes together 150 yards off beat 6 singles strung out close by
    local fieldA, far = {}, {}
    for i = 1, 12 do fieldA[#fieldA + 1] = { (i % 4) * 3, math.floor(i / 4) * 3 } end
    for i = 1, 6 do local p = { 150 + (i % 3) * 3, (i % 2) * 3 }; fieldA[#fieldA + 1] = p; far[p] = true end
    for i = 1, 6 do fieldA[#fieldA + 1] = { -5, -60 * i } end
    O.BUDGET_SEEDS = 1   -- grown from the busiest patch only
    local subA = O.Budget(fieldA, 330, 40)
    O.BUDGET_SEEDS = 8
    local got = 0
    for _, p in ipairs(subA) do if far[p] then got = got + 1 end end
    check(got == 6 and #subA >= 18, "the most nodes per yard ridden, not just the nearest")
    -- the busiest patch is found even when it's listed last among many
    local patches = {}
    for pi = 1, 12 do
        local size = pi == 12 and 15 or 3
        for i = 1, size do patches[#patches + 1] = { pi * 1000 + (i % 4) * 5, (i % 3) * 5 } end
    end
    local _, kP = O.Budget(patches, 200, 0)
    check(kP == 15, "the busiest of a dozen patches")
end

---------------------------------------------------------------------------
STEP("taboo areas in the solver")
do
    -- a tall block in the middle of a 1000 x 1000 field
    local block = { 450, -10, 550, -10, 550, 900, 450, 900 }
    local W = O.Walls({ block })
    check(W and #W.verts == 4, "its four corners to go round")
    check(O.Walls({}) == nil and O.Walls({ { 0, 0, 1, 1 } }) == nil, "no areas (or one with 2 corners): no walls")
    check(W:Inside({ 500, 500 }) and not W:Inside({ 400, 500 }), "inside and outside")
    check(W:Blocked({ 100, 500 }, { 900, 500 }) and not W:Blocked({ 100, 950 }, { 900, 950 }), "a line through it is blocked")
    check(not W:Blocked({ 100, 500 }, { 300, 500 }), "a line beside it isn't")
    -- round the top: (100,500) -> (447,903) -> (553,903) -> (900,500)
    local d = W:Dist({ 100, 500 }, { 900, 500 })
    local over = 2 * math.sqrt(347 ^ 2 + 403 ^ 2) + 106
    check(near(d, over, 0.01), "the way round is the distance (" .. d .. ")")
    local path = W:Path({ 100, 500 }, { 900, 500 })
    check(#path == 2 and near(path[1][1], 450 - O.WALL_MARGIN) and near(path[1][2], 900 + O.WALL_MARGIN)
        and near(path[2][1], 550 + O.WALL_MARGIN), "bending round the two top corners, a little out from them")
    check(#W:Path({ 100, 950 }, { 900, 950 }) == 0, "no bends on a clear line")
    -- a U: from inside its pocket out under it goes up, over an arm and down
    local U = { 300, 200, 700, 200, 700, 1000, 600, 1000, 600, 300, 400, 300, 400, 1000, 300, 1000 }
    local WU = O.Walls({ U })
    check(not WU:Inside({ 500, 600 }) and WU:Inside({ 350, 600 }), "the pocket isn't inside, the arm is")
    local up = WU:Path({ 500, 600 }, { 500, 100 })
    check(#up == 3 and up[1][2] > 1000 and up[3][2] < 200, "out of the pocket and round an arm")
    check(near(WU:Dist({ 500, 600 }, { 500, 100 }), WU:Dist({ 500, 100 }, { 500, 600 })), "the same both ways")
    check(O.SelfCrossing({ 0, 0, 10, 10, 10, 0, 0, 10 }) and not O.SelfCrossing(U), "edges that cross are found")
    -- random fields round the block, every way: no leg goes through it
    local function covered(nodes, stops, r)
        for _, c in ipairs(nodes) do
            local best = math.huge
            for i = 1, #stops do best = math.min(best, O.SegDist(stops[i], stops[i % #stops + 1], c)) end
            if best > r + 0.5 then return false end
        end
        return true
    end
    local function blockedLegs(stops, w)
        local bad = 0
        for i = 1, #stops do if w:Blocked(stops[i], stops[i % #stops + 1]) then bad = bad + 1 end end
        return bad
    end
    for _, r in ipairs({ 0, 60 }) do
        for _ = 1, 4 do
            local pts = {}
            while #pts < 80 do
                local q = { math.random() * 1000, math.random() * 1000 }
                if not W:Inside(q) then pts[#pts + 1] = q end
            end
            O.SetWalls(W)
            local stops = O.Expand(O.Shortcut(pts, r))
            O.SetWalls(nil)
            check(blockedLegs(stops, W) == 0, "no leg crosses the area (passes within " .. r .. ")")
            local bends, inside = 0, 0
            for _, st in ipairs(stops) do
                if st.bend then bends = bends + 1 end
                if W:Inside(st) then inside = inside + 1 end
            end
            check(bends > 0 and inside == 0, "it bends round, and no stop is in it")
            if r == 0 then check(#stops - bends == 80, "every node is still a stop") end
            if r > 0 then check(covered(pts, stops, r), "every node is still passed within reach") end
            -- without the area the same nodes go straight through
            check(blockedLegs(O.Shortcut(pts, r), W) > 0, "(which they would without it)")
        end
    end
    check(O.GetWalls() == nil and O.Dist({ 0, 0 }, { 3, 4 }) == 5, "walls off again: straight lines")
    -- a stop that passes within reach never stands behind the area from its node
    O.SetWalls(W)
    local spot = O.Place({ 400, 500 }, { 400, 600 }, { 560, 550 }, 120)
    O.SetWalls(nil)
    check(not W:Inside(spot) and not W:Blocked(spot, { 560, 550 }), "the stop stays on the node's side")
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
check(ui.sightSlider:GetValue() == 185, "new routes pass within 185 yards unless you change it")
check(ui.sightSlider.valueText:GetText() == "185 yards", "185 stays 185 (not rounded to 190 by the slider's steps)")
ui.sightSlider:SetValue(200)
check(ui.sightSlider:GetValue() == 200 and ui.sightSlider.valueText:GetText() == "200 yards", "the slider goes up to 200 yards")
ui.sightSlider:SetValue(0)   -- this route goes right up to every node
check(ui.mergeSlider == nil, "no Combine nodes within slider (Route passes within groups nodes itself)")
ui.newName:SetText("Picked")

STEP("New route always opens blank")
GP:OpenConfig("routes")
GP.db.sight = 90   -- what 1.1.0 remembered from the last route
GP:OpenConfig("new")
check(ui.newZone.getter() == nil and ui.newName:GetText() == "" and not SwitchFor("Peacebloom"), "no zone, name or picks")
check(ui.sightSlider:GetValue() == 185, "slider back at its default")
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
check(not SwitchFor("Peacebloom"):IsOn() and ui.newName:GetText() == "Elwynn Forest - " and ui.sightSlider:GetValue() == 185,
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
check(ui.sightSlider.valueText:GetText() == "185 yards", "passes within shows its value")
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
STEP("skip list")
GP:OpenConfig("new")
Click(ui.myZone)
check(not GP:IsSkipped("Silverleaf") and #GP:SkippedNames() == 0, "nothing skipped to start")
Click(SwitchFor("Silverleaf"))
check(SwitchFor("Silverleaf"):IsOn())
Click(SwitchFor("Silverleaf"), "RightButton")
check(GP:IsSkipped("Silverleaf") and GP.db.skip.Silverleaf == true, "right-click puts it on the skip list")
check(logHas("|cffffd100Silverleaf|r is skipped"), "says so in chat")
check(not SwitchFor("Silverleaf"):IsOn() and SwitchFor("Silverleaf").label:GetText():find("skipped", 1, true),
    "shown off and marked skipped")
check(ui.makeButton.disabled, "a skipped node alone can't make a route")
for _, e in ipairs(GP:ZoneNodes(E)) do
    if e.name == "Silverleaf" then check(e.skip, "ZoneNodes marks it") end
end
herbHead = nil
for _, h in ipairs(ui.kindHeads) do if h:IsShown() and h:GetText() == "HERBS" then herbHead = h end end
Click(herbHead.all)
check(SwitchFor("Peacebloom"):IsOn() and not SwitchFor("Silverleaf"):IsOn(), "Select all leaves it off")
check(herbHead.all:GetText() == "Clear all", "and every node that isn't skipped counts as all")
check(ui.newHint:GetText() == "Earthroot and Peacebloom", "the made-up name leaves it out")
Click(herbHead.all)
local herbsBoth = { ["Herb Gathering"] = { Peacebloom = true, Silverleaf = true } }
local peace = 0
for _, e in ipairs(GP:ZoneNodes(E)) do if e.name == "Peacebloom" then peace = e.count end end
check(peace > 0 and #GP:CollectNodes(E, herbsBoth) == peace, "no route reads its nodes")
check(GP:RouteName(E, herbsBoth) == "Peacebloom")
check(not GP:AnyPicked({ ["Herb Gathering"] = { Silverleaf = true } }), "picking only skipped nodes picks nothing")
check(GP:NewRoute({ mapID = E, kinds = { ["Herb Gathering"] = { Silverleaf = true } } }) == nil
    and logHas("pick at least one kind of node"), "so no route is made from them")
local before = GP:NodeCount(route)
local kept = { points = { unpack(route.points) }, nodes = route.nodes, length = route.length }
gm:Add(E, "Herb Gathering", 2, 0.66, 0.44)
check(GP:NodeCount(route) == before, "a new skipped node doesn't join a route that has its kind")
gm:Delete(E, "Herb Gathering", 0.66, 0.44)
check(GP:RebuildRoute(route))
RunJobs()
check(route.nodes == peace, "rebuilding a route drops the skipped nodes")
SlashCmdList.GATHERPATHFOREVER("skipped")
check(logHas("skipped (right-click one on the New route tab to stop skipping it): Silverleaf"), "/gpf skipped lists them")
GP:OpenConfig("new")
Click(ui.myZone)
Click(SwitchFor("Silverleaf"))
check(not GP:IsSkipped("Silverleaf") and SwitchFor("Silverleaf"):IsOn(), "clicking a skipped node unskips and picks it")
Click(SwitchFor("Silverleaf"), "RightButton")
Click(SwitchFor("Silverleaf"), "RightButton")
check(not GP:IsSkipped("Silverleaf") and logHas("is no longer skipped"), "right-click again stops skipping it")
check(GP:RebuildRoute(route))
RunJobs()
check(route.nodes == peace + 2, "and a rebuild brings it back")
GatherPathForeverDB.skip = { Silverleaf = true, [5] = true, Junk = "yes" }
GP:LoadSettings()
check(GP:IsSkipped("Silverleaf") and #GP:SkippedNames() == 1, "the saved list comes back, junk dropped")
GP.db.skip = {}
route.points, route.nodes, route.length = kept.points, kept.nodes, kept.length   -- as the later steps expect
GP:OpenConfig("routes")

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
    and nearRow.info:GetText():find("a lap on foot  -  passes within 50 yards", 1, true), "listed with its distance, on a second line")
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

STEP("restore defaults on the display tab")
local routesBefore, angleBefore = #GP.db.routes, GP.db.minimapAngle
GP.db.minimapAngle = 123
GP.db.sight = 40
Click(GP.minimapButton, "RightButton")   -- lines hidden from the minimap button
GP.db.worldWidth, GP.db.minimapAlpha, GP.db.rangeYards = 9, 20, 180
GP.db.worldRouteColor, GP.db.arrows, GP.db.arrowsReverse, GP.db.joinLine = false, false, true, false
GP.db.range, GP.db.autoAdd, GP.db.minimapButton = true, false, false
GP:SetLineColor("minimap", 0.1, 0.2, 0.3)
GP.db.rangeColor = { 0, 0, 0 }
GP:UpdateMinimapButton()
check(ui.restoreDefaults, "a Restore defaults button")
Click(ui.restoreDefaults)
check(GP.confirmWindow:IsShown() and GP.db.worldWidth == 9, "asks first")
Click(GP.confirmWindow.no)
check(GP.db.worldWidth == 9, "Cancel changes nothing")
Click(ui.restoreDefaults)
Click(GP.confirmWindow.yes)
for _, k in ipairs(GP.DISPLAY_KEYS) do
    local v, d = GP.db[k], GP.DEFAULTS[k]
    if type(d) == "table" then
        check(v ~= d and v[1] == d[1] and v[2] == d[2] and v[3] == d[3], k .. " back to its default (a copy)")
    else
        check(v == d, k .. " back to its default")
    end
end
local listed = {}
for _, k in ipairs(GP.DISPLAY_KEYS) do listed[k] = true end
local notOnTab = { minimapAngle = true, sight = true, nextColor = true, tabooShow = true }
for k in pairs(GP.DEFAULTS) do
    check(listed[k] or notOnTab[k], k .. ": every setting on the tab is restored")
end
check(GP.db.hiddenWas == nil and GP.db.worldMap and GP.db.minimap, "hidden lines shown again")
check(GP.minimapButton:IsShown(), "the minimap button back")
check(#GP.db.routes == routesBefore and GP.db.minimapAngle == 123 and GP.db.sight == 40,
    "routes, the button's place and New route's slider kept")
GP.db.minimapAngle, GP.db.sight = angleBefore, GP.DEFAULTS.sight
GP:SetLineColor("minimap", 0.5, 0.5, 0.5)
check(GP.DEFAULTS.minimapColor[1] == 1, "changing a color after doesn't touch the defaults")
GP:RestoreDefaults()

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

STEP("direction arrows")
-- spacing along the loop, pure: a 100 x 100 square, an arrow every 100 pixels
local marks = GP.ArrowMarks({ 0, 100, 100, 0 }, { 0, 0, 100, 100 }, 4, 100)
check(#marks == 4, "one arrow per 100 pixels of the way round")
check(marks[1][1] == 50 and marks[1][2] == 0 and marks[1][3] == 1 and marks[1][4] == 0, "half a spacing in, pointing along the leg")
check(marks[2][1] == 100 and marks[2][2] == 50 and marks[2][4] == 1, "then round the corner")
check(marks[4][1] == 0 and marks[4][2] == 50 and marks[4][4] == -1, "and back to the start")
marks = GP.ArrowMarks({ 0, 100, 100, 0 }, { 0, 0, 100, 100 }, 4, 100, true)
check(#marks == 4 and marks[1][1] == 0 and marks[1][2] == 50 and marks[1][4] == 1, "reversed: the other way round")
check(#GP.ArrowMarks({ 0, 100, 100, 0 }, { 0, 0, 100, 100 }, 4, 40) == 10, "closer together")
check(#GP.ArrowMarks({ 0, 100 }, { 0, 0 }, 2, 10) == 0, "there and back (two stops): no arrows")
check(#GP.ArrowMarks({ 0, 0, 0 }, { 0, 0, 0 }, 3, 10) == 0, "stops on top of each other: no arrows")

check(GP.db.arrows == true and GP.db.arrowsReverse == false, "on to start, not reversed")
check(ui.arrowsSwitch and ui.arrowsReverse, "two switches on Display")
local herbPoints = herbs.points
herbs.points = { 0.4, 0.4, 0.6, 0.4, 0.6, 0.7, 0.4, 0.7 }
local wasShown = {}
for i, r in ipairs(GP.db.routes) do wasShown[i] = r.shown; r.shown = (r == herbs) end
WorldMapFrame:SetMapID(E)
GP:Changed()
local wa = Shown(pin.arrows)
check(#wa == 20, "world map: an arrow (two lines) every 80 pixels of an 800-pixel loop")
check(#Shown(pin.pool) == 4, "and the route's own lines are unchanged")
-- the first arrow sits 40 pixels along the top edge, pointing east (right)
check(near(wa[1].__to[1], 440 + 6, 0.01) and near(wa[1].__to[2], -266.8, 0.01), "the tip, ahead of its middle")
check(near(wa[1].__from[1], 440 - 6, 0.01) and near(math.abs(wa[1].__from[2] + 266.8), 7.2, 0.01), "the wings behind it")
check(wa[1].__to[1] == wa[2].__to[1] and wa[1].__to[2] == wa[2].__to[2], "two lines meeting at the tip")
check(wa[1].__color[1] == herbs.color[1] and near(wa[1].__color[4], 0.85) and wa[1].__thickness == 4,
    "in the line's color, opacity and width")
Click(ui.arrowsReverse)
check(GP.db.arrowsReverse == true)
wa = Shown(pin.arrows)
-- reversed, the first leg runs from the first stop down the west edge
check(#wa == 20 and near(wa[1].__to[1], 400, 0.01) and wa[1].__to[2] < wa[1].__from[2], "reversed: pointing down (south)")
Click(ui.arrowsReverse)

-- minimap: a square 50 yards round you, 23.3 pixels each way
local a, b = 50 / 1600, 50 / 1066
herbs.points = { 0.5 - a, 0.5 - b, 0.5 + a, 0.5 - b, 0.5 + a, 0.5 + b, 0.5 - a, 0.5 + b }
PLAYER.x, PLAYER.y = 0.5, 0.5
GP:Changed()
local ma = Shown(GP.mm.arrows)
local edge = 50 * 70 / 150
check(#ma == 10, "minimap: an arrow every 40 pixels of a 187-pixel loop")
check(near(ma[1].__to[1], -edge + 20 + 4.5, 0.01) and near(ma[1].__to[2], edge, 0.01), "the first along the north edge, pointing east")
check(ma[1].__thickness == 3, "as wide as the minimap's lines")
for _, l in ipairs(ma) do check(inside(l.__from[1], l.__from[2]) and inside(l.__to[1], l.__to[2]), "inside the minimap") end
GP.db.arrowsReverse = true
GP:DrawMinimap()
ma = Shown(GP.mm.arrows)
check(near(ma[1].__to[1], -edge, 0.01) and ma[1].__to[2] < ma[1].__from[2], "reversed without forcing a redraw: pointing south")
GP.db.arrowsReverse = false
-- an arrow that would stick out past the edge isn't drawn
herbs.points = { 0.5 - 3 * a, 0.5 - b, 0.5 + 3 * a, 0.5 - b, 0.5, 0.5 + b }
GP:Changed()
for _, l in ipairs(Shown(GP.mm.arrows)) do
    check(inside(l.__from[1], l.__from[2]) and inside(l.__to[1], l.__to[2]), "only arrows wholly on the minimap")
end
check(#Shown(GP.mm.arrows) > 0, "the ones inside still are")
Click(ui.arrowsSwitch)
check(GP.db.arrows == false and #Shown(GP.mm.arrows) == 0 and #Shown(pin.arrows) == 0, "off: no arrows anywhere")
check(#Shown(GP.mm.pool) > 0 and #Shown(pin.pool) > 0, "the lines stay")
Click(ui.arrowsSwitch)
check(#Shown(GP.mm.arrows) > 0, "back on")
Click(ui.minimapSwitch)
check(#Shown(GP.mm.arrows) == 0, "minimap lines off: its arrows go too")
Click(ui.minimapSwitch)
herbs.points = herbPoints
for i, r in ipairs(GP.db.routes) do r.shown = wasShown[i] end
GP:Changed()

STEP("time for a lap")
local lapRoute = { mapID = E, points = {}, length = 700 }
GP.db.speed = nil
check(GP:Speed() == 7 and GP:LapTime(lapRoute) == "about 2 min", "on foot: 7 yards a second")
lapRoute.length = 300
check(GP:LapTime(lapRoute) == "under a minute")
lapRoute.length = 7 * 60 * 75
check(GP:LapTime(lapRoute) == "about 1 h 15 min", "hours and minutes")
UNIT_SPEED = 7
check(GP:SampleSpeed() == false and GP.db.speed == nil, "on foot: nothing remembered")
UNIT_SPEED = 14
check(GP:SampleSpeed() == true and GP.db.speed == 14, "mounted: its speed is remembered")
check(GP:SampleSpeed() == false, "the same speed again: no change")
lapRoute.length = 14 * 60 * 6
check(GP:LapTime(lapRoute) == "about 6 min", "laps at that speed")
UNIT_SPEED = 7
GP:SampleSpeed()
check(GP.db.speed == 14, "kept after you get off")
UNIT_SPEED = SECRET
check(GP:SampleSpeed() == false and GP.db.speed == 14, "a hidden speed is left alone")
UNIT_SPEED = 7
GP:OpenConfig("routes")
local lapRow = ui.routeRows[1]
check(lapRow.info:GetText():find("\nAbout %d+ min a lap") or lapRow.info:GetText():find("\nUnder a minute a lap"),
    "the Routes tab shows it on the second line")
check(not lapRow.info:GetText():find("on foot", 1, true), "mounted speed known: no 'on foot'")
GP.db.speed = nil
GP:RefreshConfig()
check(lapRow.info:GetText():find("a lap on foot", 1, true), "otherwise it says on foot")

STEP("line to the route on the minimap")
local nx, ny, nd = GP.NearestOnLoop({ 0, 100, 100 }, { 10, 10, 50 }, 3, 50, 0)
check(nx == 50 and ny == 10 and nd == 10, "the nearest point can be along a leg")
nx, ny, nd = GP.NearestOnLoop({ 0, 100 }, { 10, 10 }, 2, -30, 50)
check(nx == 0 and ny == 10 and nd == 50, "or a stop")
check(GP.db.joinLine == true and ui.joinSwitch, "on to start, with a switch")
local wasShown2 = {}
for i, r in ipairs(GP.db.routes) do wasShown2[i] = r.shown; r.shown = (r == herbs) end
local herbPoints2 = herbs.points
-- a loop 100 yards north of you: 46.7 pixels up
local yn = 100 / 1066
herbs.points = { 0.45, 0.5 - yn, 0.55, 0.5 - yn, 0.5, 0.5 - 3 * yn }
PLAYER.x, PLAYER.y = 0.5, 0.5
GP:Changed()
local jl = Shown(GP.mm.join)
check(#jl > 2, "dashes toward the route")
local up = 100 * 70 / 150
for _, l in ipairs(jl) do
    check(near(l.__from[1], 0, 0.01) and near(l.__to[1], 0, 0.01) and l.__to[2] > l.__from[2], "straight up (north)")
    check(l.__to[2] <= up + 0.01, "no further than the route")
end
check(near(jl[1].__from[2], 0, 0.01) and near(jl[1].__to[2], 6, 0.01) and near(jl[2].__from[2], 10, 0.01), "6 on, 4 off")
check(jl[1].__color[1] == herbs.color[1] and jl[1].__thickness == 2, "the route's color, a little thinner")
-- far away (500 yards north): dashes go to the minimap's edge
yn = 500 / 1066
herbs.points = { 0.45, 0.5 - yn, 0.55, 0.5 - yn, 0.5, 0.5 - 2 * yn }
GP:Changed()
jl = Shown(GP.mm.join)
check(#jl > 0 and jl[#jl].__to[2] > 69 - 10 and jl[#jl].__to[2] <= 69.01, "a route off the minimap: up to its edge")
-- on the route: no line
yn = 10 / 1066
herbs.points = { 0.45, 0.5 - yn, 0.55, 0.5 - yn, 0.5, 0.5 - 30 * yn }
GP:Changed()
check(#Shown(GP.mm.join) == 0, "within 20 yards of the route: no line")
herbs.points = { 0.45, 0.5 - 100 / 1066, 0.55, 0.5 - 100 / 1066, 0.5, 0.5 - 300 / 1066 }
GP:Changed()
check(#Shown(GP.mm.join) > 0)
Click(ui.joinSwitch)
check(GP.db.joinLine == false and #Shown(GP.mm.join) == 0, "switched off")
GP.db.joinLine = true
GP:DrawMinimap()
check(#Shown(GP.mm.join) > 0, "back on, without forcing a redraw")
Click(ui.minimapSwitch)
check(#Shown(GP.mm.join) == 0, "minimap lines off: it goes too")
Click(ui.minimapSwitch)
PLAYER.x = 0.5 + 0.0005
GP:DrawMinimap()
check(#Shown(GP.mm.join) > 0, "follows you as you move")
PLAYER.x = 0.5
herbs.points = herbPoints2
for i, r in ipairs(GP.db.routes) do r.shown = wasShown2[i] end
GP:Changed()

---------------------------------------------------------------------------
STEP("TomTom waypoint")
do
    check(GP.NextStop(4, 4) == 1 and GP.NextStop(4, 2) == 3, "next stop goes round the loop")
    check(GP.NextStop(4, 1, true) == 4 and GP.NextStop(4, 3, true) == 2, "and the other way reversed")
    local k, d = GP.NearestStop({ 0, 100, 100 }, { 0, 0, 50 }, 3, 90, 40)
    check(k == 3 and near(d, math.sqrt(200)), "the nearest stop")

    check(GP.db.tomtom == false and ui.tomtomSwitch, "off to start, with a switch")
    check(not GP:HasTomTom(), "no TomTom here yet")
    GP:ToggleTomTom()
    check(GP.db.tomtom == false and logHas("needs the |cffffd100TomTom|r addon"), "/gpf tomtom without TomTom says so")
    GP:OpenConfig("display")
    check(ui.tomtomSwitch:GetAlpha() < 1, "greyed out without TomTom")

    -- a fake TomTom that remembers its waypoints
    local points, nextUid, removed = {}, 0, 0
    TomTom = {
        AddWaypoint = function(self, m, x, y, opts)
            nextUid = nextUid + 1
            points[nextUid] = { m = m, x = x, y = y, opts = opts }
            return nextUid
        end,
        RemoveWaypoint = function(self, uid) if points[uid] then points[uid] = nil; removed = removed + 1 end end,
    }
    local function current()
        local uid, n = nil, 0
        for u in pairs(points) do uid = u; n = n + 1 end
        check(n <= 1, "never more than one waypoint")
        return uid and points[uid]
    end
    GP:RefreshConfig()
    check(ui.tomtomSwitch:GetAlpha() == 1, "not greyed out with TomTom")

    local wasShown3 = {}
    for i, r in ipairs(GP.db.routes) do wasShown3[i] = r.shown; r.shown = (r == herbs) end
    local kept = herbs.points
    -- a square 200 x 200 yards: stops at (400, 400), (600, 400), (600, 600), (400, 600) yards
    local function P(xy, yy) return xy / 1600, yy / 1066 end
    local x1, y1 = P(400, 400); local x2, y2 = P(600, 400); local x3, y3 = P(600, 600); local x4, y4 = P(400, 600)
    herbs.points = { x1, y1, x2, y2, x3, y3, x4, y4 }
    PLAYER.x, PLAYER.y = P(380, 610)   -- by stop 4
    GP:UpdateWaypoint()
    check(current() == nil, "nothing while it's off")
    Click(ui.tomtomSwitch)
    check(GP.db.tomtom == true, "switched on")
    local wp = current()
    check(wp and wp.m == E and wp.x == x4 and wp.y == y4, "points to the nearest stop")
    check(wp.opts.title == herbs.name .. " - stop 4 of 4" and wp.opts.crazy and wp.opts.persistent == false
        and wp.opts.cleardistance == 0, "titled, with the arrow, not saved, not cleared by TomTom")
    GP:UpdateWaypoint()
    check(current() == wp and removed == 0, "left alone while you ride to it")
    PLAYER.x, PLAYER.y = P(405, 590)   -- within 20 yards of stop 4
    GP:UpdateWaypoint()
    wp = current()
    check(wp.x == x1 and wp.y == y1 and removed == 1, "arrived: moves on to the next stop round the loop")
    PLAYER.x, PLAYER.y = P(500, 400)   -- half way along
    GP:UpdateWaypoint()
    check(current() == wp, "not moved on half way there, though stop 2 is as near")
    PLAYER.x, PLAYER.y = P(410, 405)
    GP:UpdateWaypoint()
    check(current().x == x2 and current().y == y2, "then stop 2")

    GP.db.arrowsReverse = true
    PLAYER.x, PLAYER.y = P(598, 402)
    GP:UpdateWaypoint()
    check(current().x == x1 and current().y == y1, "reversed arrows: back the other way")
    GP.db.arrowsReverse = false

    -- went far off: starts again at the nearest stop
    PLAYER.x, PLAYER.y = P(400, 400)
    GP:UpdateWaypoint()   -- arrived at 1: on to 2
    check(current().x == x2)
    PLAYER.x, PLAYER.y = P(400, 900)   -- 300 yards south of stop 4, 360 from stop 2
    GP:UpdateWaypoint()
    check(current().x == x2, "not yet: stop 4 isn't half as far")
    PLAYER.x, PLAYER.y = P(380, 700)   -- stop 4 is 102 yards away, stop 2 over 300
    GP:UpdateWaypoint()
    check(current().x == x4 and current().y == y4, "lost: back to the nearest stop")

    -- a rebuilt route (stops moved) starts again
    local x5, y5 = P(390, 690)
    herbs.points = { x1, y1, x2, y2, x3, y3, x5, y5 }
    GP:UpdateWaypoint()
    check(current().y ~= y4, "the old stop is gone")
    check(current().x == x1 and current().y == y1, "within 20 yards of the new stop 4: on to stop 1")
    herbs.points = { x1, y1, x2, y2, x3, y3, x4, y4 }

    -- another zone, a hidden route, off
    PLAYER.map = W
    GP:UpdateWaypoint()
    check(current() == nil, "another zone: no waypoint")
    PLAYER.map = E
    GP:UpdateWaypoint()
    check(current() ~= nil, "back")
    GP:SetRouteShown(herbs, false)
    check(current() == nil, "route hidden: gone")
    GP:SetRouteShown(herbs, true)
    check(current() ~= nil)
    GP:ToggleTomTom()
    check(GP.db.tomtom == false and current() == nil, "/gpf tomtom turns it off")
    SlashCmdList.GATHERPATHFOREVER("tomtom")
    check(GP.db.tomtom == true and current() ~= nil, "and on")
    GP:RestoreDefaults()
    check(GP.db.tomtom == false and current() == nil, "Restore defaults turns it off")
    -- TomTom errors don't break anything
    GP.db.tomtom = true
    TomTom.AddWaypoint = function() error("boom") end
    GP:UpdateWaypoint()
    check(GP.wp and GP.wp.uid == nil, "a TomTom error is caught")
    TomTom = nil
    GP:UpdateWaypoint()
    check(GP.wp == nil, "TomTom gone: cleared")
    GP.db.tomtom = false

    herbs.points = kept
    for i, r in ipairs(GP.db.routes) do r.shown = wasShown3[i] end
    PLAYER.x, PLAYER.y = 0.5, 0.5
    GP:Changed()
end

---------------------------------------------------------------------------
STEP("HUD in the middle of the screen")
do
    check(GP.db.hud == false and GP.db.hudRotate == true and GP.db.hudNodes == true, "off to start, turning, with nodes")
    check(GP.db.hudSize == 320 and GP.db.hudYards == 150 and GP.db.hudAlpha == 60 and GP.db.hudY == 0)
    check(GP.db.hudCombat == true and GP.db.hudPicked == true and GP.db.hudPickedHide == false
        and GP.db.hudRespawn == 10, "shown in combat, picked nodes marked for 10 minutes")
    GP:Changed()
    check(not (GP.hud and GP.hud:IsShown()), "nothing on screen while it's off")
    -- a route of its own, the others hidden
    local wasShown = {}
    for i, r in ipairs(GP.db.routes) do wasShown[i] = r.shown; r.shown = false end
    local hr = { id = 999, mapID = E, name = "HUD test", shown = true, color = { 0.2, 0.4, 0.6 },
        kinds = { Mining = { ["Copper Vein"] = true } },
        points = { 0.4 + 100 / 1600, 0.4, 0.4 + 100 / 1600, 0.4 + 50 / 1066 } }
    table.insert(GP.db.routes, hr)
    PLAYER.x, PLAYER.y = 0.4, 0.4
    SlashCmdList.GATHERPATHFOREVER("hud")
    check(GP.db.hud == true and logHas("HUD on"), "/gpf hud turns it on")
    local hud = GP.hud
    check(hud and hud:IsShown(), "shown with a route in your zone")
    check(hud.__parent == UIParent, "on UIParent, not a Blizzard frame")
    local pt = hud.__points[#hud.__points]
    check(pt[1] == "CENTER" and pt[2] == UIParent and pt[4] == 0 and pt[5] == 0, "in the middle of the screen")
    check(hud.__w == 320 and near(hud:GetAlpha(), 0.6), "320 wide at 60%")
    -- 100 yards east, 150 yards to the edge of a 160 radius
    local k = 160 / 150
    local lines = Shown(hud.pool)
    check(#lines == 1, "two stops: one line")
    check(near(lines[1].__from[1], 100 * k, 0.01) and near(lines[1].__from[2], 0, 0.01), "facing north: east is right")
    check(lines[1].__color[1] == 0.2 and lines[1].__thickness == GP.db.minimapWidth, "the minimap's look")
    check(#Shown(hud.ring) == 64, "a faint ring round the edge")
    local me = Shown(hud.me)
    check(#me == 2 and me[1].__to[2] > 0 and near(me[1].__to[1], 0, 0.01), "you: an arrow pointing up")
    -- turns with you even when the minimap doesn't
    CVARS.rotateMinimap = "0"
    FACING = math.pi / 2
    Tick(0.05)
    lines = Shown(hud.pool)
    check(near(lines[1].__from[1], 0, 0.01) and near(lines[1].__from[2], -100 * k, 0.01), "facing west: east is behind you")
    me = Shown(hud.me)
    check(me[1].__to[2] > 0 and near(me[1].__to[1], 0, 0.01), "your arrow still points up")
    -- north up
    Click((function() GP:OpenConfig("hud") return ui.hudRotate end)())
    check(GP.config.currentTab == "hud" and GP.db.hudRotate == false, "the HUD tab's Turn with me switch")
    lines = Shown(hud.pool)
    check(near(lines[1].__from[1], 100 * k, 0.01) and near(lines[1].__from[2], 0, 0.01), "north up: east is right")
    me = Shown(hud.me)
    check(me[1].__to[1] < 0 and near(me[1].__to[2], 0, 0.01), "your arrow points west")
    GP.db.hudRotate = true
    FACING = 0
    -- moving redraws it
    PLAYER.x = 0.4 + 50 / 1600
    Tick(0.05)
    lines = Shown(hud.pool)
    check(near(lines[1].__from[1], 50 * k, 0.01), "follows you as you move")
    PLAYER.x = 0.4
    -- nodes: Copper Vein at 0.3,0.3 and 0.3,0.7 are in reach at 400 yards, 0.7,0.7 isn't
    GP.db.hudYards = 400
    GP:Changed()
    local dots = Shown(hud.dots)
    check(#dots == 2, "the route's nodes in reach as dots")
    local d1 = dots[1]
    check(d1.__color[1] == GP.HUD_KIND_COLORS.Mining[1] and d1.__thickness == GP.HUD_DOT, "ore colored dots")
    for _, d in ipairs(dots) do
        local x, y = (d.__from[1] + d.__to[1]) / 2, d.__from[2]
        check(math.sqrt(x * x + y * y) <= 160, "inside the HUD")
    end
    GP:SetSkipped("Copper Vein", true)
    check(#Shown(hud.dots) == 0, "skipped nodes go")
    GP:SetSkipped("Copper Vein", false)
    check(#Shown(hud.dots) == 2, "and come back")
    gm:Add(E, "Mining", 10, 0.35, 0.40)
    check(#Shown(hud.dots) == 3, "a node GatherMate2 finds shows up")
    gm:Delete(E, "Mining", 0.35, 0.40)
    check(#Shown(hud.dots) == 2, "a deleted one goes")
    for i = #hr.points, 5, -1 do hr.points[i] = nil end   -- the found node joined the route: back to two stops
    -- picked nodes: GatherMate2 adding a node where you stand means you gathered it
    local function rings() local n = 0; for _, d in ipairs(Shown(hud.dots)) do if d.__thickness == 1.5 then n = n + 1 end end return n end
    check(rings() == 0 and #GP.db.picked == 0, "nothing picked yet")
    PLAYER.x, PLAYER.y = 0.3, 0.3
    local now = time()
    local two = { unpack(hr.points) }
    gm:Delete(E, "Mining", 0.3, 0.3)
    gm:Add(E, "Mining", 10, 0.3, 0.3)
    hr.points = { unpack(two) }   -- it may have joined the route: back to two stops
    PLAYER.x, PLAYER.y = 0.4, 0.4
    GP:Changed()
    check(#GP.db.picked == 1 and GP.db.picked[1][1] == E and GP.db.picked[1][4] == "Mining", "picking it is remembered")
    check(rings() == GP.HUD_PICKED_SIDES and #Shown(hud.dots) == 1 + GP.HUD_PICKED_SIDES,
        "the picked node is an empty ring, the other a dot")
    -- a node someone else shares from far away isn't one you picked
    gm:Add(E, "Mining", 10, 0.36, 0.40)
    check(#GP.db.picked == 1, "a node added away from you isn't picked")
    gm:Delete(E, "Mining", 0.36, 0.40)
    hr.points = { unpack(two) }
    -- hidden instead
    Click((function() GP:OpenConfig("hud") return ui.hudPickedHide end)())
    check(GP.db.hudPickedHide == true and rings() == 0 and #Shown(hud.dots) == 1, "Hide picked nodes")
    Click(ui.hudPickedHide)
    -- marks off
    Click(ui.hudPicked)
    check(GP.db.hudPicked == false and rings() == 0 and #Shown(hud.dots) == 2, "Mark picked nodes off: plain dots")
    Click(ui.hudPicked)
    check(rings() == GP.HUD_PICKED_SIDES)
    -- the mark runs out after the respawn time
    FAKE_CLOCK = now + 9 * 60
    Tick(0.05)
    check(rings() == GP.HUD_PICKED_SIDES, "still picked after 9 minutes")
    FAKE_CLOCK = now + 10 * 60 + 1
    Tick(0.05)
    check(rings() == 0 and #Shown(hud.dots) == 2 and #GP.db.picked == 0, "back to a dot after 10")
    -- kept over a reload, junk dropped
    GatherPathForeverDB.picked = { { E, 0.3, 0.3, "Mining", FAKE_CLOCK }, { "x" }, 5 }
    GP:LoadSettings()
    check(#GP.db.picked == 1, "saved marks load, broken ones are dropped")
    GP.db.picked = {}
    GP:Changed()
    -- the same vein saved twice in one place is one dot
    check(#Shown(hud.dots) == 2)
    gm:Add(E, "Mining", 10, 0.3 + 5 / 1600, 0.3)
    hr.points = { unpack(two) }
    GP:Changed()
    check(#Shown(hud.dots) == 2, "a duplicate 5 yards away: still one dot")
    gm:Add(E, "Mining", 11, 0.3 + 5 / 1600, 0.3 + 5 / 1066, true)   -- Tin there is another node
    hr.kinds.Mining["Tin Vein"] = true
    GP.nodeVersion = GP.nodeVersion + 1
    GP:Changed()
    check(#Shown(hud.dots) == 3, "a different kind in the same place keeps its own dot")
    hr.kinds.Mining["Tin Vein"] = nil
    gm.gmdbs.Mining[E][gm:EncodeLoc(0.3 + 5 / 1600, 0.3 + 5 / 1066)] = nil
    -- Combine duplicate nodes runs GatherMate2's own cleanup; its deletes don't take stops out of routes
    local cleaned, running = 0, false
    gm.IsCleanupRunning = function() return running end
    gm.CleanupDB = function(self)
        cleaned = cleaned + 1
        running = true
        local stops = #hr.points
        hr.sight = 0
        hr.points[#hr.points + 1] = 0.3 + 5 / 1600; hr.points[#hr.points + 1] = 0.3
        self:Delete(E, "Mining", 0.3 + 5 / 1600, 0.3)
        check(#hr.points == stops + 2, "a duplicate GatherMate2 removes keeps its route stop")
        running = false
        self:Send("GatherMate2Cleanup")
    end
    Click((function() GP:OpenConfig("display") return ui.combine end)())
    check(cleaned == 0, "asks first")
    Click(GP.confirmWindow.yes)
    check(cleaned == 1 and logHas("duplicate nodes combined") and not GP.combining, "Combine runs GatherMate2's cleanup")
    SlashCmdList.GATHERPATHFOREVER("combine")
    check(cleaned == 2, "/gpf combine")
    hr.sight = nil
    hr.points = { unpack(two) }
    gm.CleanupDB = function() error("boom") end
    check(GP:CombineDuplicates() == false and not GP.combining and logHas("couldn't combine"), "a GatherMate2 error is caught")
    gm.CleanupDB, gm.IsCleanupRunning = nil, nil
    check(GP:CombineDuplicates() == false, "an old GatherMate2 without it")
    GP:Changed()
    Click(ui.hudNodes)
    check(GP.db.hudNodes == false and #Shown(hud.dots) == 0, "Show nodes off")
    Click(ui.hudNodes)
    -- zoomed in, the line is cut at the edge
    GP.db.hudYards = 50
    GP:Changed()
    lines = Shown(hud.pool)
    check(#lines == 0 and #Shown(hud.dots) == 0, "100 yards away is off a 50 yard HUD")
    GP.db.hudYards = 150
    -- size, height and opacity
    GP.db.hudSize, GP.db.hudY, GP.db.hudAlpha = 400, -120, 30
    GP:Changed()
    pt = hud.__points[#hud.__points]
    check(hud.__w == 400 and pt[5] == -120 and near(hud:GetAlpha(), 0.3), "bigger, lower, fainter")
    lines = Shown(hud.pool)
    check(near(lines[1].__from[1], 100 * 200 / 150, 0.01), "same yards, more pixels")
    GP.db.hudSize, GP.db.hudY, GP.db.hudAlpha = 320, 0, 60
    -- arrows need 3 stops
    hr.points = { 0.4 + 60 / 1600, 0.4, 0.4 + 60 / 1600, 0.4 + 60 / 1066, 0.4 - 60 / 1600, 0.4 + 60 / 1066 }
    GP:Changed()
    check(#Shown(hud.arrows) > 0, "direction arrows on the HUD")
    GP.db.arrows = false
    GP:Changed()
    check(#Shown(hud.arrows) == 0, "not with arrows off")
    GP.db.arrows = true
    -- line to the route: far from it
    hr.points = { 0.4 + 100 / 1600, 0.4, 0.4 + 100 / 1600, 0.4 + 50 / 1066 }
    GP:Changed()
    check(#Shown(hud.join) > 0, "dashes toward the route")
    -- combat: stays up, unless Show in combat is off
    IN_COMBAT = true
    FireEvent("PLAYER_REGEN_DISABLED")
    check(hud:IsShown(), "shown in combat")
    Click(ui.hudCombat)
    check(GP.db.hudCombat == false and not hud:IsShown(), "Show in combat off: hidden in combat")
    IN_COMBAT = false
    FireEvent("PLAYER_REGEN_ENABLED")
    check(hud:IsShown(), "back after")
    Click(ui.hudCombat)
    check(GP.db.hudCombat == true)
    -- flights, other zones
    UnitOnTaxi = function() return true end
    GP:Changed()
    check(not hud:IsShown(), "hidden on a flight")
    UnitOnTaxi = nil
    PLAYER.map = W
    GP:Changed()
    check(not hud:IsShown(), "hidden with no route in your zone")
    PLAYER.map = E
    hr.shown = false
    GP:Changed()
    check(not hud:IsShown(), "hidden with the route hidden")
    hr.shown = true
    GP:Changed()
    check(hud:IsShown())
    -- off from the tab, and /gpf hud
    Click(ui.hudSwitch)
    check(GP.db.hud == false and not hud:IsShown(), "Show the HUD off")
    SlashCmdList.GATHERPATHFOREVER("hud")
    check(GP.db.hud == true and hud:IsShown())
    -- the key binding
    check(BINDING_HEADER_GATHERPATHFOREVER == "GatherPath Forever" and BINDING_NAME_GATHERPATHFOREVER_HUD ~= nil,
        "names in the Key Bindings menu")
    local xml = assert(io.open("Bindings.xml")):read("*a")
    check(xml:find('name="GATHERPATHFOREVER_HUD"', 1, true) and xml:find("GatherPathForever_ToggleHud()", 1, true),
        "Bindings.xml calls the toggle")
    GatherPathForever_ToggleHud()
    check(GP.db.hud == false and not hud:IsShown() and logHas("HUD off"), "the key turns it off")
    GatherPathForever_ToggleHud()
    check(GP.db.hud == true and hud:IsShown(), "and on")
    GP.db.hudCombat, GP.db.hudPicked, GP.db.hudPickedHide, GP.db.hudRespawn = false, false, true, 25
    GP:RestoreDefaults()
    check(GP.db.hudCombat == true and GP.db.hudPicked == true and GP.db.hudPickedHide == false
        and GP.db.hudRespawn == 10, "Restore defaults puts the new HUD settings back")
    check(GP.db.hud == false and not hud:IsShown(), "Restore defaults turns it off")
    -- tidy up
    table.remove(GP.db.routes)
    for i, r in ipairs(GP.db.routes) do r.shown = wasShown[i] end
    PLAYER.x, PLAYER.y = 0.5, 0.5
    GP:Changed()
end

---------------------------------------------------------------------------
STEP("timed runs")
do
    local speedWas = GP.db.speed
    GP.db.speed = 1.5   -- 1.5 yards a second: 5 minutes is 450 yards
    -- the slider on New route
    GP:OpenConfig("new")
    Click(ui.myZone)
    check(ui.minutesSlider and ui.minutesSlider:GetValue() == 0, "Lap time starts on the whole zone")
    check(ui.minutesSlider.valueText:GetText() == "Whole zone")
    Click(SwitchFor("Peacebloom"))
    Click(SwitchFor("Silverleaf"))
    ui.sightSlider:SetValue(0)
    ui.minutesSlider:SetValue(5)
    check(ui.minutesSlider.valueText:GetText() == "5 min")
    ui.newName:SetText("Short run")
    Click(ui.makeButton)
    RunJobs()
    local run
    for _, r in ipairs(GP.db.routes) do if r.name == "Short run" then run = r end end
    check(run and run.minutes == 5, "made with its time")
    local total = #GP:CollectNodes(E, run.kinds)
    check(run.allNodes == total and run.nodes >= 3 and run.nodes < total, "some of the nodes, not all")
    check(run.length <= 450 + 1, "a lap fits 5 minutes")
    check(logHas("A 5 min run: the busiest " .. run.nodes .. " of " .. total .. " nodes."), "chat says so")
    GP:OpenConfig("routes")
    -- New route opens blank again, Edit fills it in
    GP:OpenConfig("new")
    check(ui.minutesSlider:GetValue() == 0, "blank again")
    GP:EditRouteInWindow(run)
    check(ui.minutesSlider:GetValue() == 5, "Edit shows its time")
    -- more time: more nodes
    ui.minutesSlider:SetValue(20)
    Click(ui.makeButton)
    RunJobs()
    check(run.minutes == 20 and run.nodes == total and run.allNodes == total, "20 minutes: every node fits")
    local whole = run.length
    -- back to the whole zone
    GP:EditRouteInWindow(run)
    ui.minutesSlider:SetValue(0)
    Click(ui.makeButton)
    RunJobs()
    check(run.minutes == nil and run.allNodes == nil and run.nodes == total, "Whole zone: no time")
    check(near(run.length, whole, 1), "the same loop as a long enough timed one")
    -- rebuild keeps the time
    GP:EditRoute(run, { kinds = run.kinds, name = run.name, sight = 0, minutes = 5 })
    RunJobs()
    local n5 = run.nodes
    GP:RebuildRoute(run)
    RunJobs()
    check(run.minutes == 5 and run.nodes == n5 and run.length <= 451, "Rebuild keeps it a 5 min run")
    -- new nodes don't stretch a timed run
    local before = #run.points
    gm:Add(E, "Herb Gathering", 1, 0.405, 0.30)
    check(#run.points == before, "a node found later waits for Rebuild")
    gm:Delete(E, "Herb Gathering", 0.405, 0.30)
    -- a failed edit puts the time back
    local kinds = run.kinds
    GP:EditRoute(run, { kinds = { Mining = { ["Tin Vein"] = true } }, name = run.name, sight = 0, minutes = 0 })
    RunJobs()
    check(run.minutes == 5 and run.kinds == kinds, "no loop: the route stays a 5 min run")
    -- the Routes row says so
    GP:OpenConfig("routes")
    local found = false
    for _, row in ipairs(ui.routeRows or {}) do
        local t = row.info and row.info:GetText() or ""
        if t:find("(5 min run)", 1, true) then found = true end
    end
    check(found, "the row shows (5 min run)")
    GP:DeleteRoute(run)
    GP.db.speed = speedWas
    GP:Changed()
end

---------------------------------------------------------------------------
STEP("taboo areas")
do
    local r1 = GP.db.routes[1]
    local kept = { points = { unpack(r1.points) }, nodes = r1.nodes, length = r1.length, kinds = r1.kinds, sight = r1.sight }
    -- a route to every Peacebloom and Silverleaf, straight through the middle
    r1.kinds, r1.sight = { ["Herb Gathering"] = { Peacebloom = true, Silverleaf = true } }, 0
    check(GP:RebuildRoute(r1))
    RunJobs()
    local before = r1.nodes
    local function legsThrough(route, mapID)
        local walls = GP.WallsFor(mapID)
        local w, h = GP:MapYards(mapID)
        local p, n, bad = route.points, GP:NodeCount(route), 0
        for i = 1, n do
            local j = i % n + 1
            if walls:Blocked({ p[2 * i - 1] * w, p[2 * i] * h }, { p[2 * j - 1] * w, p[2 * j] * h }) then bad = bad + 1 end
        end
        return bad
    end

    -- the window: a Taboo areas tab
    GP:OpenConfig("taboo")
    check(GP.config.currentTab == "taboo" and ui.tabooZone.getter() == E, "a Taboo areas tab, on your zone")
    check(ui.tabooEmpty:GetText():find("No taboo areas in Elwynn Forest", 1, true), "none yet")
    check(ui.tabooShow:IsOn(), "shown on the world map to start")

    -- draw one: a band down the middle, over the Peacebloom at 0.5, 0.4
    IN_COMBAT = true
    check(not GP:StartTaboo(E) and logHas("in combat"), "not in combat")
    IN_COMBAT = false
    Click(ui.tabooDraw)
    check(GP.drawing and GP.drawing.mapID == E, "drawing in Elwynn")
    check(WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == E, "on the world map, on that zone")
    check(not GP.config:IsShown(), "the window gets out of the way")
    check(GP.drawBar:IsShown() and GP.drawBar.finish.disabled, "a bar on the map; Finish waits for 3 corners")
    check(ClickMap("LeftButton", 0.47, 0.30) and ClickMap("LeftButton", 0.53, 0.30), "left-clicks are corners")
    check(GP.drawBar.title:GetText():find("2 corners", 1, true))
    check(ClickMap("LeftButton", 0.9, 0.9) and ClickMap("RightButton"), "right-click takes the last one back")
    check(#GP.drawing.pts == 4)
    ClickMap("LeftButton", 0.53, 0.58)
    ClickMap("LeftButton", 0.47, 0.58)
    check(not GP.drawBar.finish.disabled and GP.drawBar.title:GetText():find("4 corners", 1, true), "Finish with 3 or more")
    check(#Shown(GP.provider.pin.draft) >= 3, "the corners so far are drawn, on to the cursor")
    WorldMapFrame:SetMapID(W)
    check(not ClickMap("LeftButton", 0.2, 0.2), "on another map clicks work as usual")
    check(GP.drawBar.help:GetText():find("Go back to Elwynn Forest", 1, true), "and the bar says where to go")
    WorldMapFrame:SetMapID(E)
    Click(GP.drawBar.finish)
    check(not GP.drawing and not GP.drawBar:IsShown() and #(WorldMapFrame.__clickHandlers or {}) == 0,
        "Finish keeps it and stops taking clicks")
    check(#GP:Taboos(E) == 1 and #GP:Taboos(E)[1] == 8, "saved with its 4 corners")
    check(GP.config:IsShown() and GP.config.currentTab == "taboo", "back on the Taboo areas tab")
    check(ui.tabooRows[1]:IsShown() and ui.tabooRows[1].text:GetText():find("Area 1", 1, true)
        and ui.tabooRows[1].text:GetText():find("4 corners, about 96 x 298 yards", 1, true), "listed with its size")
    check(GP:Busy() or #(GP.queue or {}) > 0, "the zone's routes are worked out again")
    RunJobs()
    check(r1.nodes == before - 1 and r1.taboo == 1, "the node inside is left out")
    check(logHas("1 node in taboo areas left out"), "and chat says so")
    check(legsThrough(r1, E) == 0, "no leg goes through the area")
    check(GP:NodeCount(r1) > r1.nodes, "it bends round its corners instead")
    check(GP:InTaboo(E, 0.5, 0.45) and not GP:InTaboo(E, 0.4, 0.45) and not GP:InTaboo(W, 0.5, 0.45))
    check(near(r1.length, GP:RouteLength(r1)), "the length is the way round")

    -- on the world map: outline and hatching
    GP:DrawWorldMap()
    local hatch = #Shown(GP.provider.pin.taboo)
    check(hatch > 4, "drawn red and hatched on the world map (" .. hatch .. " lines)")
    Click(ui.tabooShow)
    check(not GP.db.tabooShow and #Shown(GP.provider.pin.taboo) == 0, "or not")
    Click(ui.tabooShow)
    local spans = GP.HatchSpans({ 0, 100, 100, 0 }, { 0, 0, -100, -100 }, 4, 10)
    check(#spans >= 18, "hatch lines across a square")
    for _, sp in ipairs(spans) do
        check(sp[1] >= -0.01 and sp[3] <= 100.01 and near(sp[1] + sp[2], sp[3] + sp[4]), "inside it, on the diagonal")
    end

    -- nodes found later
    local stops = GP:NodeCount(r1)
    gm:Add(E, "Herb Gathering", 1, 0.50, 0.50)
    check(GP:NodeCount(r1) == stops, "a node found inside an area doesn't join")
    gm:Add(E, "Herb Gathering", 1, 0.56, 0.35)
    check(GP:NodeCount(r1) > stops and legsThrough(r1, E) == 0, "one outside does, going round")
    gm:Delete(E, "Herb Gathering", 0.56, 0.35)
    check(legsThrough(r1, E) == 0, "and when it's deleted the line still goes round")
    gm:Delete(E, "Herb Gathering", 0.50, 0.50)

    -- a node deleted between two stops on either side: they meet round the area
    local hand = { id = 900, mapID = E, name = "By hand", kinds = { ["Herb Gathering"] = { Peacebloom = true } }, sight = 0,
        color = { 1, 1, 1 }, shown = true, points = { 0.30, 0.45, 0.50, 0.75, 0.70, 0.45, 0.50, 0.15 } }
    table.insert(GP.db.routes, hand)
    check(legsThrough(hand, E) == 0, "(clear to start)")
    gm:Add(E, "Herb Gathering", 1, 0.50, 0.75, true)
    gm:Delete(E, "Herb Gathering", 0.50, 0.75)
    check(GP:NodeCount(hand) > 3 and legsThrough(hand, E) == 0, "a deleted node's neighbours meet round the area")
    -- a new node whose cheapest place is across the area: its leg bends round too
    hand.points = { 0.30, 0.45, 0.50, 0.15 }
    gm:Add(E, "Herb Gathering", 1, 0.70, 0.50)
    check(GP:NodeCount(hand) > 3 and legsThrough(hand, E) == 0, "a new node's legs go round the area")
    gm:Delete(E, "Herb Gathering", 0.70, 0.50)
    GP:DeleteRoute(hand)

    -- one whose edges cross is turned down; Cancel keeps nothing
    check(not GP:AddTaboo(E, { 0.1, 0.1, 0.2, 0.2, 0.2, 0.1, 0.1, 0.2 }) and logHas("edges cross"), "a bow tie isn't an area")
    check(not GP:AddTaboo(E, { 0.1, 0.1, 0.2, 0.2 }), "nor 2 corners")
    GP:StartTaboo(E)
    ClickMap("LeftButton", 0.1, 0.1); ClickMap("LeftButton", 0.2, 0.1); ClickMap("LeftButton", 0.2, 0.2)
    Click(GP.drawBar.cancel)
    check(not GP.drawing and #GP:Taboos(E) == 1 and #(WorldMapFrame.__clickHandlers or {}) == 0, "Cancel keeps nothing")
    check(not ClickMap("RightButton"), "right-click on the map zooms out again")

    -- saved, and junk dropped
    GatherPathForeverDB.taboos[99] = { { 0.1, 0.1 }, "junk", { 0.1, 0.1, 0.2, "x", 0.3, 0.3 } }
    GatherPathForeverDB.taboos.junk = { { 0.1, 0.1, 0.2, 0.1, 0.2, 0.2 } }
    GP:LoadSettings()
    check(#GP:Taboos(E) == 1 and GP.db.taboos[99] == nil and GP.db.taboos.junk == nil, "the area comes back, junk doesn't")

    -- delete it from the tab
    GP:OpenConfig("taboo")
    Click(ui.tabooRows[1].del)
    check(GP.confirmWindow:IsShown())
    Click(GP.confirmWindow.yes)
    check(#GP:Taboos(E) == 0 and GP.db.taboos[E] == nil, "deleted")
    RunJobs()
    check(r1.nodes == before and (r1.taboo or 0) == 0, "and the route takes the node in again")
    check(not ui.tabooRows[1]:IsShown() and ui.tabooEmpty:GetText():find("No taboo areas", 1, true))

    r1.points, r1.nodes, r1.length, r1.kinds, r1.sight, r1.taboo = kept.points, kept.nodes, kept.length, kept.kinds, kept.sight, nil
    GP:OpenConfig("routes")
end

---------------------------------------------------------------------------
STEP("minimap test (/gpf scantest)")
do
    local names = GP.TooltipNames("|TInterface\\Minimap\\Up:0|t |cffffffffSilverleaf|r\n Copper Vein \n\n")
    check(#names == 2 and names[1] == "Silverleaf" and names[2] == "Copper Vein", "icons, colors and spaces stripped")
    check(#GP.TooltipNames(nil) == 0)
    -- a fake minimap: 140 wide at (500, 400), 200 yards to its edge; Copper Vein 20 px east, someone 30 px north
    local saved = {}
    for _, k in ipairs({ "UpdateMouseoverAtPoint", "SetUsingSoftCursor", "GetCenter", "GetEffectiveScale", "IsMouseOver" }) do
        saved[k] = rawget(Minimap, k)
    end
    local hover, soft, calls = nil, nil, 0
    Minimap.GetCenter = function() return 500, 400 end
    Minimap.GetEffectiveScale = function() return 1 end
    Minimap.IsMouseOver = function() return false end
    Minimap.SetUsingSoftCursor = function(_, on) soft = on end
    Minimap.UpdateMouseoverAtPoint = function(_, x, y) hover = { x, y }; calls = calls + 1 end
    local oldRadius = C_Minimap.GetViewRadius
    C_Minimap.GetViewRadius = function() return 200 end
    local wasShown = Minimap.__shown
    Minimap:Show()
    C_TooltipInfo = { GetMinimapMouseover = function()
        local dx, dy = hover[1] - 500, hover[2] - 400
        if math.abs(dx - 20) <= 4 and math.abs(dy) <= 4 then
            return { type = 1, lines = { { leftText = "|cffffffffCopper Vein|r" } } }
        elseif math.abs(dx) <= 2 and math.abs(dy - 30) <= 2 then
            return { lines = { { leftText = "Someone" } } }
        end
    end }
    PLAYER.map = E
    check(GP:ScanTest() == "works", "finds a node GatherMate2 knows")
    check(logHas("Copper Vein (57 yd)") and logHas("it works"), "named, with how far")
    check(soft == false and hover[1] == -10000, "soft cursor and the hover point put back")
    check(calls > 900, "a grid over the whole minimap")
    -- only other things
    local real = C_TooltipInfo.GetMinimapMouseover
    C_TooltipInfo.GetMinimapMouseover = function()
        local d = real()
        if d and d.type then return nil end
        return d
    end
    check(GP:ScanTest() == "answers" and logHas("none of those are herb or ore"), "answers, but no nodes")
    C_TooltipInfo.GetMinimapMouseover = function() return nil end
    check(GP:ScanTest() == "nothing" and logHas("isn't letting addons read it"), "nothing answers")
    C_TooltipInfo.GetMinimapMouseover = function() error("blocked") end
    check(GP:ScanTest() == "nothing" and logHas("errors"), "errors are caught")
    Minimap.UpdateMouseoverAtPoint = function() error("blocked") end
    check(GP:ScanTest() == "nothing" and soft == false, "a blocked probe is caught")
    Minimap.UpdateMouseoverAtPoint = function(_, x, y) hover = { x, y } end
    Minimap.IsMouseOver = function() return true end
    check(GP:ScanTest() == "mouse", "not with the mouse on the minimap")
    Minimap.IsMouseOver = function() return false end
    IN_COMBAT = true
    check(GP:ScanTest() == "combat", "not in combat")
    IN_COMBAT = false
    C_TooltipInfo = nil
    SlashCmdList.GATHERPATHFOREVER("scantest")
    check(logHas("no way for addons to read the minimap"), "/gpf scantest on a client without it")
    for k, v in pairs(saved) do Minimap[k] = v end
    for _, k in ipairs({ "UpdateMouseoverAtPoint", "SetUsingSoftCursor", "GetCenter", "GetEffectiveScale", "IsMouseOver" }) do
        if saved[k] == nil then rawset(Minimap, k, nil) end
    end
    C_Minimap.GetViewRadius = oldRadius
    if not wasShown then Minimap:Hide() end
end

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
check(GP.db.sight == GP.DEFAULTS.sight, "1.1.0's 50 yards becomes the default")
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
GP.db.routes[1].minutes, GP.db.routes[1].allNodes = 10, 40
GP:LoadSettings()
check(GP.db.routes[1].minutes == 10 and GP.db.routes[1].allNodes == 40, "a timed run keeps its time")
GP.db.routes[1].minutes = "junk"
GP:LoadSettings()
check(GP.db.routes[1].minutes == nil and GP.db.routes[1].allNodes == nil, "a broken time: the whole zone")

STEP("without GatherMate2")
GatherMate2 = nil
check(not GP:HasGatherMate())
check(GP:NewRoute({ mapID = E, kinds = { Mining = { ["Copper Vein"] = true } } }) == nil and logHas("needs GatherMate2"))
GP:OpenConfig("new")
check(#GP:ZoneNodes(E) == 0)
GP:OpenConfig("routes")
check(GP:NodeCount(GP.db.routes[1]) == 9, "routes already made still work")

LOG[#LOG + 1] = "PASSED"
