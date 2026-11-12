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

-- Straight-line yards between two points
local function Euclid(a, b)
    local dx, dy = a[1] - b[1], a[2] - b[2]
    return sqrt(dx * dx + dy * dy)
end
O.Euclid = Euclid

-- Taboo areas the route keeps out of (O.Walls), while one is being worked out
-- (O.SetWalls). nil: none, every leg is a straight line.
local walls

-- Yards to travel from a to b: straight, or round the taboo areas in the way
local function Dist(a, b)
    if walls then return walls:Dist(a, b) end
    local dx, dy = a[1] - b[1], a[2] - b[2]
    return sqrt(dx * dx + dy * dy)
end
O.Dist = Dist

---------------------------------------------------------------------------
-- Taboo areas: polygons (lists of { x, y } in yards) a route never goes into.
-- A leg that would cross one goes round it instead, by way of its corners
-- (pushed out by MARGIN so the line doesn't touch the edge). Distances round
-- them come from the shortest paths between those corners (worked out once,
-- Floyd-Warshall) and, for each point, which corners it can see.
---------------------------------------------------------------------------
local MARGIN = 3      -- yards a line going round an area keeps from its corners
local HUGE = math.huge
O.WALL_MARGIN = MARGIN

local function Orient(ax, ay, bx, by, cx, cy)
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

-- Do segments a-b and c-d touch or cross? (touching counts: better a short
-- way round than a line along an edge)
local function Crosses(ax, ay, bx, by, cx, cy, dx, dy)
    local o1, o2 = Orient(ax, ay, bx, by, cx, cy), Orient(ax, ay, bx, by, dx, dy)
    if (o1 > 0 and o2 > 0) or (o1 < 0 and o2 < 0) then return false end
    local o3, o4 = Orient(cx, cy, dx, dy, ax, ay), Orient(cx, cy, dx, dy, bx, by)
    if (o3 > 0 and o4 > 0) or (o3 < 0 and o4 < 0) then return false end
    if o1 == 0 and o2 == 0 and o3 == 0 and o4 == 0 then
        -- on one line: only if they overlap
        return math.max(math.min(ax, bx), math.min(cx, dx)) <= math.min(math.max(ax, bx), math.max(cx, dx))
            and math.max(math.min(ay, by), math.min(cy, dy)) <= math.min(math.max(ay, by), math.max(cy, dy))
    end
    return true
end
O.Crosses = Crosses

-- Is (x, y) inside the polygon (flat list x1, y1, x2, y2...)? Ray casting.
local function InPoly(xy, x, y)
    local inside = false
    local n = #xy / 2
    local j = n
    for i = 1, n do
        local xi, yi, xj, yj = xy[2 * i - 1], xy[2 * i], xy[2 * j - 1], xy[2 * j]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

-- Does a polygon's outline cross itself? (flat list)
function O.SelfCrossing(xy)
    local n = #xy / 2
    for i = 1, n do
        local i2 = i % n + 1
        for j = i + 1, n do
            local j2 = j % n + 1
            if j ~= i2 and j2 ~= i then
                if Crosses(xy[2 * i - 1], xy[2 * i], xy[2 * i2 - 1], xy[2 * i2],
                    xy[2 * j - 1], xy[2 * j], xy[2 * j2 - 1], xy[2 * j2]) then
                    return true
                end
            end
        end
    end
    return false
end

local Walls = {}
Walls.__index = Walls

-- polys: a list of polygons, each a flat list { x1, y1, x2, y2, ... } in yards
-- (3 corners or more). Returns the walls, or nil if there are none.
function O.Walls(polys)
    local w = setmetatable({ polys = {}, edges = {}, verts = {}, info = setmetatable({}, { __mode = "k" }) }, Walls)
    local minX, minY, maxX, maxY = HUGE, HUGE, -HUGE, -HUGE
    for _, xy in ipairs(polys or {}) do
        local n = math.floor(#xy / 2)
        if n >= 3 then
            local poly = { n = n }
            local area = 0
            for i = 1, n do
                local j = i % n + 1
                area = area + xy[2 * i - 1] * xy[2 * j] - xy[2 * j - 1] * xy[2 * i]
            end
            -- corners anticlockwise (x right, y up in the maths; any way works if consistent)
            local flat = {}
            for i = 1, n do
                local k = area >= 0 and i or n - i + 1
                flat[2 * i - 1], flat[2 * i] = xy[2 * k - 1], xy[2 * k]
            end
            poly.xy = flat
            local pminX, pminY, pmaxX, pmaxY = HUGE, HUGE, -HUGE, -HUGE
            for i = 1, n do
                local x, y = flat[2 * i - 1], flat[2 * i]
                pminX, pmaxX = math.min(pminX, x), math.max(pmaxX, x)
                pminY, pmaxY = math.min(pminY, y), math.max(pmaxY, y)
                local j = i % n + 1
                local x2, y2 = flat[2 * j - 1], flat[2 * j]
                w.edges[#w.edges + 1] = { x, y, x2, y2,
                    math.min(x, x2), math.min(y, y2), math.max(x, x2), math.max(y, y2) }
            end
            poly.box = { pminX, pminY, pmaxX, pmaxY }
            minX, minY = math.min(minX, pminX), math.min(minY, pminY)
            maxX, maxY = math.max(maxX, pmaxX), math.max(maxY, pmaxY)
            w.polys[#w.polys + 1] = poly
        end
    end
    if #w.polys == 0 then return nil end
    w.box = { minX - 1, minY - 1, maxX + 1, maxY + 1 }
    -- the corners a way round can bend at: each corner that sticks out,
    -- pushed out from both its edges by MARGIN
    for _, poly in ipairs(w.polys) do
        local xy, n = poly.xy, poly.n
        for i = 1, n do
            local h, j = (i - 2) % n + 1, i % n + 1
            local px, py = xy[2 * h - 1], xy[2 * h]
            local x, y = xy[2 * i - 1], xy[2 * i]
            local nx, ny = xy[2 * j - 1], xy[2 * j]
            if Orient(px, py, x, y, nx, ny) > 0 then   -- turns left: sticks out (anticlockwise)
                local d1x, d1y = x - px, y - py
                local d2x, d2y = nx - x, ny - y
                local l1, l2 = sqrt(d1x * d1x + d1y * d1y), sqrt(d2x * d2x + d2y * d2y)
                if l1 > 0 and l2 > 0 then
                    -- outward normals (right of the way round)
                    local n1x, n1y = d1y / l1, -d1x / l1
                    local n2x, n2y = d2y / l2, -d2x / l2
                    local k = MARGIN / math.max(0.25, 1 + n1x * n2x + n1y * n2y)
                    local v = { x + (n1x + n2x) * k, y + (n1y + n2y) * k }
                    if not w:Inside(v) then w.verts[#w.verts + 1] = v end
                end
            end
        end
    end
    -- shortest ways between the corners
    local V = #w.verts
    local D, nxt = {}, {}
    for i = 1, V do
        D[i], nxt[i] = {}, {}
        for j = 1, V do D[i][j] = i == j and 0 or HUGE end
    end
    for i = 1, V do
        for j = i + 1, V do
            if not w:Blocked(w.verts[i], w.verts[j]) then
                local d = Euclid(w.verts[i], w.verts[j])
                D[i][j], D[j][i], nxt[i][j], nxt[j][i] = d, d, j, i
            end
        end
        O.Pause()
    end
    for k = 1, V do
        local Dk = D[k]
        for i = 1, V do
            local Di, dik = D[i], D[i][k]
            if dik < HUGE then
                local Ni = nxt[i]
                for j = 1, V do
                    local d = dik + Dk[j]
                    if d < Di[j] then Di[j], Ni[j] = d, Ni[k] end
                end
            end
        end
        O.Pause()
    end
    w.D, w.nxt = D, nxt
    return w
end

-- Is the point inside a taboo area?
function Walls:Inside(p)
    local x, y = p[1], p[2]
    for _, poly in ipairs(self.polys) do
        local b = poly.box
        if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] and InPoly(poly.xy, x, y) then return true end
    end
    return false
end

-- Does the straight line a-b touch a taboo area?
function Walls:Blocked(a, b)
    local ax, ay, bx, by = a[1], a[2], b[1], b[2]
    local x1, y1, x2, y2 = math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by)
    local box = self.box
    if x2 < box[1] or x1 > box[3] or y2 < box[2] or y1 > box[4] then return false end
    for _, e in ipairs(self.edges) do
        if not (x2 < e[5] or x1 > e[7] or y2 < e[6] or y1 > e[8])
            and Crosses(ax, ay, bx, by, e[1], e[2], e[3], e[4]) then
            return true
        end
    end
    return false
end

-- What's known about one point: the corners it can see (and how far), the
-- yards from it to every corner, and distances to other points already worked
-- out. Kept while the point stays where it is.
function Walls:Info(p)
    local info = self.info[p]
    if info and info.x == p[1] and info.y == p[2] then return info end
    info = { x = p[1], y = p[2], pair = setmetatable({}, { __mode = "k" }) }
    self.info[p] = info
    return info
end

function Walls:Seen(info, p)
    if info.seen then return info.seen end
    local seen = {}
    for i, v in ipairs(self.verts) do
        if not self:Blocked(p, v) then seen[#seen + 1] = i; seen[#seen + 1] = Euclid(p, v) end
    end
    Step(#self.verts)
    info.seen = seen
    return seen
end

-- Yards from p to every corner, going round
function Walls:To(info, p)
    if info.to then return info.to end
    local seen = self:Seen(info, p)
    local to, via = {}, {}
    local D = self.D
    for j = 1, #self.verts do to[j] = HUGE end
    for k = 1, #seen, 2 do
        local u, du = seen[k], seen[k + 1]
        local Du = D[u]
        for j = 1, #self.verts do
            local d = du + Du[j]
            if d < to[j] then to[j], via[j] = d, u end
        end
    end
    Step(#seen * 2)
    info.to, info.via = to, via
    return to
end

-- The way from a to b round the taboo areas: its length, and the corners it
-- bends at (indices), or nil when a can't get to b at all
function Walls:Way(a, b)
    local ia, ib = self:Info(a), self:Info(b)
    local to = self:To(ia, a)
    local seen = self:Seen(ib, b)
    local best, last = HUGE, nil
    for k = 1, #seen, 2 do
        local v = seen[k]
        local d = to[v] + seen[k + 1]
        if d < best then best, last = d, v end
    end
    return best, last, ia
end

function Walls:Dist(a, b)
    local ib = self:Info(b)
    local ia = self:Info(a)
    local d = ia.pair[ib]
    if d then return d end
    if not self:Blocked(a, b) then
        d = Euclid(a, b)
    else
        d = self:Way(a, b)
        if d == HUGE then d = Euclid(a, b) * 100 end   -- shut in: straight through, but never chosen if it can help it
    end
    ia.pair[ib] = d
    ib.pair[ia] = d
    return d
end

-- The corners (as { x, y }) a leg from a to b bends round, in order; empty
-- when the straight line is clear (or there's no way round)
function Walls:Path(a, b)
    if not self:Blocked(a, b) then return {} end
    local d, last, ia = self:Way(a, b)
    if d == HUGE or not last then return {} end
    local first = ia.via[last]
    local out = {}
    local k = first
    while k do
        out[#out + 1] = { self.verts[k][1], self.verts[k][2] }
        if k == last then break end
        k = self.nxt[k][last]
    end
    return out
end

-- Use these walls (or none) for every distance from now on
function O.SetWalls(w) walls = w end
function O.GetWalls() return walls end

-- The loop (stops in order) with the corners each blocked leg bends round
-- put in between; those carry bend = true
function O.Expand(stops)
    if not walls or #stops < 2 then return stops end
    local out = {}
    local n = #stops
    for i = 1, n do
        local a, b = stops[i], stops[i % n + 1]
        out[#out + 1] = a
        for _, v in ipairs(walls:Path(a, b)) do
            v.bend = true
            out[#out + 1] = v
        end
        Step(4)
    end
    return out
end

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
                if not used[j] and Euclid(p, points[j]) <= radius and not (walls and walls:Blocked(p, points[j])) then
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
                for _, q in ipairs(group) do r = math.max(r, Euclid(c, q)) end
                return r
            end
            local reach = Reach(spot)
            local function Walled(c)
                if not walls then return false end
                if walls:Inside(c) then return true end
                for _, q in ipairs(group) do if walls:Blocked(c, q) then return true end end
                return false
            end
            if reach > radius or Walled(spot) then spot, reach = { p[1], p[2] }, Reach(p) end
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

-- The k closest points to each point of the tour, nearest first. 2-opt and
-- Or-opt only try joining a point to these: the moves that shorten a loop
-- almost always join near neighbours, and it makes each pass about n * k
-- instead of n * n.
local NEAR = 10
local function Neighbours(points, tour, k)
    local near = {}
    for _, a in ipairs(tour) do
        local list, dist = {}, {}
        local pa = points[a]
        for _, b in ipairs(tour) do
            if b ~= a then
                local d = Dist(pa, points[b])
                local m = #list
                if m < k or d < dist[m] then
                    if m == k then list[m], dist[m] = nil, nil; m = m - 1 end
                    local at = m + 1
                    while at > 1 and dist[at - 1] > d do
                        list[at], dist[at] = list[at - 1], dist[at - 1]
                        at = at - 1
                    end
                    list[at], dist[at] = b, d
                end
            end
        end
        Step(#tour)
        near[a] = list
    end
    return near
end

-- Every change to the tour goes through Put, which keeps pos (point ->
-- position) up to date and, while `undo` is a table, notes what was there
-- so a shake that didn't help can be taken back
local undo
local function Put(tour, pos, i, v)
    if undo then
        undo[#undo + 1] = i
        undo[#undo + 1] = tour[i]
    end
    tour[i] = v
    pos[v] = i
end

-- Turn round the stretch of the loop from position s, len places long
-- (going round past the end)
local function Reverse(tour, pos, s, len)
    local n = #tour
    for k = 0, math.floor(len / 2) - 1 do
        local i, j = (s + k - 1) % n + 1, (s + len - 2 - k) % n + 1
        local ti, tj = tour[i], tour[j]
        Put(tour, pos, i, tj)
        Put(tour, pos, j, ti)
    end
end

-- The legs at positions p (tour[p] -> next) and q become tour[p] -> tour[q]
-- and next(p) -> next(q): turn round whichever side of the loop is shorter
local function Swap(tour, pos, p, q)
    local n = #tour
    local len = (q - p) % n            -- from p + 1 to q
    if len <= n - len then
        Reverse(tour, pos, p % n + 1, len)
    else
        Reverse(tour, pos, q % n + 1, n - len)
    end
end

-- Tries the moves that start at point a. Returns the points whose legs
-- changed (to look at again) and the yards saved, or nil if nothing got
-- shorter.
--   2-opt: where a leg from a and another leg cross (a-b ... c-d), reconnect
--   them as a-c and b-d by turning the stretch between round.
--   Or-opt: move the run of 1 to 3 nodes starting or ending at a to the place
--   next to a near neighbour of either end where it costs least (either way
--   round).
local function TryPoint(points, tour, pos, near, a)
    local n = #tour
    local A = points[a]
    local i = pos[a]
    for side = 1, 2 do
        local p = side == 1 and i or (i - 2) % n + 1
        local x1, x2 = tour[p], tour[p % n + 1]
        local other = side == 1 and x2 or x1
        local leg = Dist(A, points[other])
        for _, c in ipairs(near[a]) do
            local C = points[c]
            local ac = Dist(A, C)
            if ac >= leg - EPS then break end
            local q = pos[c]
            local y = side == 1 and tour[q % n + 1] or tour[(q - 2) % n + 1]
            if c ~= other and y ~= a then
                local Y = points[y]
                local delta = ac + Dist(points[other], Y) - leg - Dist(C, Y)
                if delta < -EPS then
                    if side == 1 then
                        Swap(tour, pos, p, q)                  -- a-c, x2-y
                    else
                        Swap(tour, pos, pos[y], p)             -- y-x1, c-a
                    end
                    return { a, other, c, y }, -delta
                end
            end
        end
    end
    if n < 6 then return nil end
    for len = 1, 3 do
        for back = 0, len - 1, math.max(1, len - 1) do
            local first = (i - back - 1) % n + 1
            local function At(k) return tour[(first + k - 2) % n + 1] end   -- k-th of the run
            local inRun = {}
            for k = 1, len do inRun[At(k)] = true end
            local s1, sL = At(1), At(len)
            local prev, nxt = tour[(first - 2) % n + 1], At(len + 1)
            local P, S1, SL, N = points[prev], points[s1], points[sL], points[nxt]
            local gain = Dist(P, S1) + Dist(SL, N) - Dist(P, N)
            if gain > EPS then
                local bestCost, bestU, bestFlip = gain - EPS, nil, false
                for e = 1, 2 do
                    local S = e == 1 and S1 or SL
                    for _, c in ipairs(near[e == 1 and s1 or sL]) do
                        if Dist(S, points[c]) >= gain then break end
                        if not inRun[c] then
                            local k = pos[c]
                            -- the legs c -> next and before -> c, if outside the run
                            for w = 1, 2 do
                                local u = tour[w == 1 and k or (k - 2) % n + 1]
                                local v = tour[pos[u] % n + 1]
                                if not inRun[u] and not inRun[v] then
                                    local U, V = points[u], points[v]
                                    local uv = Dist(U, V)
                                    local c1 = Dist(U, S1) + Dist(SL, V) - uv
                                    local c2 = Dist(U, SL) + Dist(S1, V) - uv
                                    if c1 < bestCost then bestCost, bestU, bestFlip = c1, u, false end
                                    if c2 < bestCost then bestCost, bestU, bestFlip = c2, u, true end
                                end
                            end
                        end
                    end
                end
                if bestU then
                    local run = {}
                    for k = 1, len do run[k] = At(bestFlip and len - k + 1 or k) end
                    local out = {}
                    for k = 1, n do
                        local t = tour[k]
                        if not inRun[t] then
                            out[#out + 1] = t
                            if t == bestU then
                                for r = 1, len do out[#out + 1] = run[r] end
                            end
                        end
                    end
                    local v = tour[pos[bestU] % n + 1]
                    for k = 1, n do
                        if tour[k] ~= out[k] then Put(tour, pos, k, out[k]) end
                    end
                    return { prev, nxt, s1, sL, bestU, v }, gain - bestCost
                end
            end
        end
    end
    return nil
end

-- Keep trying the points in `start` (and the ends of every leg that changes)
-- until no move makes the loop shorter. Returns the yards saved.
local function Settle(points, tour, pos, near, start)
    local queue, queued = {}, {}
    local head, tail = 1, 0
    local function Add(t)
        if not queued[t] then
            queued[t] = true
            tail = tail + 1
            queue[tail] = t
        end
    end
    for _, t in ipairs(start) do Add(t) end
    local saved = 0
    while head <= tail do
        local a = queue[head]
        queue[head] = nil
        head = head + 1
        queued[a] = nil
        local touched, gain = TryPoint(points, tour, pos, near, a)
        Step(NEAR * 4)
        if touched then
            saved = saved + gain
            for _, t in ipairs(touched) do Add(t) end
        end
    end
    return saved
end

-- 2-opt and Or-opt until neither finds anything shorter. Then shake it up
-- many times (two short stretches next to each other change places, then it
-- settles again) and keep each shake that comes out shorter: this gets out of
-- loops that no single move can shorten.
local SHAKES = 2       -- per point
local function Improve(points, tour)
    local n = #tour
    if n <= 3 then return tour end
    local near = Neighbours(points, tour, math.min(NEAR, n - 1))
    local pos = {}
    for i, k in ipairs(tour) do pos[k] = i end
    Settle(points, tour, pos, near, tour)
    if n < 8 then return tour end
    local seed = 12345
    local function Random(m)               -- the same every time, 1 to m
        seed = (seed * 16807) % 2147483647
        return seed % m + 1
    end
    local function At(k) return tour[(k - 1) % n + 1] end
    local maxRun = math.max(1, math.min(30, math.floor(n / 4)))
    for _ = 1, SHAKES * n do
        local l1, l2 = Random(maxRun), Random(maxRun)
        local p = Random(n)
        -- the l1 after tour[p] and the l2 after those change places:
        -- p, A1..Al1, B1..Bl2, q  becomes  p, B1..Bl2, A1..Al1, q
        local P, A1, Al = points[At(p)], points[At(p + 1)], points[At(p + l1)]
        local B1, Bl, Q = points[At(p + l1 + 1)], points[At(p + l1 + l2)], points[At(p + l1 + l2 + 1)]
        local added = Dist(P, B1) + Dist(Bl, A1) + Dist(Al, Q)
            - Dist(P, A1) - Dist(Al, B1) - Dist(Bl, Q)
        undo = {}
        local run = {}
        for k = 1, l1 + l2 do run[k] = At(p + k) end
        for k = 1, l1 + l2 do
            Put(tour, pos, (p + k - 1) % n + 1, k <= l2 and run[l1 + k] or run[k - l2])
        end
        local ends = {}
        for _, k in ipairs({ p, p + 1, p + l2, p + l2 + 1, p + l1 + l2, p + l1 + l2 + 1 }) do
            ends[#ends + 1] = At(k)
        end
        local gain = Settle(points, tour, pos, near, ends)
        if gain - added <= EPS then
            -- no shorter: take it all back, last change first
            for k = #undo - 1, 1, -2 do
                tour[undo[k]] = undo[k + 1]
                pos[undo[k + 1]] = undo[k]
            end
        end
        undo = nil
        Step(l1 + l2)
    end
    return tour
end

-- The shortest loop it can find through the points. Returns the tour.
function O.Solve(points)
    local n = #points
    local tour = {}
    if n <= 3 then
        for i = 1, n do tour[i] = i end
        return tour
    end
    return Improve(points, Nearest(points))
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
function O.SegDist(a, b, c) return Euclid(c, Closest(a, b, c)) end

-- Can a stop at p stand for node c: outside the taboo areas, with nothing
-- between it and c?
local function Clear(p, c)
    return not walls or not (walls:Inside(p) or walls:Blocked(p, c))
end

-- Where to walk past node c, coming from a and going on to b, when you only
-- need to get within `radius` of it: the spot that far from c with the
-- shortest a -> spot -> b. On the straight line a-b if that passes close enough.
function O.Place(a, b, c, radius)
    local q = Closest(a, b, c)
    local d = Euclid(q, c)
    if d <= radius and Clear(q, c) then return q end
    local function At(t)
        return { c[1] + radius * math.cos(t), c[2] + radius * math.sin(t) }
    end
    local function Cost(t)
        local p = At(t)
        if not Clear(p, c) then return HUGE end
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
    if Cost(best) == HUGE then return { c[1], c[2] } end   -- nowhere clear on the circle: the node itself
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
function O.Shortcut(nodes, radius)
    if radius and radius > 0 then
        local groups = O.Group(nodes, radius / 2)
        nodes = (#groups >= 2 or #nodes < 2) and groups or O.Group(nodes, 0)   -- a loop needs 2 stops
    end
    local tour = O.Solve(nodes)
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
                    moved = math.max(moved, Euclid(p, s))
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
        Improve(stops, order)
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
