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

local function NormalizePath(Path: string)
	return string.gsub(Path, "[/\\]", "/")
end

local function GetParentDirectory(Path: string)
	return string.gsub(Path, "[/\\][^/\\]-$", "")
end

local function GetRelativePath(Path: string, RelativeTo: string)
	Path = NormalizePath(Path)
	RelativeTo = NormalizePath(RelativeTo)
	
	if string.find(Path, "^/?%a:") then
		Path = string.sub(Path, 2)
	end
	
	for _, Directory in ipairs(string.split(RelativeTo, "/")) do
		if string.find(Path, `{Directory}/`, 1, true) == 1 then
			Path = string.sub(Path, #Directory + 2)
		else
			Path = `../{Path}`
		end
	end
	
	Path = `./{Path}`
	Path = string.gsub(Path, "^%./%.%.", "..")
	
	return Path
end

type Sourcemap = {name: string, className: string, filePaths: {string}?, children: {Sourcemap}?}

local function GetSourcemap(): Sourcemap?
	local RootUri = lsp.workspace.getRootUri()
	local SourcemapUri = RootUri:joinPath("sourcemap.json")
	lsp.client.sendLogMessage("log", `Sourcemap at: {SourcemapUri:toString()}`)
	
	local ReadSuccess, Content = pcall(lsp.fs.readFile, SourcemapUri)
	if not ReadSuccess then lsp.client.sendLogMessage("log", `Sourcemap could not be read: {Content}`); return nil end
	
	local DecodeSuccess, Sourcemap = pcall(lsp.json.deserialize, Content)
	if not DecodeSuccess then lsp.client.sendLogMessage("warning", `Sourcemap could not be decoded: {Sourcemap}`); return nil end
	
	return Sourcemap
end

local function _GetLibrariesFromSourcemap(_Libraries, _Sourcemap: Sourcemap?, RobloxPath: string?)
	local Libraries = (_Libraries or {})
	local Sourcemap = (_Sourcemap or GetSourcemap())
	
	if not Sourcemap then
		return
	end
	
	if Sourcemap.className == "ModuleScript" and Sourcemap.filePaths then
		local MetaFile, SourceFile
		
		for _, FilePath in Sourcemap.filePaths do
			if string.find(FilePath, ".*%.meta%.json$") then
				MetaFile = FilePath
			else
				SourceFile = FilePath
			end
		end
		
		if MetaFile and SourceFile and IsLibrary(lsp.workspace.getRootUri():joinPath(MetaFile)) then
			Libraries[Sourcemap.name] = `{RobloxPath}/{Sourcemap.name}`
		end
	end
	
	if Sourcemap.children then
		for _, Child in Sourcemap.children do
			_GetLibrariesFromSourcemap(Libraries, Child, (RobloxPath and `{RobloxPath}/{Sourcemap.name}` or "@game"))
		end
	end
	
	return Libraries
end

local function _GetLibrariesFromRoot(_Libraries, _Uri: Uri?)
	local Libraries = (_Libraries or {})
	local Uri = (_Uri or lsp.workspace.getRootUri())
	
	for _, Entry in lsp.fs.listDirectory(Uri) do
		local Name = string.sub(Entry:toString(), #Uri:toString() + 2)
		local Library = string.match(Name, "(.*)%.meta%.json$")
		
		if Library and IsLibrary(Entry) then
			Libraries[Library] = (string.sub(Entry.path, 1, -#Name - 1) .. Library)
		else
			pcall(_GetLibrariesFromRoot, Libraries, Entry)
		end
	end
	
	return Libraries
end

local LibraryCache
local LibraryCacheExpiration = 0
local function GetLibraries()
	if LibraryCache and LibraryCacheExpiration > os.clock() then
		return LibraryCache
	end
	
	local Libraries = (_GetLibrariesFromSourcemap() or _GetLibrariesFromRoot())
	
	LibraryCache = Libraries
	LibraryCacheExpiration = (os.clock() + 5)
	
	lsp.client.sendLogMessage("log", `Library log start`)
	for i, v in Libraries do lsp.client.sendLogMessage("log", `\tLibrary log: {i} = {v}`) end
	lsp.client.sendLogMessage("log", `Library log end`)
	
	return Libraries
end

return {
	transformSource = function(Source, Context)
		local Changes = {}
		local Line, LineStart = 1, 1
		
		local Libraries = {}
		local Parent = GetParentDirectory(Context.filePath)
		
		local OvertureCalls = 0
		local MuteOverture = false
		
		for Index, Library in GetLibraries() do
			if string.find(Library, "^@game") then
				Libraries[Index] = Library
			else
				Libraries[Index] = GetRelativePath(Library, Parent)
			end
		end
		
		for Index = 1, #Source do
			if string.sub(Source, Index, Index) == "\n" then
				Line += 1
				LineStart = (Index + 1)
			end
			
			if string.find(Source, "^Overture[:.]", Index) then
				OvertureCalls += 1
				MuteOverture = true
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
						newText = `require("{Libraries[Library]}")`,
					})
				end
				
				OvertureCalls -= 1
			end
		end
		
		lsp.client.sendLogMessage("log", `{OvertureCalls} Overture calls remaining in {Context.filePath}`)
		
		if MuteOverture and OvertureCalls == 0 then
			Line, LineStart = 1, 1
			
			for Index = 1, #Source do
				if string.sub(Source, Index, Index) == "\n" then
					Line += 1
					LineStart = (Index + 1)
				end
				
				local Column = (Index - LineStart + 1)
				
				if string.find(Source, "^Overture ?=", Index) then
					table.insert(Changes, {
						startLine = Line,
						startColumn = Column,
						endLine = Line,
						endColumn = Column,
						newText = "_",
					})
					
					break
				end
			end
		end
		
		return Changes
	end
}:: PluginApi