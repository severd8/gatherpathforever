-- Runs the GatherPath Forever tests outside the game.
-- From the repo root:  lua5.1 tests/run.lua
-- Exits with code 1 (and prints the error) if a test fails.

dofile("tests/wowstub.lua")   -- fake game API (replaces print with a logger)

local ok, err = xpcall(function() dofile("tests/run_tests.lua") end, debug.traceback)
for _, line in ipairs(LOG) do
    if line:find("^STEP") or line:find("PASSED") then REAL_PRINT(line) end
end
if not ok then
    REAL_PRINT("FAILED: " .. tostring(err))
    REAL_PRINT("last chat lines:")
    for i = math.max(1, #LOG - 5), #LOG do REAL_PRINT("  " .. LOG[i]) end
    os.exit(1)
end
