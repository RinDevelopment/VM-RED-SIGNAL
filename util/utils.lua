-- language: Lua 5.1, file: util/utils.lua
-- shared primitives. pure 5.1, no bit library.

local M = {}

function M.read(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local d = f:read("*a")
    f:close()
    return d
end

function M.write(path, data)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(data)
    f:close()
    return true
end

function M.hex(s)
    local t = {}
    for i = 1, #s do
        t[i] = string.format("%02x", string.byte(s, i))
    end
    return table.concat(t)
end

function M.adler(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + string.byte(s, i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

function M.shellquote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.basename(p)
    return (p:match("([^/\\]+)$")) or p
end

function M.dirname(p)
    return (p:match("^(.*)[/\\][^/\\]*$")) or "."
end

function M.randbytes(n)
    local t = {}
    for i = 1, n do
        t[i] = string.char(math.random(0, 255))
    end
    return table.concat(t)
end

function M.seed()
    math.randomseed(os.time() + math.floor(os.clock() * 1000000))
    for i = 1, 32 do math.random() end
end

function M.randname(prefix)
    local t = {}
    local chars = "0123456789abcdef"
    for i = 1, 10 do
        local k = math.random(1, #chars)
        t[i] = chars:sub(k, k)
    end
    return (prefix or "_") .. table.concat(t)
end

-- rename internal loader identifiers per build. global names are excluded
-- because a few locals intentionally shadow globals on the right-hand side.
local POLY = {
    "_B", "_C", "_S", "_F", "_T", "XOR", "bx", "rc4", "unroll", "hexlit",
    "adler", "dec", "pool", "CH", "CK", "ORD", "parts", "src", "N", "fn",
    "KT", "KB", "KEY", "ST", "SB", "SALT", "DC", "BLOB", "bp", "rb", "rw",
    "rs", "rstr", "dbl", "inv", "rproto", "run", "mkcl", "R", "open", "top",
    "code", "K", "P", "maxstack", "gr", "sr", "truth", "rk", "invoke",
    "main", "le", "opn", "va", "np", "ins", "op", "A", "B", "C", "Bx",
    "child", "cu", "desc", "dop", "db", "base", "f", "res", "nargs", "idx",
    "limit", "cont", "step", "v", "i", "j", "k", "p", "e", "o", "q",
    "pack", "n", "t", "c",
}

function M.polymorph(text)
    local head, rest = "", text
    if text:sub(1, 2) == "#!" then
        local nl = text:find("\n", 1, true)
        if nl then
            head = text:sub(1, nl)
            rest = text:sub(nl + 1)
        end
    end
    local chars = "0123456789abcdef"
    local t = {}
    for i = 1, 6 do
        local k = math.random(1, #chars)
        t[i] = chars:sub(k, k)
    end
    local suffix = "_" .. table.concat(t)
    for _, name in ipairs(POLY) do
        rest = rest:gsub("%f[%w_]" .. name .. "%f[^%w_]", name .. suffix)
    end
    return head .. rest
end

return M
