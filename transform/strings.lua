-- language: Lua 5.1, file: transform/strings.lua
-- rewrites every string literal (short + long) into a decoder call and builds the pool.

local M = {}
local tok = require("transform.tokenizer")

local simple = {
    a = "\a", b = "\b", f = "\f", n = "\n", r = "\r",
    t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'",
}

local function unescape(s)
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c ~= "\\" then
            out[#out + 1] = c
            i = i + 1
        else
            local e = s:sub(i + 1, i + 1)
            if e == "" then
                out[#out + 1] = "\\"
                i = i + 1
            elseif e >= "0" and e <= "9" then
                local digits = s:sub(i + 1, i + 3):match("^%d%d?%d?")
                out[#out + 1] = string.char(tonumber(digits))
                i = i + 1 + #digits
            elseif e == "x" then
                local hx = s:sub(i + 2, i + 3):match("^%x%x?")
                if hx then
                    out[#out + 1] = string.char(tonumber(hx, 16))
                    i = i + 2 + #hx
                else
                    out[#out + 1] = "x"
                    i = i + 2
                end
            elseif e == "\n" then
                out[#out + 1] = "\n"
                i = i + 2
            elseif e == "\r" then
                if s:sub(i + 2, i + 2) == "\n" then
                    out[#out + 1] = "\r\n"
                    i = i + 3
                else
                    out[#out + 1] = "\r"
                    i = i + 2
                end
            elseif simple[e] then
                out[#out + 1] = simple[e]
                i = i + 2
            else
                out[#out + 1] = e
                i = i + 2
            end
        end
    end
    return table.concat(out)
end

local function long_value(src, sp)
    local body = src:sub(sp.open + 1, sp.close - 1)
    if body:sub(1, 2) == "\r\n" then
        body = body:sub(3)
    elseif body:sub(1, 1) == "\n" or body:sub(1, 1) == "\r" then
        body = body:sub(2)
    end
    return body
end

function M.encode(src, decname)
    local spans = tok.spans(src)
    local pool = {}
    local out = {}
    local last = 1
    for i = 1, #spans do
        local sp = spans[i]
        local value
        if sp.kind == "short" then
            value = unescape(src:sub(sp.s + 1, sp.e - 1))
        else
            value = long_value(src, sp)
        end
        pool[#pool + 1] = value
        out[#out + 1] = src:sub(last, sp.s - 1)
        out[#out + 1] = "(" .. decname .. "(" .. i .. "))"
        last = sp.e + 1
    end
    out[#out + 1] = src:sub(last)
    return table.concat(out), pool
end

return M
