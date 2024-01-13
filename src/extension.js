const vscode = require('vscode');
const config = vscode.workspace.getConfiguration();
const fs = require('fs');
const path = require('path');

const BASE_META_FILE = {
	"properties": {},
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

const markRunContext = (file, runContext) => {
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

	const toggleLibrary = vscode.commands.registerCommand('extension.toggleLibrary', () => {
		// The code you place here will be executed every time your command is executed
		const file = vscode.window.activeTextEditor?.document.uri.fsPath;
		const metaFile = getMetaFile(file);
		if (!metaFile) return;
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

	const setServer = vscode.commands.registerCommand('extension.setServerContext', () => markRunContext(vscode.window.activeTextEditor?.document.uri.fsPath, "Server"));
	const setClient = vscode.commands.registerCommand('extension.setClientContext', () => markRunContext(vscode.window.activeTextEditor?.document.uri.fsPath, "Client"));

	context.subscriptions.concat([setServer, setClient]);
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
