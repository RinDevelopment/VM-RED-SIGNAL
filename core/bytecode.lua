-- language: Lua 5.1, file: core/bytecode.lua
-- parses luac 5.1 binary chunks. little/big endian aware.

local M = {}

local function u8(s, p)
    return string.byte(s, p), p + 1
end

local function u32(s, p, le)
    local b1, b2, b3, b4 = string.byte(s, p, p + 3)
    if not b1 then return nil, p end
    if le then
        return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216, p + 4
    end
    return b4 + b3 * 256 + b2 * 65536 + b1 * 16777216, p + 4
end

local function usize(s, p, le, w)
    if w == 4 then return u32(s, p, le) end
    local lo, hi
    lo, p = u32(s, p, le)
    hi, p = u32(s, p, le)
    if le then return lo + hi * 4294967296, p end
    return hi + lo * 4294967296, p
end

local function read_string(s, p, le, sw)
    local n
    n, p = usize(s, p, le, sw)
    if n == 0 then return nil, p end
    local v = s:sub(p, p + n - 2)
    return v, p + n
end

local function read_proto(s, p, le, sw)
    local proto = {}
    proto.source, p = read_string(s, p, le, sw)
    proto.linedefined, p = u32(s, p, le)
    proto.lastlinedefined, p = u32(s, p, le)
    proto.nups, p = u8(s, p)
    proto.numparams, p = u8(s, p)
    proto.is_vararg, p = u8(s, p)
    proto.maxstack, p = u8(s, p)

    local n
    n, p = u32(s, p, le)
    proto.code = {}
    for i = 1, n do
        proto.code[i], p = u32(s, p, le)
    end

    n, p = u32(s, p, le)
    proto.k = {}
    for i = 1, n do
        local t
        t, p = u8(s, p)
        if t == 0 then
            proto.k[i] = { t = 0 }
        elseif t == 1 then
            local b
            b, p = u8(s, p)
            proto.k[i] = { t = 1, v = b ~= 0 }
        elseif t == 3 then
            local raw = s:sub(p, p + 7)
            p = p + 8
            proto.k[i] = { t = 3, raw = raw }
        elseif t == 4 then
            local v
            v, p = read_string(s, p, le, sw)
            proto.k[i] = { t = 4, v = v }
        else
            error("unknown constant type " .. tostring(t))
        end
    end

    n, p = u32(s, p, le)
    proto.p = {}
    for i = 1, n do
        proto.p[i], p = read_proto(s, p, le, sw)
    end

    -- debug: lineinfo
    n, p = u32(s, p, le)
    p = p + n * 4
    -- debug: locvars
    n, p = u32(s, p, le)
    for i = 1, n do
        local _
        _, p = read_string(s, p, le, sw)
        _, p = u32(s, p, le)
        _, p = u32(s, p, le)
    end
    -- debug: upvalue names
    n, p = u32(s, p, le)
    for i = 1, n do
        local _
        _, p = read_string(s, p, le, sw)
    end

    return proto, p
end

function M.parse(data)
    if #data < 12 then return nil, "short file" end
    if data:sub(1, 4) ~= "\27Lua" then return nil, "not a lua chunk" end
    local ver = string.byte(data, 5)
    if ver ~= 0x51 then
        return nil, "unsupported bytecode version 0x" .. string.format("%02x", ver) .. " (need 5.1)"
    end
    local le = string.byte(data, 7) == 1
    local intsz = string.byte(data, 8)
    local sizet = string.byte(data, 9)
    local insz = string.byte(data, 10)
    local numsz = string.byte(data, 11)
    if intsz ~= 4 or (sizet ~= 4 and sizet ~= 8) or insz ~= 4 or numsz ~= 8 then
        return nil, "unexpected word sizes"
    end
    local proto, p = read_proto(data, 13, le, sizet)
    return { proto = proto, le = le, size = p }
end

-- decode a raw 8-byte lua_Number (double)
function M.decode_number(raw, le)
    local b = { string.byte(raw, 1, 8) }
    if not le then
        local r = {}
        for i = 1, 8 do r[i] = b[9 - i] end
        b = r
    end
    local sign = b[8] >= 128 and -1 or 1
    local e = (b[8] % 128) * 16 + math.floor(b[7] / 16)
    local m = b[1] + b[2] * 256 + b[3] * 65536 + b[4] * 16777216
        + b[5] * 4294967296 + b[6] * 1099511627776 + (b[7] % 16) * 281474976710656
    if e == 0 then
        if m == 0 then return sign * 0 end
        return sign * math.ldexp(m, -1074)
    elseif e == 2047 then
        if m == 0 then return sign * math.huge end
        return 0 / 0
    end
    return sign * math.ldexp(m + 4503599627370496, e - 1075)
end

return M
