-- language: Lua 5.1, file: core/vmserialize.lua
-- remaps standard lua 5.1 opcodes into a per-build permutation and packs the
-- proto tree into a private binary blob. constants stay raw, blob gets encrypted.

local M = {}

local NOP = 38

local function u8(v)
    return string.char(v % 256)
end

local function u32(v)
    v = v % 4294967296
    return string.char(
        v % 256,
        math.floor(v / 256) % 256,
        math.floor(v / 65536) % 256,
        math.floor(v / 16777216) % 256
    )
end

local function str(s)
    if s == nil then return u32(0) end
    return u32(#s + 1) .. s .. "\0"
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function M.build_map()
    local std = {}
    for i = 0, NOP - 1 do std[#std + 1] = i end
    shuffle(std)
    local map = {}
    for i = 0, NOP - 1 do
        map[i] = std[i + 1]
    end
    return map
end

local function write_proto(proto, map, out)
    out[#out + 1] = u8(proto.numparams)
    out[#out + 1] = u8(proto.is_vararg)
    out[#out + 1] = u8(proto.nups)
    out[#out + 1] = u8(proto.maxstack)
    out[#out + 1] = u32(#proto.code)
    local skip = false
    for i = 1, #proto.code do
        local ins = proto.code[i]
        if skip then
            out[#out + 1] = u32(ins)
            skip = false
        else
            local op = ins % 64
            local remapped = (ins - op) + map[op]
            out[#out + 1] = u32(remapped)
            if op == 34 then
                local C = math.floor(ins / 16384) % 512
                if C == 0 then skip = true end
            end
        end
    end
    out[#out + 1] = u32(#proto.k)
    for i = 1, #proto.k do
        local k = proto.k[i]
        out[#out + 1] = u8(k.t)
        if k.t == 1 then
            out[#out + 1] = u8(k.v and 1 or 0)
        elseif k.t == 3 then
            out[#out + 1] = k.raw
        elseif k.t == 4 then
            out[#out + 1] = str(k.v)
        end
    end
    out[#out + 1] = u32(#proto.p)
    for i = 1, #proto.p do
        write_proto(proto.p[i], map, out)
    end
end

function M.serialize(parsed)
    local map = M.build_map()
    local out = { "SHRD", u8(1), u8(parsed.le and 1 or 0), u8(NOP) }
    for i = 0, NOP - 1 do
        out[#out + 1] = u8(map[i])
    end
    write_proto(parsed.proto, map, out)
    return table.concat(out), map
end

return M
