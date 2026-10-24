-- language: Lua 5.1, file: loader/template.lua
-- self-contained runtime emitted into every protected file.

local M = {}

local TPL = [====[
@@SHEBANG@@-- lua-shroud | protected build
local _B, _C, _S = string.byte, string.char, string.sub
local _F, _T = math.floor, table.concat
local _G = _G
local XOR = {}
do
  local function x4(a, b)
    local r, p = 0, 1
    for i = 1, 4 do
      if a % 2 ~= b % 2 then r = r + p end
      a = _F(a / 2); b = _F(b / 2); p = p * 2
    end
    return r
  end
  local k = 0
  for a = 0, 15 do
    for b = 0, 15 do
      XOR[k] = x4(a, b)
      k = k + 1
    end
  end
end
local function bx(a, b)
  local al, bl = a % 16, b % 16
  local ah, bh = _F(a / 16), _F(b / 16)
  return XOR[ah * 16 + bh] * 16 + XOR[al * 16 + bl]
end
local function rc4(k, d)
  local S = {}
  local kl = #k
  for i = 0, 255 do S[i] = i end
  local j = 0
  for i = 0, 255 do
    j = (j + S[i] + _B(k, (i % kl) + 1)) % 256
    S[i], S[j] = S[j], S[i]
  end
  local i, j2 = 0, 0
  local o = {}
  for p = 1, #d do
    i = (i + 1) % 256
    j2 = (j2 + S[i]) % 256
    S[i], S[j2] = S[j2], S[i]
    o[p] = _C(bx(_B(d, p), S[(S[i] + S[j2]) % 256]))
  end
  return _T(o)
end
local function unroll(k, d)
  local o = {}
  local kl = #k
  for i = 1, #d do
    local kb = _B(k, ((i - 1) % kl) + 1)
    local rb = bx(kb, (i * 131) % 256)
    o[i] = _C(bx(_B(d, i), rb))
  end
  return _T(o)
end
local function hexlit(h)
  local o = {}
  local j = 1
  for i = 1, #h, 2 do
    o[j] = _C(tonumber(_S(h, i, i + 1), 16))
    j = j + 1
  end
  return _T(o)
end
local function adler(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + _B(s, i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end
@@KEYINIT@@
local function dec(c, idx)
  return unroll(KEY, rc4(KEY .. SALT .. tostring(idx), hexlit(c)))
end
local DC = @@DECOYS@@
local pool = {}
do
  local raw = dec(@@POOL@@, 0)
  local i = 1
  while i <= #raw do
    local l = _B(raw, i) * 16777216 + _B(raw, i + 1) * 65536 + _B(raw, i + 2) * 256 + _B(raw, i + 3)
    pool[#pool + 1] = _S(raw, i + 4, i + 3 + l)
    i = i + 4 + l
  end
end
local CH = @@CHUNKS@@
local CK = @@CHECK@@
local ORD = @@ORDER@@
local parts = {}
for oi = 1, #ORD do
  local id = ORD[oi]
  local p = dec(CH[id], id)
  if adler(p) ~= CK[id] then return end
  parts[id] = p
end
local src = _T(parts)
local N = @@NAME@@
_G[N] = function(i) return pool[i] end
local fn = (loadstring or load)(src, "=shroud")
if not fn then _G[N] = nil; return end
fn(...)
_G[N] = nil
]====]

function M.render(vars)
    local out = TPL
    for k, v in pairs(vars) do
        out = out:gsub("@@" .. k .. "@@", function() return v end)
    end
    return out
end

return M
