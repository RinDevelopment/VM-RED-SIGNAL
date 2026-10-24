local function counter()
    local n = 0
    return function()
        n = n + 1
        return n
    end
end
local c = counter()
print(c(), c(), c())

local t = {}
for i = 1, 120 do t[i] = i * 2 end
print(#t, t[1], t[120])

for k, v in ipairs({ 10, 20, 30 }) do print("ipairs", k, v) end
for k, v in pairs({ a = 1, b = 2 }) do print("pairs", k, v) end

local function multi(a, b) return a + b, a - b, a * b end
local x, y, z = multi(7, 3)
print("multi", x, y, z)

local function va(...) return select("#", ...), ... end
print("va", va(1, nil, 3))

local mt = setmetatable({}, {
    __add = function() return 99 end,
    __index = function(_, k) return "ix:" .. k end,
})
print("mt", mt + 1, mt.foo)

local s = 0
for i = 10, 1, -2 do s = s + i end
print("step", s)

local a, b = 1, 2
a, b = b, a
print("swap", a, b)

local big = {}
for i = 1, 120 do big[i] = i end
print("big", big[1], big[60], big[120], #big)

local n = 0
repeat
    n = n + 1
until n >= 5
print("repeat", n)

local out = {}
for i = 1, 10 do
    if i % 2 == 0 then
        out[#out + 1] = i
    end
end
print("odds", table.concat(out, ","))

local function outer(v)
    local acc = v
    return function(d)
        acc = acc + d
        return acc
    end, function()
        return acc
    end
end
local add, get = outer(10)
add(5)
add(7)
print("upval", get())

local lit = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120}
print("lit", lit[1], lit[50], lit[51], lit[120], #lit)

local found
for i = 1, 10 do
    for j = 1, 10 do
        if i * j == 42 then
            found = i .. "x" .. j
            break
        end
    end
    if found then break end
end
print("break", found)

local nested = 0
for i = 1, 3 do
    for j = 1, 3 do
        nested = nested + i * j
    end
end
print("nested", nested)

local function tc(n)
    if n == 0 then return "done" end
    return tc(n - 1)
end
print("tail", tc(50))

local fs = {}
for i = 1, 3 do
    fs[i] = function() return i end
end
print("close", fs[1](), fs[2](), fs[3]())
