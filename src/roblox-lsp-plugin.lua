local rojo = require("library.rojo")
local fs = require("bee.filesystem")
local util = require("utility")
local json = require("json")
local log = require("log")

local function _IsoLibrary(FilePath)
	local MetaFilePath = string.gsub(FilePath, "/([^/]*)%.[^/]*$", "/%1.meta.json")
	if not fs.exists(fs.current_path() / MetaFilePath) then return false end
	
	local DecodeSuccess, Meta = pcall(json.decode, util.loadFile(MetaFilePath))
	if not DecodeSuccess then return false end
	if not Meta then return false end
	if not Meta.properties then return false end
	if not Meta.properties.Tags then return false end
	
	for _, Tag in next, Meta.properties.Tags do
		if Tag == "oLibrary" then
			return true
		end
	end
	
	return false
end

local function _GetMatchingModule(MatchName)
	for FullName, FilePath in next, rojo.SourceMap do
		local Success, Match = pcall(string.find, FullName, "%." .. MatchName .. "$")
		
		if (Success and Match) and _IsoLibrary(FilePath) then
			return string.gsub(string.gsub(FullName, "%.([^%.]-[@]%d+%.%d+%.%d+)", "[\"%1\"]"), "%.(%a-[ ][^%.]*)", "[\"%1\"]")
		end
	end
end

function OnSetText(uri, text)
	local diffs = {}
	
	for start, name, finish in text:gmatch("()Overture:LoadLibrary%(\"(.-)\"%)()") do
		local FullName = _GetMatchingModule(name)
		
		if FullName then
			log.debug("Found oLibrary:", FullName, "for", name)
			
			table.insert(diffs, {
				start = start,
				finish = finish - 1,
				text = string.format("require(game.%s)", FullName),
			})
		end
	end
	
	return diffs
end

function OnCompletion(uri, text, offset)
	local items = {}
	
	if text:sub(0, offset):match("Overture:LoadLibrary%(\"$") then
		for FullName, FilePath in next, rojo.SourceMap do
			if _IsoLibrary(FilePath) then
				table.insert(items, {
					kind = 9,
					label = string.match(FullName, "%.([^%.]*)$"),
					detail = "`oLibrary`"
				})
			end
		end
	end
	
	return items
end