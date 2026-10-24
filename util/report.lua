-- language: Lua 5.1, file: util/report.lua
-- terminal presentation: banner, fields, staged progress, summary.
-- color is optional; quiet mode keeps stdout clean and sends errors to stderr.

local M = {}

local C = {
    reset = "\27[0m",
    dim = "\27[2m",
    bold = "\27[1m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    cyan = "\27[36m",
}

local quiet = false
local color = false
local label_width = 10

local function paint(s, code)
    if not color then return s end
    return code .. s .. C.reset
end

local function out(s)
    if quiet then return end
    io.write(s)
    io.flush()
end

local function err(s)
    io.stderr:write(s .. "\n")
end

local function one_line(s)
    return tostring(s or "failed"):gsub("[\r\n]+", " ")
end

function M.setup(opts)
    opts = opts or {}
    quiet = opts.quiet and true or false
    color = opts.color and not quiet or false
end

function M.is_tty()
    if package.config:sub(1, 1) ~= "/" then return false end
    local r = os.execute("test -t 1 >/dev/null 2>&1")
    if type(r) == "number" then return r == 0 end
    return r == true
end

function M.size(n)
    n = tonumber(n) or 0
    if n < 1024 then return n .. " B" end
    if n < 1048576 then return string.format("%.1f KB", n / 1024) end
    return string.format("%.1f MB", n / 1048576)
end

function M.banner(mode)
    if quiet then return end
    local label = (mode == "vm") and "vm pipeline" or "source pipeline"
    out(paint("lua-shroud", C.bold .. C.cyan)
        .. paint("  ·  ", C.dim)
        .. paint(label, C.bold) .. "\n")
    out(paint("source in. nothing readable out.", C.dim) .. "\n")
end

function M.field(label, value)
    if quiet then return end
    out(paint(string.format("%-" .. label_width .. "s", label), C.dim)
        .. "  " .. tostring(value) .. "\n")
end

function M.begin(n, total, label)
    local started = os.clock()
    if quiet then return started end
    local tag = string.format("[%d/%d]", n, total)
    out(paint(tag, C.dim) .. " "
        .. paint(string.format("%-" .. label_width .. "s", label), C.bold)
        .. paint(" ... ", C.dim))
    return started
end

function M.done(started, detail)
    if quiet then return end
    local elapsed = string.format("%.2fs", os.clock() - started)
    local tail = elapsed
    if detail and #tostring(detail) > 0 then
        tail = tostring(detail) .. paint("  ·  ", C.dim) .. elapsed
    end
    out(paint("ok", C.green) .. "  " .. paint(tail, C.dim) .. "\n")
end

function M.fail(started, detail)
    local msg = one_line(detail)
    if quiet then
        err("lua-shroud: " .. msg)
        return
    end
    local elapsed = string.format("%.2fs", os.clock() - started)
    out(paint("fail", C.red) .. "  " .. paint(msg, C.dim)
        .. paint("  ·  " .. elapsed, C.dim) .. "\n")
end

function M.note(label, value)
    if quiet then return end
    out(paint(label, C.dim) .. "  " .. tostring(value) .. "\n")
end

function M.detail(label, text)
    local block = "--- " .. label .. " ---\n" .. tostring(text)
    if quiet then
        err(block)
    else
        out(paint(block, C.dim) .. "\n")
    end
end

function M.error(msg)
    err(paint("lua-shroud:", C.red) .. " " .. one_line(msg))
end

function M.finish(path, bytes, seconds)
    if quiet then return end
    out(paint(string.rep("─", 46), C.dim) .. "\n")
    out(paint("built", C.bold .. C.green) .. "  " .. tostring(path)
        .. paint("  ·  ", C.dim) .. M.size(bytes)
        .. paint("  ·  ", C.dim) .. string.format("%.2fs", seconds) .. "\n")
end

return M
