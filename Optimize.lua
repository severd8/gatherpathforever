-- GatherPath Forever: finding the shortest loop through a set of nodes.
-- Plain Lua with no game calls, so the tests can run it as it is.
--
-- A point is { x, y } in yards. A tour is a list of point numbers, visited in
-- that order and back to the first. Long jobs call O.Pause() now and then;
-- in the game that hands the rest of the work to the next frame (Core.lua
-- runs it in a coroutine), in the tests it does nothing.

local _, ns = ...
ns = ns or {}
local O = {}
ns.Optimize = O

local sqrt = math.sqrt
local EPS = 1e-6

-- Called every few thousand steps. Core.lua replaces it with a yield.
function O.Pause() end

local work = 0
local function Step(n)
    work = work + n
    if work >= 4000 then
        work = 0
        O.Pause()
    end
end

local function Dist(a, b)
    local dx, dy = a[1] - b[1], a[2] - b[2]
    return sqrt(dx * dx + dy * dy)
end
O.Dist = Dist

-- The length of a tour, back to the start
function O.Length(points, tour)
    local n = #tour
    if n < 2 then return 0 end
    local total = 0
    for i = 1, n do
        total = total + Dist(points[tour[i]], points[tour[i % n + 1]])
    end
    return total
end

-- Nodes near each other become one spot (Shortcut uses it, so the solver has
-- far fewer points to work with). Each group is the nodes within `radius` of
-- the first one not yet in a group; its spot is their middle, or that first
-- node if the middle would leave one further than `radius` away. So every node
-- is within `radius` of its spot. Returns the spots; each has .count (nodes in
-- it) and .reach (yards to its furthest node).
function O.Group(points, radius)
    local out = {}
    if not radius or radius <= 0 then
        for i, p in ipairs(points) do out[i] = { p[1], p[2], count = 1, reach = 0 } end
        return out
    end
    local used = {}
    for i, p in ipairs(points) do
        if not used[i] then
            used[i] = true
            local group = { p }
            for j = i + 1, #points do
                if not used[j] and Dist(p, points[j]) <= radius then
                    used[j] = true
                    group[#group + 1] = points[j]
                end
            end
            Step(#points)
            local sx, sy = 0, 0
            for _, q in ipairs(group) do sx, sy = sx + q[1], sy + q[2] end
            local spot = { sx / #group, sy / #group }
            local function Reach(c)
                local r = 0
                for _, q in ipairs(group) do r = math.max(r, Dist(c, q)) end
                return r
            end
            local reach = Reach(spot)
            if reach > radius then spot, reach = { p[1], p[2] }, Reach(p) end
            spot.count, spot.reach = #group, reach
            out[#out + 1] = spot
        end
    end
    return out
end

-- Start with the closest unvisited node each time
local function Nearest(points)
    local n = #points
    local tour, used = { 1 }, { [1] = true }
    local cur = 1
    for _ = 2, n do
        local best, bestD = nil, math.huge
        local cp = points[cur]
        for j = 1, n do
            if not used[j] then
                local d = Dist(cp, points[j])
                if d < bestD then best, bestD = j, d end
            end
        end
        Step(n)
        used[best] = true
        tour[#tour + 1] = best
        cur = best
    end
    return tour
end

local function Reverse(tour, i, j)
    while i < j do
        tour[i], tour[j] = tour[j], tour[i]
        i, j = i + 1, j - 1
    end
end

-- Untangle: wherever two legs cross (a-b ... c-d), reconnect them as a-c and
-- b-d by turning the stretch between round. True if anything got shorter.
local function TwoOpt(points, tour)
    local n = #tour
    local better = false
    for i = 1, n - 2 do
        local a, b = points[tour[i]], points[tour[i + 1]]
        local ab = Dist(a, b)
        for j = i + 2, n do
            if not (i == 1 and j == n) then
                local c, d = points[tour[j]], points[tour[j % n + 1]]
                local delta = Dist(a, c) + Dist(b, d) - ab - Dist(c, d)
                if delta < -EPS then
                    Reverse(tour, i + 1, j)
                    better = true
                    b = points[tour[i + 1]]
                    ab = Dist(a, b)
                end
            end
        end
        Step(n)
    end
    return better
end

-- Move a run of 1 to 3 nodes to the place in the loop where it costs least
-- (either way round). True if anything got shorter.
local function OrOpt(points, tour)
    local better = false
    for len = 1, 3 do
        local i = 1
        while i <= #tour do
            local n = #tour
            if n < len + 3 then return better end
            local first, last = i, i + len - 1
            if last > n then break end
            local prev = tour[first == 1 and n or first - 1]
            local nxt = tour[last == n and 1 or last + 1]
            local s1, sL = tour[first], tour[last]
            local P, S1, SL, N = points[prev], points[s1], points[sL], points[nxt]
            local gain = Dist(P, S1) + Dist(SL, N) - Dist(P, N)
            local bestCost, bestAt, bestFlip = gain - EPS, nil, false
            for k = 1, n do
                local kn = k % n + 1
                -- the leg tour[k] -> tour[kn], outside the run and not the gap it leaves
                local inside = (k >= first and k <= last) or (kn >= first and kn <= last)
                if not inside and tour[k] ~= prev then
                    local U, V = points[tour[k]], points[tour[kn]]
                    local uv = Dist(U, V)
                    local c1 = Dist(U, S1) + Dist(SL, V) - uv
                    local c2 = Dist(U, SL) + Dist(S1, V) - uv
                    if c1 < bestCost then bestCost, bestAt, bestFlip = c1, k, false end
                    if c2 < bestCost then bestCost, bestAt, bestFlip = c2, k, true end
                end
            end
            Step(n)
            if bestAt then
                local run = {}
                for k = first, last do run[#run + 1] = tour[k] end
                if bestFlip then
                    for a = 1, math.floor(#run / 2) do run[a], run[#run - a + 1] = run[#run - a + 1], run[a] end
                end
                local after = tour[bestAt]   -- the node the run goes in after
                for _ = first, last do table.remove(tour, first) end
                local at
                for k = 1, #tour do if tour[k] == after then at = k break end end
                for a = #run, 1, -1 do table.insert(tour, at + 1, run[a]) end
                better = true
            else
                i = i + 1
            end
        end
    end
    return better
end

-- 2-opt and Or-opt until neither finds anything shorter
local function Improve(points, tour, maxRounds)
    if #tour <= 3 then return tour end
    for _ = 1, maxRounds or 60 do
        local a = TwoOpt(points, tour)
        local b = OrOpt(points, tour)
        if not (a or b) then break end
    end
    return tour
end

-- The shortest loop it can find through the points. Returns the tour.
function O.Solve(points, maxRounds)
    local n = #points
    local tour = {}
    if n <= 3 then
        for i = 1, n do tour[i] = i end
        return tour
    end
    return Improve(points, Nearest(points), maxRounds)
end

-- The point of the segment a-b closest to c
local function Closest(a, b, c)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len2 = dx * dx + dy * dy
    if len2 < EPS then return { a[1], a[2] } end
    local t = ((c[1] - a[1]) * dx + (c[2] - a[2]) * dy) / len2
    t = t < 0 and 0 or (t > 1 and 1 or t)
    return { a[1] + t * dx, a[2] + t * dy }
end
O.Closest = Closest

-- How far c is from the segment a-b
function O.SegDist(a, b, c) return Dist(c, Closest(a, b, c)) end

-- Where to walk past node c, coming from a and going on to b, when you only
-- need to get within `radius` of it: the spot that far from c with the
-- shortest a -> spot -> b. On the straight line a-b if that passes close enough.
function O.Place(a, b, c, radius)
    local q = Closest(a, b, c)
    local d = Dist(q, c)
    if d <= radius then return q end
    local function At(t)
        return { c[1] + radius * math.cos(t), c[2] + radius * math.sin(t) }
    end
    local function Cost(t)
        local p = At(t)
        return Dist(a, p) + Dist(p, b)
    end
    -- search the half of the circle facing the line (golden section)
    local t0 = math.atan2(q[2] - c[2], q[1] - c[1])
    local lo, hi = t0 - math.pi / 2, t0 + math.pi / 2
    local g = (sqrt(5) - 1) / 2
    local x1, x2 = hi - g * (hi - lo), lo + g * (hi - lo)
    local f1, f2 = Cost(x1), Cost(x2)
    for _ = 1, 24 do
        if f1 < f2 then
            hi, x2, f2 = x2, x1, f1
            x1 = hi - g * (hi - lo)
            f1 = Cost(x1)
        else
            lo, x1, f1 = x1, x2, f2
            x2 = lo + g * (hi - lo)
            f2 = Cost(x2)
        end
    end
    local best = f1 < f2 and x1 or x2
    if Cost(t0) <= Cost(best) then best = t0 end
    return At(best)
end

-- The route only has to pass within `radius` yards of each node (you can see
-- it on the minimap from there with Find Herbs or Find Minerals). Groups the
-- nodes within half of it (O.Group), then starts from the loop through the
-- groups, slides each stop towards the line between its neighbours (never so
-- far from its group that a node in it is more than `radius` away: a lone node
-- gets all of it), finds the best order again, and drops
-- stops that end up on a straight line. Grouping first makes routes about a
-- quarter shorter on clustered nodes, and the work several times quicker.
-- Returns the stops in loop order, { x, y }.
function O.Shortcut(nodes, radius, maxRounds)
    if radius and radius > 0 then
        local groups = O.Group(nodes, radius / 2)
        nodes = (#groups >= 2 or #nodes < 2) and groups or O.Group(nodes, 0)   -- a loop needs 2 stops
    end
    local tour = O.Solve(nodes, maxRounds)
    local stops = {}
    for i, k in ipairs(tour) do stops[i] = { nodes[k][1], nodes[k][2], node = nodes[k] } end
    if not radius or radius <= 0 or #stops < 3 then return stops end
    for _ = 1, 4 do
        local n = #stops
        local order = {}
        for i = 1, n do order[i] = i end
        for _ = 1, 40 do
            local moved = 0
            for i = 1, n do
                local a, s, b = stops[order[i == 1 and n or i - 1]], stops[order[i]], stops[order[i % n + 1]]
                local before = Dist(a, s) + Dist(s, b)
                local p = O.Place(a, b, s.node, radius - (s.node.reach or 0))
                if Dist(a, p) + Dist(p, b) < before - EPS then
                    moved = math.max(moved, Dist(p, s))
                    s[1], s[2] = p[1], p[2]
                end
            end
            Step(n * 8)
            if moved < 0.1 then break end
        end
        local again = {}
        for i = 1, n do again[i] = stops[order[i]] end
        stops = again
        for i = 1, n do order[i] = i end
        local before = O.Length(stops, order)
        Improve(stops, order, maxRounds)
        local reordered = {}
        for i = 1, n do reordered[i] = stops[order[i]] end
        stops = reordered
        if O.Length(stops, order) > before - 0.1 then break end
    end
    -- stops on the straight line between their neighbours aren't needed
    local i = 1
    while i <= #stops and #stops > 2 do
        local n = #stops
        local a, b = stops[i == 1 and n or i - 1], stops[i % n + 1]
        if O.SegDist(a, b, stops[i]) < 0.3 then
            table.remove(stops, i)
        else
            i = i + 1
        end
    end
    return stops
end

-- Where a new point costs least to add to a tour: it goes after tour[at].
-- Returns at and the yards it adds.
function O.BestInsert(points, tour, p)
    local n = #tour
    if n == 0 then return 0, 0 end
    if n == 1 then return 1, 2 * Dist(points[tour[1]], p) end
    local bestAt, bestCost = 1, math.huge
    for k = 1, n do
        local U, V = points[tour[k]], points[tour[k % n + 1]]
        local c = Dist(U, p) + Dist(p, V) - Dist(U, V)
        if c < bestCost then bestAt, bestCost = k, c end
    end
    return bestAt, bestCost
end

return O
