-- language: Lua 5.1, file: transform/tokenizer.lua
-- finds string literal spans only. comments are skipped, long brackets handled.
-- returns array of {s=start, e=end,kind="short"|"long",quote=,eq=}

local M = {}

local function long_open(src, i)
    if src:sub(i, i) ~= "[" then return nil end
    local j = i + 1
    while src:sub(j, j) == "=" do j = j + 1 end
    if src:sub(j, j) == "[" then
        return j - i - 1, j
    end
    return nil
end

local function scan_short(src, i)
    local q = src:sub(i, i)
    local j = i + 1
    local n = #src
    while j <= n do
        local c = src:sub(j, j)
        if c == "\\" then
            j = j + 2
        elseif c == q then
            return j
        elseif c == "\n" or c == "\r" then
            return j - 1
        else
            j = j + 1
        end
    end
    return n
end

function M.spans(src)
    local out = {}
    local i, n = 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c == "-" and src:sub(i + 1, i + 1) == "-" then
            -- comment
            local eq, open = long_open(src, i + 2)
            if eq then
                local close = "]" .. string.rep("=", eq) .. "]"
                local j = src:find(close, open + 1, true)
                i = (j and (j + #close)) or (n + 1)
            else
                local j = src:find("\n", i + 2, true)
                i = (j and (j + 1)) or (n + 1)
            end
        elseif c == '"' or c == "'" then
            local e = scan_short(src, i)
            out[#out + 1] = { s = i, e = e, kind = "short", quote = c }
            i = e + 1
        elseif c == "[" then
            local eq, open = long_open(src, i)
            if eq then
                local close = "]" .. string.rep("=", eq) .. "]"
                local j = src:find(close, open + 1, true)
                if j then
                    out[#out + 1] = { s = i, e = j + #close - 1, kind = "long", eq = eq, open = open, close = j }
                    i = j + #close
                else
                    i = n + 1
                end
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return out
end

return M
