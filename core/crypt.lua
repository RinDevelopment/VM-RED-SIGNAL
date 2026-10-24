-- language: Lua 5.1, file: core/crypt.lua
-- multi-layer packing: rolling xor -> rc4. pure arithmetic, no bit library.

local M = {}

local X = {}
do
    local function x4(a, b)
        local r, p = 0, 1
        for i = 1, 4 do
            if a % 2 ~= b % 2 then r = r + p end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            p = p * 2
        end
        return r
    end
    local idx = 0
    for a = 0, 15 do
        for b = 0, 15 do
            X[idx] = x4(a, b)
            idx = idx + 1
        end
    end
end

local function bx(a, b)
    local al = a % 16
    local ah = math.floor(a / 16)
    local bl = b % 16
    local bh = math.floor(b / 16)
    return X[ah * 16 + bh] * 16 + X[al * 16 + bl]
end
M.bx = bx

-- xor plaintext with a key stream derived from key + position
function M.roll(key, data)
    if #key == 0 then return data end
    local out = {}
    local kl = #key
    for i = 1, #data do
        local b = string.byte(data, i)
        local kb = string.byte(key, ((i - 1) % kl) + 1)
        local rb = bx(kb, (i * 131) % 256)
        out[i] = string.char(bx(b, rb))
    end
    return table.concat(out)
end

function M.rc4(key, data)
    if #key == 0 then return data end
    local S = {}
    for i = 0, 255 do S[i] = i end
    local kl = #key
    local j = 0
    for i = 0, 255 do
        j = (j + S[i] + string.byte(key, (i % kl) + 1)) % 256
        S[i], S[j] = S[j], S[i]
    end
    local i, jj = 0, 0
    local out = {}
    for p = 1, #data do
        i = (i + 1) % 256
        jj = (jj + S[i]) % 256
        S[i], S[jj] = S[jj], S[i]
        out[p] = string.char(bx(string.byte(data, p), S[(S[i] + S[jj]) % 256]))
    end
    return table.concat(out)
end

-- cipher = rc4(key..salt..idx, roll(key, plain))
function M.pack(plain, key, salt, idx)
    local k2 = key .. salt .. tostring(idx)
    return M.rc4(k2, M.roll(key, plain))
end

function M.unpack(cipher, key, salt, idx)
    local k2 = key .. salt .. tostring(idx)
    return M.roll(key, M.rc4(k2, cipher))
end

-- length-prefixed pool serialization
function M.serialize_pool(tbl)
    local out = {}
    for i = 1, #tbl do
        local s = tbl[i]
        local l = #s
        out[#out + 1] = string.char(
            math.floor(l / 16777216) % 256,
            math.floor(l / 65536) % 256,
            math.floor(l / 256) % 256,
            l % 256
        )
        out[#out + 1] = s
    end
    return table.concat(out)
end

-- key bytes shifted by step*i so the literal never contains the raw key
function M.hide_bytes(s, step)
    local t = {}
    for i = 1, #s do
        t[i] = (string.byte(s, i) + step * i) % 256
    end
    return t
end

return M
