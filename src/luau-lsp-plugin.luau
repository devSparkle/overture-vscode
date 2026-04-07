-- local Test = Overture:LoadLibrary("Test")

local function PackVararg(...)
	local LoosePack = table.pack(...)
	local Args = {}
	
	for Index = 1, LoosePack.n do
		local Value = LoosePack[Index]
		
		if Value ~= nil then
			table.insert(Args, Value)
		end
	end
	
	return Args
end

local function Merge(...)
	local NewTable = {}
	
	for _, Table in ipairs(PackVararg(...)) do
		for Index, Value in Table do
			NewTable[Index] = Value
		end
	end
	
	return NewTable
end

local function GetLibraries(_Uri)
	local Libraries = {}
	local Uri = (_Uri or lsp.workspace.getRootUri())
	
	for _, Entry in lsp.fs.listDirectory(Uri) do
		local Library = string.match(Entry:toString(), "(.*).meta.json$")
		
		if Library then
			Libraries[Library] = Library
			continue
		end
		
		local Success, SubLibraries = pcall(GetLibraries, Entry)
		Libraries = Merge(Libraries, {Success = true})
		if Success then
			Libraries = Merge(Libraries, SubLibraries, {Success = true})
		end
	end
	
	return Libraries
end

return {
	transformSource = function(Source, Context)
		local Changes = {}
		local Line, LineStart = 1, 1
		
		local Libraries = GetLibraries()
		
		for Index = 1, #Source do
			if string.sub(Source, Index, Index) == "\n" then
				Line += 1
				LineStart = (Index + 1)
			end
			
			local Match = string.match(Source, "^Overture:LoadLibrary%b()", Index)
			
			if Match then
				local Library
				
				Library = string.match(Match, "%b()")
				Library = string.sub(Library, 3, -3)
				
				local Column = (Index - LineStart + 1)
				
				for Lib in Libraries do
					table.insert(Changes, {
						startLine = Line,
						startColumn = Column,
						endLine = Line,
						endColumn = (Column + #Match),
						newText = `require("{Lib}")`,
					})
				end
			end
		end
		
		return Changes
	end
}:: PluginApi