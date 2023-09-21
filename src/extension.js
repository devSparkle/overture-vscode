const vscode = require('vscode');
const config = vscode.workspace.getConfiguration()

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
