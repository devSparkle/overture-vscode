const vscode = require('vscode');
const config = vscode.workspace.getConfiguration();
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const dedent = require('dedent');
const cp = require("child_process");

const BASE_META_FILE = {
	"properties": {},
}

const ANNOTATION_ICONS = {
	'class': '$(outline-view-icon)',
	'since': '$(timeline-open)',
	'author': '$(person)',
	'default': '$(symbol-parameter)'
};

const isRojoEnabled = async () => {
	const rojoUrl = config.get("overture-vscode.rojoUrl");
	if (!rojoUrl) {
		return false;
	}
	return (await getRojoRoot(rojoUrl)) !== undefined;
}

const walkSourceMap = (tree) => {
	const instances = [{
		...tree
	}];
	delete instances[0].children;

	if (tree.children) {
		for (const child of tree.children) {
			instances.push(
				...walkSourceMap(child)
			);
		}
	}

	return instances;
}

async function findProjectFiles() {
	const folders = vscode.workspace.workspaceFolders
  
	if (!folders) {
	  return Promise.reject(
		"You must open VS Code on a workspace folder to do this."
	  )
	}
  
	const projectFiles = []
  
	for (const workspaceFolder of folders) {
	  const fileNames = (
		await vscode.workspace.fs.readDirectory(workspaceFolder.uri)
	  )
		.filter(([, fileType]) => fileType === vscode.FileType.File)
		.map(([fileName]) => fileName)
		.filter((fileName) => fileName.endsWith(".project.json"))
  
	  for (const fileName of fileNames) {
		projectFiles.push({
		  name: fileName,
		  workspaceFolderName: workspaceFolder.name,
		  path: vscode.Uri.joinPath(workspaceFolder.uri, fileName),
		})
	  }
	}
  
	return projectFiles
  }

const getActiveProjectFile = async () => {
	const rojoUrl = config.get("overture-vscode.rojoUrl");
	if (!rojoUrl) {
		vscode.window.showErrorMessage("Missing Rojo URL in settings");
		return 
	}

	const root = await getRojoRoot(rojoUrl);
	if (!root || !root.projectName) return;
	
	const projectFiles = await findProjectFiles();
	const matchingProject = projectFiles.find((project) => {
		const data = JSON.parse(fs.readFileSync(project.path.fsPath));
		return data?.name === root.projectName;
	});

	if (matchingProject) {
		return matchingProject.path;
	} else {
		return projectFiles.at(0)?.path;
	}
}

const getModulesFromSourceMap = async (context) => {
	let rojoProject = await getActiveProjectFile();
	if (!rojoProject) {
		return console.error("No Rojo Project found in workspace state");
	}

	const rojoRootFolder = vscode.Uri.from({ path: path.dirname(rojoProject.fsPath) });

	const response = await execShell(`rojo sourcemap ${rojoProject.fsPath}`, { cwd: vscode.workspace.rootPath });
	if (!response) return;

	const sourcemap = JSON.parse(response);
	if (!sourcemap) return;

	const flatMap = walkSourceMap(sourcemap);

	return flatMap.filter((instance) => {
		if (instance.className !== "ModuleScript") return false;
		return instance.filePaths?.some((path) => path.endsWith(".meta.json"))
	}).map((instance) => {
		return {
			...instance,
			filePaths: instance.filePaths.map(path => vscode.Uri.joinPath(rojoRootFolder, path))
		}
	});
}

const getMetaFile = (file) => {
	if (!file) return;
	const baseName = path.join(
		path.dirname(file), 
		path.basename(file).split(".").at(0)
	);
	const metaFile = baseName + ".meta.json";

	if (!fs.existsSync(metaFile)) {
		fs.writeFileSync(metaFile, JSON.stringify(BASE_META_FILE));
	}
	return metaFile;
}

const execShell = (cmd, opts) =>
    new Promise((resolve, reject) => {
        cp.exec(cmd, opts, (err, out) => {
            if (err) {
                return reject(err);
            }
            return resolve(out);
        });
    });

const capitalize = (text) => text.charAt(0).toUpperCase() + text.slice(1);

const getDocString = (source) => {
	try {
		const docString = /^-{0,2}\[=?\[\n\s+(?<match>[^\]]*)^-{0,2}\]=?\]$/ms.exec(source);

		if (docString?.groups?.match) {
			console.log("Match DocString: ", docString.groups?.match);
			let formatted = dedent(docString.groups.match);

			const annotations = [...formatted.matchAll(/^\s?@(?<word>\w+) (?<value>[^\n]+)$/gmi)];
			for (const annotation of annotations) {
				const match = annotation[0];
				const { word, value } = annotation.groups;
				const icon = ANNOTATION_ICONS[word] ?? ANNOTATION_ICONS.default;

				formatted = formatted.replace(match, `#### ${icon} ${capitalize(word)} \`${value}\`\n`);
			}

			const tips = [...formatted.matchAll(/^\s?:::\w+ (?<title>\w+)\n(?<content>.+)(?<!:::):::$/msg)];

			for (const tip of tips) {
				const match = tip[0];
				const { title, content } = tip.groups;

				formatted = formatted.replace(match, `### \`${title}\`\n${dedent(content)}\n`);
			}

			return formatted;
		}
	} catch (error) {
		console.error("Error getting docstring: ", error);
	}
}

