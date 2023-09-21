const vscode = require('vscode');
const config = vscode.workspace.getConfiguration()

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
	config.update("robloxLsp.runtime.plugin", context.asAbsolutePath("src/roblox-lsp-plugin.lua"), true)
	
}

function deactivate() {
	config.update("robloxLsp.runtime.plugin", undefined, true)
}

module.exports = {
	activate,
	deactivate
}
