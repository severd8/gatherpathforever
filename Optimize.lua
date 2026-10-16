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

-- Nodes closer together than `radius` yards become one point, in the middle
-- of them (you gather them from one spot). Returns new points; each has
-- .count, how many nodes it stands for.
function O.Merge(points, radius)
    local out = {}
    if not radius or radius <= 0 then
        for i, p in ipairs(points) do out[i] = { p[1], p[2], count = 1 } end
        return out
    end
    local used = {}
    for i, p in ipairs(points) do
        if not used[i] then
            used[i] = true
            local sx, sy, count = p[1], p[2], 1
            -- grow the group from the nodes already in it
            local group = { p }
            local k = 1
            while k <= #group do
                local g = group[k]
                for j = i + 1, #points do
                    if not used[j] and Dist(g, points[j]) <= radius then
                        used[j] = true
                        group[#group + 1] = points[j]
                        sx, sy, count = sx + points[j][1], sy + points[j][2], count + 1
                    end
                end
                Step(#points)
                k = k + 1
            end
            out[#out + 1] = { sx / count, sy / count, count = count }
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

-- The shortest loop it can find through the points. Returns the tour.
function O.Solve(points, maxRounds)
    local n = #points
    local tour = {}
    if n <= 3 then
        for i = 1, n do tour[i] = i end
        return tour
    end
    tour = Nearest(points)
    for _ = 1, maxRounds or 60 do
        local a = TwoOpt(points, tour)
        local b = OrOpt(points, tour)
        if not (a or b) then break end
    end
    return tour
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
