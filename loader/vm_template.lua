-- language: Lua 5.1, file: loader/vm_template.lua
-- custom bytecode VM. source text never exists at runtime, no loadstring.

local M = {}

local TPL = [====[
@@SHEBANG@@-- lua-shroud | vm build
local _B, _C, _S = string.byte, string.char, string.sub
local _F, _T = math.floor, table.concat
local _G = _G
local unpack = table.unpack or unpack
local function pack(...) return { n = select('#', ...), ... } end
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
@@KEYINIT@@
local function dec(c)
  return unroll(KEY, rc4(KEY .. SALT .. "0", hexlit(c)))
end
if type(debug) == "table" and type(debug.gethook) == "function" then
  local ok, h = pcall(debug.gethook)
  if ok and h then return end
end
local BLOB = dec(@@BLOB@@)
local bp = 1
local function rb() local v = _B(BLOB, bp); bp = bp + 1; return v end
local function rw()
  local a, b, c, d = _B(BLOB, bp, bp + 3)
  bp = bp + 4
  return a + b * 256 + c * 65536 + d * 16777216
end
local function rs(n)
  local v = _S(BLOB, bp, bp + n - 1)
  bp = bp + n
  return v
end
local function rstr()
  local n = rw()
  if n == 0 then return nil end
  local v = rs(n - 1)
  bp = bp + 1
  return v
end
local function dbl(raw, le)
  local b = { _B(raw, 1, 8) }
  if not le then
    local r = {}
    for i = 1, 8 do r[i] = b[9 - i] end
    b = r
  end
  local sign = b[8] >= 128 and -1 or 1
  local e = (b[8] % 128) * 16 + _F(b[7] / 16)
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
if rs(4) ~= "SHRD" then return end
local ver = rb()
local le = rb() == 1
local opn = rb()
local inv = {}
for i = 0, opn - 1 do inv[rb()] = i end
local function rproto()
  local p = {}
  p.np = rb(); p.va = rb(); p.nups = rb(); p.maxstack = rb()
  local cn = rw()
  p.code = {}
  local skip = false
  for i = 1, cn do
    local w = rw()
    if skip then
      p.code[i] = w
      skip = false
    else
      local cop = w % 64
      local std = inv[cop]
      local ins = (w - cop) + std
      p.code[i] = ins
      if std == 34 then
        local C = _F(ins / 16384) % 512
        if C == 0 then skip = true end
      end
    end
  end
  local kn = rw()
  p.k = {}
  for i = 1, kn do
    local t = rb()
    if t == 1 then
      p.k[i] = rb() ~= 0
    elseif t == 3 then
      p.k[i] = dbl(rs(8), le)
    elseif t == 4 then
      p.k[i] = rstr()
    end
  end
  local pn = rw()
  p.p = {}
  for i = 1, pn do p.p[i] = rproto() end
  return p
end
local run
local function mkcl(p, u, e)
  return function(...)
    local r = run(p, u, pack(...), e)
    return unpack(r, 1, r.n)
  end
end
run = function(proto, ups, vargs, venv)
  local R = {}
  local open = {}
  local pc = 1
  local top = proto.maxstack
  local code = proto.code
  local K = proto.k
  local P = proto.p
  local maxstack = proto.maxstack
  local np = proto.np
  for i = 0, np - 1 do R[i] = vargs[i + 1] end
  local va = { n = 0 }
  if proto.va ~= 0 then
    local en = vargs.n - np
    if en > 0 then
      for j = 1, en do va[j] = vargs[np + j] end
      va.n = en
    end
  end
  local function gr(r)
    local b = open[r]
    if b then return b.v end
    return R[r]
  end
  local function sr(r, v)
    local b = open[r]
    if b then b.v = v else R[r] = v end
  end
  local function truth(v) return v ~= nil and v ~= false end
  local function rk(x)
    if x < 256 then return gr(x) end
    return K[x - 255]
  end
  local function invoke(f, args, n)
    if type(f) ~= "function" then
      local mt = getmetatable(f)
      local h = mt and mt.__call
      if not h then
        error("attempt to call a " .. type(f) .. " value", 0)
      end
      local a2 = { f }
      for i = 1, n do a2[i + 1] = args[i] end
      return invoke(h, a2, n + 1)
    end
    return pack(f(unpack(args, 1, n)))
  end
  while true do
    local ins = code[pc]
    local op = ins % 64
    local A = _F(ins / 64) % 256
    local C = _F(ins / 16384) % 512
    local B = _F(ins / 8388608) % 512
    local Bx = B * 512 + C
    pc = pc + 1
    if op == 0 then
      sr(A, gr(B))
    elseif op == 1 then
      sr(A, K[Bx + 1])
    elseif op == 2 then
      sr(A, B ~= 0)
      if C ~= 0 then pc = pc + 1 end
    elseif op == 3 then
      for i = A, A + B do sr(i, nil) end
    elseif op == 4 then
      sr(A, ups[B + 1].v)
    elseif op == 5 then
      sr(A, venv[K[Bx + 1]])
    elseif op == 6 then
      sr(A, gr(B)[rk(C)])
    elseif op == 7 then
      venv[K[Bx + 1]] = gr(A)
    elseif op == 8 then
      ups[B + 1].v = gr(A)
    elseif op == 9 then
      gr(A)[rk(B)] = rk(C)
    elseif op == 10 then
      sr(A, {})
    elseif op == 11 then
      local b = gr(B)
      sr(A + 1, b)
      sr(A, b[rk(C)])
    elseif op == 12 then
      sr(A, rk(B) + rk(C))
    elseif op == 13 then
      sr(A, rk(B) - rk(C))
    elseif op == 14 then
      sr(A, rk(B) * rk(C))
    elseif op == 15 then
      sr(A, rk(B) / rk(C))
    elseif op == 16 then
      sr(A, rk(B) % rk(C))
    elseif op == 17 then
      sr(A, rk(B) ^ rk(C))
    elseif op == 18 then
      sr(A, -gr(B))
    elseif op == 19 then
      sr(A, not truth(gr(B)))
    elseif op == 20 then
      sr(A, #gr(B))
    elseif op == 21 then
      local v = gr(B)
      for i = B + 1, C do v = v .. gr(i) end
      sr(A, v)
    elseif op == 22 then
      pc = pc + (Bx - 131071)
    elseif op == 23 then
      if (rk(B) == rk(C)) ~= (A ~= 0) then pc = pc + 1 end
    elseif op == 24 then
      if (rk(B) < rk(C)) ~= (A ~= 0) then pc = pc + 1 end
    elseif op == 25 then
      if (rk(B) <= rk(C)) ~= (A ~= 0) then pc = pc + 1 end
    elseif op == 26 then
      if truth(gr(A)) ~= (C ~= 0) then pc = pc + 1 end
    elseif op == 27 then
      if truth(gr(B)) == (C ~= 0) then sr(A, gr(B)) else pc = pc + 1 end
    elseif op == 28 then
      local nargs = (B == 0) and (top - A) or (B - 1)
      local args = {}
      for j = 1, nargs do args[j] = gr(A + j) end
      local res = invoke(gr(A), args, nargs)
      if C == 0 then
        for j = 1, res.n do sr(A + j - 1, res[j]) end
        top = A + res.n - 1
      else
        for j = 1, C - 1 do sr(A + j - 1, res[j]) end
      end
    elseif op == 29 then
      local nargs = (B == 0) and (top - A) or (B - 1)
      local args = {}
      for j = 1, nargs do args[j] = gr(A + j) end
      return invoke(gr(A), args, nargs)
    elseif op == 30 then
      local n = (B == 0) and (top - A + 1) or (B - 1)
      local res = { n = n }
      for j = 1, n do res[j] = gr(A + j - 1) end
      return res
    elseif op == 31 then
      local step = gr(A + 2)
      local idx = gr(A) + step
      sr(A, idx)
      local limit = gr(A + 1)
      local cont
      if step > 0 then cont = idx <= limit else cont = limit <= idx end
      if cont then
        pc = pc + (Bx - 131071)
        sr(A + 3, idx)
      end
    elseif op == 32 then
      sr(A, gr(A) - gr(A + 2))
      pc = pc + (Bx - 131071)
    elseif op == 33 then
      local f = gr(A)
      local res = invoke(f, { gr(A + 1), gr(A + 2) }, 2)
      if res[1] ~= nil then sr(A + 2, res[1]) else pc = pc + 1 end
      for j = 1, C do sr(A + 2 + j, res[j]) end
    elseif op == 34 then
      local n = (B == 0) and (top - A) or B
      local c = C
      if c == 0 then c = code[pc]; pc = pc + 1 end
      local t = gr(A)
      local base = (c - 1) * 50
      for j = 1, n do t[base + j] = gr(A + j) end
    elseif op == 35 then
      for r = A, maxstack do
        local b = open[r]
        if b then R[r] = b.v; open[r] = nil end
      end
    elseif op == 36 then
      local child = P[Bx + 1]
      local cu = {}
      for i = 1, child.nups do
        local desc = code[pc]
        pc = pc + 1
        local dop = desc % 64
        local db = _F(desc / 8388608) % 512
        if dop == 0 then
          local box = open[db]
          if not box then box = { v = R[db] }; open[db] = box end
          cu[i] = box
        else
          cu[i] = ups[db + 1]
        end
      end
      sr(A, mkcl(child, cu, venv))
    elseif op == 37 then
      local n = (B == 0) and va.n or (B - 1)
      for j = 1, n do sr(A + j - 1, va[j]) end
      if B == 0 then top = A + n - 1 end
    else
      error("bad opcode " .. tostring(op), 0)
    end
  end
end
local main = rproto()
run(main, {}, { n = select('#', ...), ... }, _G)
]====]

function M.render(vars)
    local out = TPL
    for k, v in pairs(vars) do
        out = out:gsub("@@" .. k .. "@@", function() return v end)
    end
    return out
end

return M