const getRojoRoot = async (url) => {
	try {
		const response = await axios.get(`${url}/api/rojo`, { timeout: 1000 });
		if (response.data) {
			return response.data
		}
	} catch (error) {
		console.error(error);		
	}
}

const getInstanceState = async (rojoUrl, rootInstanceId) => {
	try {
		const response = await axios.get(`${rojoUrl}/api/read/${rootInstanceId}`, { timeout: 1000 });
		if (response.data && response.data.instances) {
			return response.data.instances;
		}
	} catch (error) {
		console.error(error);
	}
}

const getOvertureLibrary = async (name) => {
	const rojoUrl = config.get("overture-vscode.rojoUrl");
	if (!rojoUrl) {
		return vscode.window.showErrorMessage("Missing Rojo URL in settings");
	}

	const root = await getRojoRoot(rojoUrl);
	if (!root || !root.rootInstanceId) return;

	const sourcemap = await getInstanceState(rojoUrl, root.rootInstanceId);

	if (sourcemap) {
		const libraries = Object.values(sourcemap).filter((instance) => instance.ClassName == "ModuleScript" && instance.Properties.Tags?.Tags && instance.Properties.Tags.Tags.includes("oLibrary"));
		const matchingInstance = libraries.find((library) => library.Name == name);

		if (matchingInstance) {

			let pathString = `${matchingInstance.Name}`;
			let currentInstance = matchingInstance;
			while (currentInstance?.Parent && currentInstance.Parent != root.rootInstanceId) {
				currentInstance = sourcemap[currentInstance.Parent];
				if (currentInstance) pathString = `${currentInstance.Name}.${pathString}`;
			}

			return {
				path: pathString,
				instance: matchingInstance
			};
		}
	}
}

const getIconThemeExtension = () => {
	const iconTheme = config.get('workbench.iconTheme');

	const themeExtensions = vscode.extensions.all.filter((ext) => ext.packageJSON.contributes?.iconThemes !== undefined);
	const matchingExt = themeExtensions.find((ext) => ext.packageJSON.contributes.iconThemes.find((theme) => theme.id === iconTheme));
	
	if (matchingExt) {
		const matchingTheme = matchingExt.packageJSON.contributes.iconThemes.find((theme) => theme.id === iconTheme);
		const themePath = path.join(matchingExt.extensionPath, matchingTheme.path);

		const metadata = JSON.parse(fs.readFileSync(themePath));
		const translatedIconDefinitions = {};
		for (const key in metadata.iconDefinitions) {
			const { iconPath } = metadata.iconDefinitions[key];
			if (iconPath) {
				const newIconPath = path.join(path.dirname(themePath), iconPath);
				translatedIconDefinitions[key] = {
					...metadata.iconDefinitions[key],
					iconPath: newIconPath,
				};
			} else {
				translatedIconDefinitions[key] = metadata.iconDefinitions[key];
			}
		}
		metadata.iconDefinitions = translatedIconDefinitions;
		return metadata;
	}
}

