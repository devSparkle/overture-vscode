local rojo = require("library.rojo")
local fs = require("bee.filesystem")
local util = require("utility")
local json = require("json")
local log = require("log")
local rbxlibs = require("library.rbxlibs")

local function _IsoLibrary(FilePath)
	local RawPath = string.gsub(FilePath, "([^/]*)%.[^/]*$", "%1.meta.json")

	local MetaFilePath = fs.path(RawPath)
	if tostring(MetaFilePath):find(tostring(fs.current_path())) then
		MetaFilePath = fs.relative(MetaFilePath, fs.current_path())
	end
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

local function GetLineFromOffset(Text, Offset)
	local Line = 1
	local Lines = {}
	local OffsetLine, OffsetIndex = nil, 1
	local Buffer = ""

	if not Text or Text:len() == 0 then return nil end
	
	for Index = 1, #Text do
		Buffer = Buffer .. Text:sub(Index, Index)
		if Index == Offset then
			OffsetLine, OffsetIndex = Line, #Buffer
		end
		
		if Text:sub(Index, Index) == "\n" or Index == #Text then
			Lines[Line] = Buffer
			Line = Line + 1
			Buffer = ""
		end
	end

	if OffsetLine then
		return Lines[OffsetLine], OffsetIndex
	else
		return nil, 0
	end
end

local function IsInCompleteField(Line, Offset, Matchers)
	local IsMatched, Match = false, nil
	for _, Matcher in pairs(Matchers) do
		if not Line:match(Matcher) then
			return false, nil
		end

		local Substring = string.sub(Line, 1, Offset)
		local WordOffset = 0

		for i = Offset, 1, -1 do
			if Substring:sub(i, i):match("%A") then
				break
			end
			WordOffset = WordOffset + 1
		end

		local Start = Offset - WordOffset
		if Line:sub(math.max(Start - #Matcher, 0) + 1, Start):match(Matcher) then
			IsMatched, Match = true, Line:sub((Offset - WordOffset) + 1, Offset)
		end
	end

	return IsMatched, Match
end

local function _GetMatchingModule(MatchName)
	for FullName, FilePath in next, rojo.SourceMap do
		local Success, Match = pcall(string.find, FullName, "%." .. MatchName .. "$")
		if (Success and Match) and _IsoLibrary(FilePath) then
			return string.gsub(string.gsub(FullName, "%.([^%.]-[@]%d+%.%d+%.%d+-?%w*)", "[\"%1\"]"), "%.(%a-[ -][^%.]*)", "[\"%1\"]")
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

function OnCompletion(url, text, offset)
	local items = {}
	
	local Line, LineOffset = GetLineFromOffset(text, offset)
	if not Line then return {} end

	do -- Overture:LoadLibrary
		local Matcher = {"local%s?", "Overture:LoadLibrary%([\"']?"}
		local IsMatch = IsInCompleteField(Line, LineOffset, Matcher)
		
		if IsMatch then
			for FullName, FilePath in next, rojo.SourceMap do
				if _IsoLibrary(FilePath) then
					local Title = string.match(FullName, "%.([^%.]*)$")
					local FileName = tostring(fs.path(FilePath):filename())
					table.insert(items, {
						kind = 7,
						label = Title,
						labelDetails = {
							detail = (" %s"):format(FileName),
							description = "oLibrary",
						},
					})
				end
			end

			return items
		end

	end

	do -- CreateElement
		local Matcher = {"CreateElement%([\"']"}
		local IsMatch, Word = IsInCompleteField(Line, LineOffset, Matcher)

		if IsMatch then
			for Key, _ in pairs(rbxlibs.CreatableInstances) do
				table.insert(items, {
					kind = 20,
					label = Key,
					labelDetails = {
						detail = (" %s"):format("Instance"),
						description = "React Component",
					},
				})
			end

			return items
		end


	end

	do -- CreateComponent or GetComponent
		local CreateComponent = {"CreateComponent%([\"']"}
		local GetComponent = {"GetComponent%([\"']"}
		local IsCreateComponentMatch = IsInCompleteField(Line, LineOffset, CreateComponent)
		local IsGetComponentMatch = IsInCompleteField(Line, LineOffset, GetComponent)

		if IsCreateComponentMatch or IsGetComponentMatch then
			for FullName, FilePath in next, rojo.SourceMap do
				if FullName:match(".UI.") then
					local Path = fs.path(FilePath)

					if not tostring(Path:stem()):match("%.") then
						local Title = string.match(FullName, "%.([^%.]*)$")
						
						table.insert(items, {
							kind = 4,
							label = Title,
							labelDetails = {
								detail = (" %s"):format(Path:parent_path():filename()),
								description = "React Component",
							},
						})
					end
				end
			end

			return items
		end
	end

	do -- IsAuthorized
		local Matcher = {"IsAuthorized%(?[{\"']?", "\""}
		local IsMatch = IsInCompleteField(Line, LineOffset, Matcher)
		if IsMatch then
			for FullName, FilePath in next, rojo.SourceMap do
				if FullName:match("PermChck_") then
					local Path = fs.path(FilePath)

					if not tostring(Path:stem()):match("%.") then
						local FileName = tostring(Path:stem())
						local Title = string.match(FileName, "PermChck_(%a+)$")
						
						table.insert(items, {
							kind = 4,
							label = Title,
							labelDetails = {
								detail = (" \"%s:...\""):format(Title),
								description = "Permissions Library",
							},
							insertTextFormat = 2,
							insertText = Title .. ":$0",
						})
					end
				end
			end

			return items
		end
	end

	return items
end
