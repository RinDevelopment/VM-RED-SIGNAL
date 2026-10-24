-- language: Lua 5.1, file: transform/junk.lua
-- syntax-safe noise. prepended only, always inside do-blocks.

local M = {}

local function n(lo, hi)
    return math.random(lo, hi)
end

function M.noise()
    local out = {}
    for i = 1, n(3, 6) do
        local a, b = n(1000, 99999), n(3, 97)
        out[#out + 1] = ("do local v%d = %d * %d; if v%d %% 2 == 0 then v%d = v%d + 0 end end")
            :format(i, a, b, i, i, i)
    end
    for i = 1, n(2, 3) do
        local a = n(1000, 99999)
        out[#out + 1] = ("do local o%d = %d; if (o%d * o%d - o%d) %% 2 == 0 then o%d = o%d end end")
            :format(i, a, i, i, i, i, i)
    end
    out[#out + 1] = "do local _dead = false; if _dead then error('unreachable') end end"
    return table.concat(out, "\n") .. "\n"
end

return M
