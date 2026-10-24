-- language: Lua 5.1, file: samples/test.lua
-- target for pipeline verification. deterministic output.

local t = {
    name = "dj",
    ["key"] = "value",
    [3] = 3,
}

local long = [[
line one
line two
]]

local function greet(who, ...)
    return "hello " .. who .. " (" .. select("#", ...) .. ")"
end

print(greet(t.name, 1, 2, 3))
print(string.format("%s=%s/%d", "key", t["key"], t[3]))
print(long:gsub("%s+", " "):upper())
print(("mix" .. 'ed'):len())

local total = 0
for i = 1, 5 do
    total = total + i
end
print("sum=" .. total)

local n = 0
while n < 3 do
    n = n + 1
end
print("n=" .. n)

if total == 15 and n == 3 then
    print("flow ok")
else
    print("flow bad")
end

-- comment with "quotes" and [[brackets]] must survive untouched
print([[long bracket arg]])