const getHoverContext = async (source) => {
	const { path: location, instance, name } = source;
	const rojoEnabled = await isRojoEnabled();

	let icon = new vscode.MarkdownString('## $(outline-view-icon)', true);
	const theme = getIconThemeExtension();

	const instanceName = instance?.Name ?? name;

	if (theme) {
		const iconName = theme.languageIds.lua ?? theme.file;
		if (iconName && theme.iconDefinitions[iconName]) {
			const definition = theme.iconDefinitions[iconName];
			const base = path.basename(definition.iconPath);
			icon = new vscode.MarkdownString(`## <img height="18" width="18" src="${base}" />`, true);
			icon.baseUri = vscode.Uri.file(path.join(path.dirname(definition.iconPath), path.sep));
		}
	}

	const fallbackMessage = rojoEnabled ? "Cannot find source for this module" : "Turn Rojo on to get file information on oLibrary Modules";

	let title = icon.appendMarkdown(dedent` 
		${instanceName}
		\`${location ?? fallbackMessage}\``)
	
	if (location && rojoEnabled) {
		const openFileCommand = vscode.Uri.parse(`command:overture-vscode.openModuleViaRojo?${
			encodeURIComponent(JSON.stringify([{ name: instanceName }]))
		}`);
		title = title.appendMarkdown(`\n#### [$(link) Open](${openFileCommand})`);
	}
	
	if (instance?.Properties?.Source?.String) {
		const docString = getDocString(instance.Properties.Source.String);
		if (docString) {
			title = title.appendMarkdown(`\n\n-------------\n\n${docString}`);
		}
	}
	
	title.supportHtml = true;
	title.isTrusted = true;
	title.supportThemeIcons = true;

	return title;
}
const markRunContext = (fileHandle, runContext) => {
	const file = fileHandle?.fsPath;
	const metaFile = getMetaFile(file);
	if (!metaFile) return;
	let meta = JSON.parse(fs.readFileSync(metaFile));
	if (!meta?.properties) {
		meta = { ...BASE_META_FILE };
	}
	const currentRunContext = meta?.properties?.RunContext;
	if (currentRunContext === runContext) {
		vscode.window.showWarningMessage(`${path.basename(file)} is already marked with ${runContext} Run Context!`);
		return;
	}
	meta.properties.RunContext = runContext;

	fs.writeFileSync(metaFile, JSON.stringify(meta, null, '\t'));
	// Display a message box to the user
	vscode.window.showInformationMessage(`Marked ${path.basename(file)} with ${runContext} Run Context`);
}

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
	config.update("robloxLsp.runtime.plugin", context.asAbsolutePath("src/roblox-lsp-plugin.lua"), true)
	
	config.update("explorer.fileNesting.enabled", true, true)
	config.update("explorer.fileNesting.expand", false, true)
	config.update("explorer.fileNesting.patterns", {
		"*.lua": "${capture}.meta.*",
		"*.luau": "${capture}.meta.*",
		
		"*.server.lua": "${capture}.meta.*",
		"*.server.luau": "${capture}.meta.*",
		"*.client.lua": "${capture}.meta.*",
		"*.client.luau": "${capture}.meta.*"
	}, true)

	const toggleLibrary = vscode.commands.registerCommand('overture-vscode.toggleLibrary', (fileHandle) => {
		const file = fileHandle?.fsPath;

		const metaFile = getMetaFile(file);
		if (!metaFile) {
			vscode.window.showErrorMessage(`Couldn't get meta file path for ${path.basename(file)}`);
			return;
		};
		let meta = JSON.parse(fs.readFileSync(metaFile));
		if (!meta?.properties) {
			meta = { ...BASE_META_FILE };
		}
		const hasTag = meta?.properties?.Tags?.includes("oLibrary") ?? false;
		if (hasTag) {
			meta.properties.Tags = (meta.properties.Tags ?? {}).filter((tag) => tag !== "oLibrary");
		} else {
			meta.properties.Tags = [...(meta.properties.Tags ?? []), "oLibrary"];
		}
		fs.writeFileSync(metaFile, JSON.stringify(meta, null, '\t'));
		// Display a message box to the user
		vscode.window.showInformationMessage(`${hasTag ? "Removed" : "Added"} oLibrary tag to ${path.basename(file)}`);
	});

	context.subscriptions.push(toggleLibrary);

	const setServer = vscode.commands.registerCommand('overture-vscode.setServerContext', (file) => markRunContext(file, "Server"));
	const setClient = vscode.commands.registerCommand('overture-vscode.setClientContext', file => markRunContext(file, "Client"));
	const openModule = vscode.commands.registerCommand('overture-vscode.openModuleViaRojo', async ({ name }) => {
		const rojoUrl = config.get("overture-vscode.rojoUrl");
		if (!rojoUrl) {
			return vscode.window.showErrorMessage("Missing Rojo URL in settings");
		}
		console.log("Opening module: ", name);

		try {
			const sourcemap = await getModulesFromSourceMap(context);
			if (!sourcemap) return console.error("No sourcemap found");

			const module = sourcemap.find((instance) => instance.name === name);

			const filePath = module?.filePaths?.find((path) => !path.fsPath.endsWith(".meta.json"));
			if (!module || !filePath) return vscode.window.showErrorMessage("Could not find module to open!");

			vscode.workspace.openTextDocument(filePath).then((doc) => {
				vscode.window.showTextDocument(doc);
			})
		} catch (error) {
			console.error(error);
			return vscode.window.showErrorMessage(`Something went wrong when trying to open "${name}"`);
		}
	});

	context.subscriptions.concat([setServer, setClient, openModule]);

	const onHover = vscode.languages.registerHoverProvider('lua', {
		async provideHover(document, position, token) {
		  const line = document.lineAt(position);
		  const range = document.getWordRangeAtPosition(position);
		  const keyword = document.getText(range);

		  const matchRange = range?.with(line.range.start, range.start);
		  if (!matchRange || !keyword) {
			return;
		  };

		  const text = document.getText(matchRange);
		  
		  if (text.match(/Overture:LoadLibrary\(["']?$/)) {
			const matching = await getOvertureLibrary(keyword);
			if (matching?.path && matching?.instance) {
				return new vscode.Hover(
					await getHoverContext(matching), 
					range
				);
			} else {
				return new vscode.Hover(
					await getHoverContext({ name: keyword }), 
					range
				);
			}
		  }
		}
	});

	context.subscriptions.push(onHover);
}

function deactivate() {
	config.update("robloxLsp.runtime.plugin", undefined, true)
	
	config.update("explorer.fileNesting.enabled", undefined, true)
	config.update("explorer.fileNesting.expand", undefined, true)
	config.update("explorer.fileNesting.patterns", undefined, true)
}

module.exports = {
	activate,
	deactivate
}
