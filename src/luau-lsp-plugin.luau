local function IsLibrary(Uri: Uri): boolean
	local ReadSuccess, Content = pcall(lsp.fs.readFile, Uri)
	if not ReadSuccess then return false end
	
	local DecodeSuccess, SiftedContent = pcall(lsp.json.deserialize, Content)
	if not DecodeSuccess then return false end
	if typeof(SiftedContent) ~= "table" then return false end
	if typeof(SiftedContent.properties) ~= "table" then return false end
	if typeof(SiftedContent.properties.Tags) ~= "table" then return false end
	if table.find(SiftedContent.properties.Tags, "oLibrary") == nil then return false end
	
	return true
end

local function GetLibraries(RelativeTo: string, _Libraries, _Uri: Uri?)
	local Libraries = (_Libraries or {})
	local Uri = (_Uri or lsp.workspace.getRootUri())
	
	for _, Entry in lsp.fs.listDirectory(Uri) do
		local Name = string.sub(Entry:toString(), #Uri:toString() + 2)
		local Library = string.match(Name, "(.*)%.meta%.json$")
		
		if Library and IsLibrary(Entry) then
			local FixedPath = Entry.path
			
			for _, Directory in ipairs(string.split(RelativeTo, "/")) do
				if string.find(FixedPath, `{Directory}/`, 1, true) == 1 then
					FixedPath = string.sub(FixedPath, #Directory + 2)
				else
					FixedPath = `../{FixedPath}`
				end
			end
			
			FixedPath = `./{FixedPath}`
			FixedPath = string.gsub(FixedPath, "%./%.%.", "..")
			
			Libraries[Library] = (string.sub(FixedPath, 1, -#Name - 1) .. Library)
		else
			pcall(GetLibraries, RelativeTo, Libraries, Entry)
		end
	end
	
	return Libraries
end

return {
	transformSource = function(Source, Context)
		local Changes = {}
		local Line, LineStart = 1, 1
		
		local Libraries = GetLibraries((string.gsub(Context.filePath, "/[^/]-$", "")))
		
		for Index = 1, #Source do
			if string.sub(Source, Index, Index) == "\n" then
				Line += 1
				LineStart = (Index + 1)
			end
			
			local Match = string.match(Source, "^Overture:LoadLibrary%b()", Index)
			
			if Match then
				local Success: boolean
				local LoadData = Match
				
				LoadData = string.match(LoadData, "%b()")
				LoadData = string.sub(LoadData, 2, -2)
				LoadData = string.gsub(LoadData, "{", "[")
				LoadData = string.gsub(LoadData, "}", "]")
				LoadData = `[{LoadData}]`
				Success, LoadData = pcall(lsp.json.deserialize, LoadData)
				
				if not Success then
					lsp.client.sendLogMessage("warning", `Failed to process match: "{Match}" in {Context.filePath}.`)
					
					continue
				end
				
				local Column = (Index - LineStart + 1)
				local Library, NamedImports = unpack(LoadData)
				
				lsp.client.sendLogMessage("log", `Setup require path {Libraries[Library]} in {Context.filePath}:{Line}:{Column} for {Library}`)
				
				if not Libraries[Library] then
					lsp.client.sendLogMessage("warning", `No path for "{Library}" in {Context.filePath}.`)
					
					continue
				end
				
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