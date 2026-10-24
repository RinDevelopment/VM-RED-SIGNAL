-- language: Lua 5.1, file: cli/obfuscate.lua
-- lua cli/obfuscate.lua input.lua [--out=...] [--mode=vm|source]
--   [--level=paranoid|normal] [--keymode=embedded|external] [--verify]
--   [--key=...] [--quiet] [--no-color] [--version]
--   (--key is optional; embedded mode generates one when omitted)

local VERSION = "1.1.0"

local here = (arg[0] or "cli/obfuscate.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local util = require("util.utils")
local report = require("util.report")
local crypt = require("core.crypt")
local strings = require("transform.strings")
local junk = require("transform.junk")
local template = require("loader.template")
local bytecode = require("core.bytecode")
local vmser = require("core.vmserialize")
local vmtpl = require("loader.vm_template")

local function parse(argv)
    local o = { level = "paranoid", keymode = "embedded", mode = "vm" }
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
        if v == "--quiet" then o.quiet = true end
        if v == "--no-color" then o.nocolor = true end
        if v == "--version" then o.version = true end
        if v:sub(1, 1) ~= "-" and not o.input then o.input = v end
        i = i + 1
    end
    return o
end

local function usage()
    print("usage: lua cli/obfuscate.lua input.lua [--out=protected.lua]")
    print("       [--mode=vm|source] [--level=paranoid|normal]")
    print("       [--keymode=embedded|external] [--verify] [--key=<optional>]")
    print("       [--quiet] [--no-color] [--version]")
    print("       embedded mode needs no key; one is generated and hidden in the build")
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

local function encode_table(bytes, step, mask)
    local t = {}
    local stringy = type(bytes) == "string"
    for i = 1, #bytes do
        local b = stringy and string.byte(bytes, i) or bytes[i]
        t[i] = (b + step * i + mask) % 256
    end
    return t
end

-- key material never appears as bytes. four random xor shares are permuted,
-- then every share byte is shifted by a per-build step and mask. the loader
-- rebuilds the key in a loop and drops the share tables immediately.
local function keyinit_embedded(key, salt)
    local n = #key
    local perm = {}
    for i = 1, n do perm[i] = i end
    for i = n, 2, -1 do
        local j = math.random(1, i)
        perm[i], perm[j] = perm[j], perm[i]
    end

    local rnd = util.strongbytes(n * 4)
    local sh = { {}, {}, {}, {} }
    for i = 1, n do
        local k = string.byte(key, perm[i])
        local a = string.byte(rnd, i)
        local b = string.byte(rnd, n + i)
        local c = string.byte(rnd, 2 * n + i)
        local d = crypt.bx(crypt.bx(crypt.bx(k, a), b), c)
        sh[1][i], sh[2][i], sh[3][i], sh[4][i] = a, b, c, d
    end

    local s1, s2 = math.random(1, 251), math.random(1, 251)
    local s3, s4 = math.random(1, 251), math.random(1, 251)
    local m1, m2 = math.random(0, 255), math.random(0, 255)
    local m3, m4 = math.random(0, 255), math.random(0, 255)
    local sp, mp = math.random(1, 251), math.random(0, 255)
    local KA = encode_table(sh[1], s1, m1)
    local KB = encode_table(sh[2], s2, m2)
    local KC = encode_table(sh[3], s3, m3)
    local KD = encode_table(sh[4], s4, m4)
    local KP = {}
    for i = 1, n do
        KP[i] = ((perm[i] - 1 + sp * i + mp) % n) + 1
    end

    local ss, sm = math.random(1, 251), math.random(0, 255)
    local ST = encode_table(salt, ss, sm)

    return table.concat({
        "local KA = " .. numtable(KA),
        "local KB = " .. numtable(KB),
        "local KC = " .. numtable(KC),
        "local KD = " .. numtable(KD),
        "local KP = " .. numtable(KP),
        "local KEY = {}",
        "local kn = #KA",
        "for i = 1, kn do",
        "  local a = (KA[i] - " .. s1 .. " * i - " .. m1 .. ") % 256",
        "  local b = (KB[i] - " .. s2 .. " * i - " .. m2 .. ") % 256",
        "  local c = (KC[i] - " .. s3 .. " * i - " .. m3 .. ") % 256",
        "  local d = (KD[i] - " .. s4 .. " * i - " .. m4 .. ") % 256",
        "  local k = bx(bx(a, b), bx(c, d))",
        "  local p = ((KP[i] - 1 - " .. sp .. " * i - " .. mp .. ") % kn) + 1",
        "  KEY[p] = _C(k)",
        "end",
        "KA, KB, KC, KD, KP = nil, nil, nil, nil, nil",
        "KEY = _T(KEY)",
        "local ST = " .. numtable(ST),
        "local SALT = {}",
        "for i = 1, #ST do SALT[i] = _C((ST[i] - " .. ss .. " * i - " .. sm .. ") % 256) end",
        "SALT = _T(SALT)",
        "ST = nil",
    }, "\n")
end

local function keyinit_external(salt)
    local ss, sm = math.random(1, 251), math.random(0, 255)
    local st = encode_table(salt, ss, sm)
    return table.concat({
        'local KEY = os.getenv("SHROUD_KEY") or ""',
        "if #KEY == 0 then return end",
        "local ST = " .. numtable(st),
        "local SALT = {}",
        "for i = 1, #ST do SALT[i] = _C((ST[i] - " .. ss .. " * i - " .. sm .. ") % 256) end",
        "SALT = _T(SALT)",
        "ST = nil",
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

local function do_verify(o, key, out_path, stage, total)
    local started = report.begin(stage, total, "verify")
    local env = ""
    if o.keymode == "external" then
        env = "SHROUD_KEY=" .. util.shellquote(key)
    end
    local c1, out1 = shell_run("lua " .. util.shellquote(o.input))
    local c2, out2 = shell_run(env .. " lua " .. util.shellquote(out_path))
    util.write(root .. "/out/verify_original.txt", out1)
    util.write(root .. "/out/verify_protected.txt", out2)
    if c1 == c2 and out1 == out2 then
        report.done(started, "stdout + exit match")
        return true
    end
    report.fail(started, "mismatch")
    report.detail("original (exit " .. c1 .. ")", out1:sub(1, 1200))
    report.detail("protected (exit " .. c2 .. ")", out2:sub(1, 1200))
    return false
end

local function make_key(o)
    local supplied = o.key
    if (not supplied or supplied == "") and o.keymode == "external" then
        supplied = os.getenv("SHROUD_KEY")
    end

    if o.keymode == "external" then
        if not supplied or supplied == "" then
            report.error("external key mode needs --key or SHROUD_KEY")
            return nil
        end
        report.field("key", "external  ·  " .. #supplied .. " B  ·  not embedded")
        return supplied
    end

    if supplied and supplied ~= "" then
        local key = crypt.rc4(supplied, string.rep("\0", 64))
        report.field("key", "supplied  ·  " .. #supplied .. " B → 64 B  ·  embedded")
        return key
    end

    local key = crypt.rc4(util.strongbytes(32), string.rep("\0", 64))
    report.field("key", "generated  ·  64 B  ·  embedded, not shown")
    return key
end

local function build_vm(o, body, shebang, key, salt, out_path)
    local total = o.verify and 7 or 6
    local build_start = os.clock()

    local started = report.begin(1, total, "compile")
    local tmp_src = os.tmpname()
    local tmp_bc = os.tmpname()
    util.write(tmp_src, body)
    local cmd = "luac -s -o " .. util.shellquote(tmp_bc) .. " " .. util.shellquote(tmp_src)
    os.execute(cmd)
    local raw = util.read(tmp_bc)
    os.remove(tmp_src)
    os.remove(tmp_bc)
    if not raw or #raw < 12 then
        report.fail(started, "luac failed — vm mode needs Lua 5.1 luac on PATH")
        return false
    end
    report.done(started, report.size(#raw))

    started = report.begin(2, total, "parse")
    local parsed, perr = bytecode.parse(raw)
    if not parsed then
        report.fail(started, "bytecode parse: " .. tostring(perr))
        return false
    end
    report.done(started, "Lua 5.1 chunk")

    started = report.begin(3, total, "remap")
    local blob = vmser.serialize(parsed)
    report.done(started, report.size(#blob) .. " custom")

    started = report.begin(4, total, "encrypt")
    local packed = crypt.pack(blob, key, salt, 0)
    report.done(started, "XOR + RC4")

    started = report.begin(5, total, "render")
    local vars = {
        SHEBANG = shebang,
        KEYINIT = (o.keymode == "external") and keyinit_external(salt) or keyinit_embedded(key, salt),
        BLOB = hexlit(util.hex(packed)),
    }
    local rendered = util.polymorph(vmtpl.render(vars))
    local ok, werr = util.write(out_path, rendered)
    if not ok then
        report.fail(started, "write failed: " .. tostring(werr))
        return false
    end
    report.done(started, report.size(#rendered) .. " artifact")

    started = report.begin(6, total, "check")
    local sok, serr = syntax_ok(out_path)
    if not sok then
        report.fail(started, "syntax check failed: " .. tostring(serr))
        return false
    end
    report.done(started, (serr == "" and "syntax ok") or tostring(serr))

    if o.verify and not do_verify(o, key, out_path, 7, total) then return false end
    report.finish(out_path, #rendered, os.clock() - build_start)
    return true
end

local function build_source(o, body, shebang, key, salt, out_path)
    local total = o.verify and 6 or 5
    local build_start = os.clock()

    local started = report.begin(1, total, "strings")
    local decname = util.randname("__sh")
    while body:find(decname, 1, true) do
        decname = util.randname("__sh")
    end
    local encoded, pool = strings.encode(body, decname)
    report.done(started, #pool .. " literal(s)")

    started = report.begin(2, total, "pool")
    local pool_blob = crypt.pack(crypt.serialize_pool(pool), key, salt, 0)
    report.done(started, report.size(#pool_blob) .. " encrypted")

    started = report.begin(3, total, "chunks")
    local payload = "local " .. decname .. " = " .. decname .. "\n"
    if o.level == "paranoid" then
        payload = payload .. junk.noise()
    end
    payload = payload .. encoded

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
    report.done(started, idx .. " chunk(s), shuffled")

    started = report.begin(4, total, "render")
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
        report.fail(started, "write failed: " .. tostring(werr))
        return false
    end
    report.done(started, report.size(#rendered) .. " artifact")

    started = report.begin(5, total, "check")
    local sok, serr = syntax_ok(out_path)
    if not sok then
        report.fail(started, "syntax check failed: " .. tostring(serr))
        return false
    end
    report.done(started, (serr == "" and "syntax ok") or tostring(serr))

    if o.verify and not do_verify(o, key, out_path, 6, total) then return false end
    report.finish(out_path, #rendered, os.clock() - build_start)
    return true
end

local function main()
    util.seed()
    local o = parse(arg)

    if o.version then
        print("lua-shroud " .. VERSION)
        os.exit(0)
    end

    local color = (not o.nocolor) and (not o.quiet)
        and report.is_tty()
        and os.getenv("NO_COLOR") == nil
        and os.getenv("TERM") ~= "dumb"
    if (not o.nocolor) and os.getenv("FORCE_COLOR") and os.getenv("FORCE_COLOR") ~= "0" then
        color = true
    end
    report.setup({ quiet = o.quiet, color = color })

    if o.help or not o.input then
        usage()
        os.exit(o.help and 0 or 1)
    end

    if o.mode ~= "vm" and o.mode ~= "source" then
        report.error("mode must be vm or source")
        os.exit(1)
    end
    if o.keymode ~= "embedded" and o.keymode ~= "external" then
        report.error("keymode must be embedded or external")
        os.exit(1)
    end
    if o.level ~= "paranoid" and o.level ~= "normal" then
        report.error("level must be paranoid or normal")
        os.exit(1)
    end

    local src, err = util.read(o.input)
    if not src then
        report.error("read failed: " .. tostring(err))
        os.exit(1)
    end

    report.banner(o.mode)
    report.field("input", o.input .. "  ·  " .. report.size(#src))

    local key = make_key(o)
    if not key then os.exit(1) end
    local salt = util.strongbytes(16)

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
        report.field("shebang", "preserved")
    end

    local out_path = o.out or (o.input:gsub("%.lua$", "") .. ".shroud.lua")
    report.field("output", out_path)
    local ok
    if o.mode == "vm" then
        ok = build_vm(o, body, shebang, key, salt, out_path)
    else
        ok = build_source(o, body, shebang, key, salt, out_path)
    end
    if not ok then os.exit(1) end
end

main()
