-- language: Lua 5.1, file: cli/obfuscate.lua
-- lua cli/obfuscate.lua input.lua --key=... --out=... [--mode=source|vm]
--   [--level=paranoid|normal] [--keymode=embedded|external] [--verify]

local here = (arg[0] or "cli/obfuscate.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local util = require("util.utils")
local crypt = require("core.crypt")
local strings = require("transform.strings")
local junk = require("transform.junk")
local template = require("loader.template")
local bytecode = require("core.bytecode")
local vmser = require("core.vmserialize")
local vmtpl = require("loader.vm_template")

local function parse(argv)
    local o = { level = "paranoid", keymode = "embedded", mode = "source" }
    local i = 1
    while i <= #argv do
        local v = argv[i]
        local function val(name)
            if v == name then
                i = i + 1
                return argv[i]
            end
            local prefix = name .. "="
            if v:sub(1, #prefix) == prefix then
                return v:sub(#prefix + 1)
            end
        end
        local k = val("--key")
        if k then o.key = k end
        local out = val("--out")
        if out then o.out = out end
        local lvl = val("--level")
        if lvl then o.level = lvl end
        local km = val("--keymode")
        if km then o.keymode = km end
        local md = val("--mode")
        if md then o.mode = md end
        if v == "--verify" then o.verify = true end
        if v == "--help" then o.help = true end
        if v:sub(1, 1) ~= "-" and not o.input then o.input = v end
        i = i + 1
    end
    return o
end

local function usage()
    print("usage: lua cli/obfuscate.lua input.lua --key=<key> [--out=protected.lua]")
    print("       [--mode=source|vm] [--level=paranoid|normal]")
    print("       [--keymode=embedded|external] [--verify]")
end

local function hexlit(h)
    if #h == 0 then return '""' end
    local parts = {}
    for i = 1, #h, 1024 do
        parts[#parts + 1] = '"' .. h:sub(i, i + 1023) .. '"'
    end
    if #parts == 1 then return parts[1] end
    return "_T({" .. table.concat(parts, ",") .. "})"
end

local function numtable(t)
    local parts = {}
    for i = 1, #t do
        parts[#parts + 1] = tostring(t[i])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function keyinit_embedded(key, salt)
    local kt = crypt.hide_bytes(key, 17)
    local st = crypt.hide_bytes(salt, 29)
    return table.concat({
        "local KT = " .. numtable(kt),
        "local KB = {}",
        "for i = 1, #KT do KB[i] = _C((KT[i] - i * 17) % 256) end",
        "local KEY = _T(KB)",
        "local ST = " .. numtable(st),
        "local SB = {}",
        "for i = 1, #ST do SB[i] = _C((ST[i] - i * 29) % 256) end",
        "local SALT = _T(SB)",
    }, "\n")
end

local function keyinit_external(salt)
    local st = crypt.hide_bytes(salt, 29)
    return table.concat({
        'local KEY = os.getenv("SHROUD_KEY") or ""',
        "if #KEY == 0 then return end",
        "local ST = " .. numtable(st),
        "local SB = {}",
        "for i = 1, #ST do SB[i] = _C((ST[i] - i * 29) % 256) end",
        "local SALT = _T(SB)",
    }, "\n")
end

local function shell_run(cmd)
    local p = io.popen(cmd .. ' 2>&1; echo "__SHROUD_EXIT:$?"')
    local out = p:read("*a") or ""
    p:close()
    local code = tonumber(out:match("__SHROUD_EXIT:(%d+)") or "1")
    out = out:gsub("%s*__SHROUD_EXIT:%d+%s*$", "")
    return code, out
end

local function syntax_ok(path)
    local p = io.popen("luac -p " .. util.shellquote(path) .. " 2>&1")
    local out = p:read("*a") or ""
    p:close()
    if out:find("not found", 1, true) then
        return true, "skipped (luac not on PATH)"
    end
    return out == "", out
end

local function do_verify(o, key, out_path)
    local env = ""
    if o.keymode == "external" then
        env = "SHROUD_KEY=" .. util.shellquote(key)
    end
    local c1, out1 = shell_run("lua " .. util.shellquote(o.input))
    local c2, out2 = shell_run(env .. " lua " .. util.shellquote(out_path))
    util.write(root .. "/out/verify_original.txt", out1)
    util.write(root .. "/out/verify_protected.txt", out2)
    if c1 == c2 and out1 == out2 then
        print("[+] verify : output match (exit " .. c1 .. ", " .. #out1 .. " bytes)")
        return true
    end
    print("[!] verify : mismatch")
    print("--- original (exit " .. c1 .. ") ---")
    print(out1:sub(1, 1200))
    print("--- protected (exit " .. c2 .. ") ---")
    print(out2:sub(1, 1200))
    return false
end

local function make_key(o)
    local key = o.key
    if not key or key == "" then
        local alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        local t = {}
        for i = 1, 40 do
            local k = math.random(1, #alpha)
            t[i] = alpha:sub(k, k)
        end
        key = table.concat(t)
        print("[*] key    : generated (embedded) -> " .. key)
    else
        print("[*] key    : supplied (" .. #key .. " bytes)")
    end
    return key
end

local function build_vm(o, body, shebang, key, salt, out_path)
    local tmp_src = os.tmpname()
    local tmp_bc = os.tmpname()
    util.write(tmp_src, body)
    local cmd = "luac -s -o " .. util.shellquote(tmp_bc) .. " " .. util.shellquote(tmp_src)
    os.execute(cmd)
    local raw = util.read(tmp_bc)
    os.remove(tmp_src)
    os.remove(tmp_bc)
    if not raw or #raw < 12 then
        print("[!] luac failed. vm mode needs a Lua 5.1 luac on PATH")
        return false
    end
    local parsed, perr = bytecode.parse(raw)
    if not parsed then
        print("[!] bytecode parse: " .. tostring(perr))
        return false
    end
    local blob = vmser.serialize(parsed)
    local packed = crypt.pack(blob, key, salt, 0)
    local vars = {
        SHEBANG = shebang,
        KEYINIT = (o.keymode == "external") and keyinit_external(salt) or keyinit_embedded(key, salt),
        BLOB = hexlit(util.hex(packed)),
    }
    local rendered = util.polymorph(vmtpl.render(vars))
    local ok, werr = util.write(out_path, rendered)
    if not ok then
        print("[!] write failed: " .. tostring(werr))
        return false
    end
    print("[*] bytecode: " .. #raw .. " bytes -> " .. #blob .. " custom, remapped opcodes")
    print("[*] output : " .. out_path .. " (" .. #rendered .. " bytes)")
    print("[*] mode   : vm | keymode: " .. o.keymode)
    local sok, serr = syntax_ok(out_path)
    if not sok then
        print("[!] syntax check failed: " .. serr)
        return false
    end
    print("[*] syntax : " .. (serr == "" and "ok" or serr))
    if o.verify and not do_verify(o, key, out_path) then return false end
    return true
end

local function build_source(o, body, shebang, key, salt, out_path)
    local decname = util.randname("__sh")
    while body:find(decname, 1, true) do
        decname = util.randname("__sh")
    end

    local encoded, pool = strings.encode(body, decname)
    print("[*] strings: " .. #pool .. " literal(s) moved to encrypted pool")

    local payload = "local " .. decname .. " = " .. decname .. "\n"
    if o.level == "paranoid" then
        payload = payload .. junk.noise()
    end
    payload = payload .. encoded

    local pool_blob = crypt.pack(crypt.serialize_pool(pool), key, salt, 0)

    local chunks = {}
    local checks = {}
    local order = {}
    local off = 1
    local idx = 0
    while off <= #payload do
        local size
        if o.level == "paranoid" then
            size = math.random(8192, 20480)
        else
            size = 65536
        end
        local piece = payload:sub(off, off + size - 1)
        off = off + size
        idx = idx + 1
        chunks[idx] = util.hex(crypt.pack(piece, key, salt, idx))
        checks[idx] = util.adler(piece)
        order[#order + 1] = idx
    end
    if idx == 0 then
        idx = 1
        chunks[1] = util.hex(crypt.pack("", key, salt, 1))
        checks[1] = util.adler("")
        order[1] = 1
    end
    for i = #order, 2, -1 do
        local j = math.random(1, i)
        order[i], order[j] = order[j], order[i]
    end

    local decoys = {}
    if o.level == "paranoid" then
        local budget = math.max(128, math.min(8192, math.floor(#payload / 2)))
        for d = 1, 2 do
            local n = math.random(math.max(64, math.floor(budget / 2)), budget)
            local t = {}
            for i = 1, n do t[i] = string.format("%02x", math.random(0, 255)) end
            decoys[#decoys + 1] = '["' .. (1000 + d) .. '"]="' .. table.concat(t) .. '"'
        end
    end

    local chunk_lit = {}
    for i = 1, idx do
        chunk_lit[#chunk_lit + 1] = "[" .. i .. "]=" .. hexlit(chunks[i])
    end

    local check_lit = {}
    for i = 1, idx do
        check_lit[#check_lit + 1] = "[" .. i .. "]=" .. tostring(checks[i])
    end

    local vars = {
        SHEBANG = shebang,
        KEYINIT = (o.keymode == "external") and keyinit_external(salt) or keyinit_embedded(key, salt),
        POOL = hexlit(util.hex(pool_blob)),
        CHUNKS = "{" .. table.concat(chunk_lit, ",") .. "}",
        CHECK = "{" .. table.concat(check_lit, ",") .. "}",
        ORDER = "{" .. table.concat(order, ",") .. "}",
        NAME = string.format("%q", decname),
        DECOYS = "{" .. table.concat(decoys, ",") .. "}",
    }

    local rendered = util.polymorph(template.render(vars))
    local ok, werr = util.write(out_path, rendered)
    if not ok then
        print("[!] write failed: " .. tostring(werr))
        return false
    end
    print("[*] chunks : " .. idx .. " (encrypted, shuffled order, adler checked)")
    print("[*] output : " .. out_path .. " (" .. #rendered .. " bytes)")
    print("[*] mode   : source | level: " .. o.level .. " | keymode: " .. o.keymode)
    local sok, serr = syntax_ok(out_path)
    if not sok then
        print("[!] syntax check failed: " .. serr)
        return false
    end
    print("[*] syntax : " .. (serr == "" and "ok" or serr))
    if o.verify and not do_verify(o, key, out_path) then return false end
    return true
end

local function main()
    util.seed()
    local o = parse(arg)
    if o.help or not o.input then
        usage()
        os.exit(o.help and 0 or 1)
    end

    local src, err = util.read(o.input)
    if not src then
        print("[!] read failed: " .. tostring(err))
        os.exit(1)
    end
    print("[*] input  : " .. o.input .. " (" .. #src .. " bytes)")

    local key = make_key(o)
    local salt = util.randbytes(16)

    local body = src
    local shebang = ""
    if body:sub(1, 2) == "#!" then
        local nl = body:find("\n", 1, true)
        if nl then
            shebang = body:sub(1, nl)
            body = body:sub(nl + 1)
        else
            shebang = body .. "\n"
            body = ""
        end
        print("[*] shebang: preserved")
    end

    local out_path = o.out or (o.input:gsub("%.lua$", "") .. ".shroud.lua")
    local ok
    if o.mode == "vm" then
        ok = build_vm(o, body, shebang, key, salt, out_path)
    else
        ok = build_source(o, body, shebang, key, salt, out_path)
    end
    if not ok then os.exit(1) end
end

main()
