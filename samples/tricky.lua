local function id(x) return x end
local t = { ["a b"] = 1, ["q\"q"] = 2 }
print(id"call sugar")
print(t["a b"], t['q"q'])
print("tab\tnewline\nquote\"backslash\\octal\065")
print([==[long ]] with [=[nested]=] markers]==])
local s = "a\
b"
print(s)
--[==[ comment
with "strings" and [[ stuff
]==]
print(("method"):sub(2, 3))
print(#[[x]])
print(("%d-%s"):format(7, "ok"))
