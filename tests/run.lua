-- Offline test runner (plain Lua 5.1, no external packages).
-- Usage: lua tests/run.lua <test files...>
-- Each test file receives the test API `T` as its chunk argument:
--   local T = ...
--   T.test("does a thing", function() T.eq(1, 1) end)

local scriptPath = (arg and arg[0]) or "tests/run.lua"
local testsDir = scriptPath:gsub("\\", "/"):match("^(.*)/[^/]*$") or "tests"
ROOT = testsDir:match("^(.*)/tests$") or (testsDir == "tests" and ".") or testsDir .. "/.."
package.path = testsDir .. "/harness/?.lua;" .. testsDir .. "/?.lua;" .. package.path

local Game = require("game")
local World = require("wow")

local T = {}
local registered = {}
local currentFile

function T.test(name, fn) table.insert(registered, { file = currentFile, name = name, fn = fn }) end

local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

local function deepEqual(a, b, path, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false, (path or "value") .. ": expected " .. show(b) .. ", got " .. show(a)
    end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(b) do
        local ok, why = deepEqual(a[k], v, (path or "") .. "." .. tostring(k), seen)
        if not ok then return false, why end
    end
    for k in pairs(a) do
        if b[k] == nil then return false, (path or "") .. "." .. tostring(k) .. ": unexpected key" end
    end
    return true
end

local function fail(msg, level) error(msg, (level or 1) + 2) end

function T.ok(cond, msg) if not cond then fail(msg or "expected truthy value", 1) end end
function T.no(cond, msg) if cond then fail(msg or ("expected falsy value, got " .. show(cond)), 1) end end
function T.eq(actual, expected, msg)
    if actual ~= expected then
        fail((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 1)
    end
end
function T.neq(actual, unexpected, msg)
    if actual == unexpected then fail((msg and (msg .. ": ") or "") .. "did not expect " .. show(actual), 1) end
end
function T.same(actual, expected, msg)
    local ok, why = deepEqual(actual, expected)
    if not ok then fail((msg and (msg .. ": ") or "") .. why, 1) end
end
function T.contains(haystack, needle, msg)
    if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
        fail((msg and (msg .. ": ") or "") .. "expected " .. show(haystack) .. " to contain " .. show(needle), 1)
    end
end
function T.notContains(haystack, needle, msg)
    if type(haystack) == "string" and haystack:find(needle, 1, true) then
        fail((msg and (msg .. ": ") or "") .. "expected " .. show(haystack) .. " not to contain " .. show(needle), 1)
    end
end
function T.raises(fn, pattern, msg)
    local ok, err = pcall(fn)
    if ok then fail((msg and (msg .. ": ") or "") .. "expected an error", 1) end
    if pattern and not tostring(err):find(pattern, 1, true) then
        fail((msg and (msg .. ": ") or "") .. "error " .. show(tostring(err)) .. " does not contain " .. show(pattern), 1)
    end
end

T.game = Game.new
T.World = World
T.deepcopy = World.deepcopy
T.ENUM = World.ENUM

-- Load test files
local files = {}
for i = 1, #arg do files[#files + 1] = arg[i] end
if #files == 0 then
    io.stderr:write("usage: lua tests/run.lua <test files>\n")
    os.exit(2)
end

local loadErrors = 0
for _, file in ipairs(files) do
    currentFile = file
    local chunk, err = loadfile(file)
    if not chunk then
        print("LOAD ERROR " .. file .. ": " .. tostring(err))
        loadErrors = loadErrors + 1
    else
        local ok, runErr = pcall(chunk, T)
        if not ok then
            print("LOAD ERROR " .. file .. ": " .. tostring(runErr))
            loadErrors = loadErrors + 1
        end
    end
end

local passed, failed = 0, 0
local filter = os.getenv("ICER_TEST_FILTER")
for _, t in ipairs(registered) do
    if not filter or t.name:find(filter, 1, true) then
        local ok, err = xpcall(t.fn, debug.traceback)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print("FAIL " .. t.file .. " :: " .. t.name)
            print("     " .. tostring(err):gsub("\n", "\n     "))
        end
    end
end

print(string.format("Tests: %d passed, %d failed, %d files%s", passed, failed, #files,
    loadErrors > 0 and (", " .. loadErrors .. " load errors") or ""))
os.exit((failed > 0 or loadErrors > 0) and 1 or 0)
