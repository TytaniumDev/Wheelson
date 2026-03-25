-- tests/benchmark_names_match.lua
local a = "PlayerOne-Realm"
local b = "PlayerOne-Realm"

local function NamesMatchOriginal(str1, str2)
    if not str1 or not str2 then return false end
    if not str1:find("-") then str1 = str1 .. "-Realm" end
    if not str2:find("-") then str2 = str2 .. "-Realm" end
    return str1 == str2
end

local function NamesMatchOptimized(str1, str2)
    if not str1 or not str2 then return false end
    if str1 == str2 then return true end
    if not str1:find("-", 1, true) then str1 = str1 .. "-Realm" end
    if not str2:find("-", 1, true) then str2 = str2 .. "-Realm" end
    return str1 == str2
end

local function format_output(name, time)
    print(string.format("%-20s %.6fs", name .. ":", time))
end

print("=== NamesMatch Benchmark (1,000,000 iterations) ===")

local t1 = os.clock()
for i = 1, 1000000 do
    NamesMatchOriginal(a, b)
end
format_output("Original Match", os.clock() - t1)

local t2 = os.clock()
for i = 1, 1000000 do
    NamesMatchOptimized(a, b)
end
format_output("Optimized Match", os.clock() - t2)

a = "PlayerOne"
b = "PlayerTwo-Realm"
local t3 = os.clock()
for i = 1, 1000000 do
    NamesMatchOriginal(a, b)
end
format_output("Original Mismatch", os.clock() - t3)

local t4 = os.clock()
for i = 1, 1000000 do
    NamesMatchOptimized(a, b)
end
format_output("Optimized Mismatch", os.clock() - t4)
