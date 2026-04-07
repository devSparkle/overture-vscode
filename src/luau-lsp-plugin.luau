local function GetLibraries(_Libraries, _Uri: Uri?)
	local Libraries = (_Libraries or {})
	local Uri = (_Uri or lsp.workspace.getRootUri())
	
	for _, Entry in lsp.fs.listDirectory(Uri) do
		local Name = string.sub(Entry:toString(), #Uri:toString() + 2)
		local Library = string.match(Name, "(.*)%.meta%.json$")
		
		if Library then
			Libraries[Library] = (string.sub(Entry.path, 1, -#Name - 1) .. Library)
		else
			pcall(GetLibraries, Libraries, Entry)
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
				local LoadData = Match
				
				LoadData = string.match(LoadData, "%b()")
				LoadData = string.sub(LoadData, 2, -2)
				LoadData = string.gsub(LoadData, "{", "[")
				LoadData = string.gsub(LoadData, "}", "]")
				LoadData = `[{LoadData}]`
				LoadData = lsp.json.deserialize(LoadData)
				
				local Column = (Index - LineStart + 1)
				local Library, NamedImports = unpack(LoadData)
				
				if NamedImports then
					local NewText = ""
					
					for Index, NamedImport in ipairs(NamedImports) do
						NewText ..= `require("{Libraries[Library]}").{NamedImport}`
						
						if Index ~= #NamedImports then
							NewText ..= ","
						end
					end
					
					NewText ..= `; {Match}`
					
					table.insert(Changes, {
						startLine = Line,
						startColumn = Column,
						endLine = Line,
						endColumn = (Column + #Match),
						newText = NewText,
					})
				else
					table.insert(Changes, {
						startLine = Line,
						startColumn = Column,
						endLine = Line,
						endColumn = (Column + #Match),
						newText = `require("{Libraries[Library]}"); {Match}`,
					})
				end
			end
		end
		
		return Changes
	end
}:: PluginApi