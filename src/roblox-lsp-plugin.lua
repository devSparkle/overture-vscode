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
			return string.gsub(string.gsub(FullName, "%.([^%.]-[@]%d+%.%d+%.%d+-?%w*)", "[\"%1\"]"), "%.(%a-[ ][^%.]*)", "[\"%1\"]")
		end
	end
end

function OnSetText(uri, text)
	local diffs = {}
	
	for start, content, finish in text:gmatch('()Overture:LoadLibrary(%b())()') do
		local NamedImports = {}
		local Name
		
		for Match in content:gmatch('%b""') do
			if not Name then
				Name = Match:sub(2, -2)
			else
				table.insert(NamedImports, Match:sub(2, -2))
			end
		end
		
		local FullName = (Name and _GetMatchingModule(Name)) or nil
		
		if FullName then
			log.debug("Found oLibrary:", FullName, "for", Name)
			
			if #NamedImports > 0 then
				for Index, Import in ipairs(NamedImports) do
					NamedImports[Index] = (string.format("require(game.%s)", FullName) .. "." .. Import)
				end
				
				table.insert(diffs, {
					start = start,
					finish = finish - 1,
					text = table.concat(NamedImports, ", "),
				})
			else
				table.insert(diffs, {
					start = start,
					finish = finish - 1,
					text = string.format("require(game.%s)", FullName),
				})
			end
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