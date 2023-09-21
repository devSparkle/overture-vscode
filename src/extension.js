const vscode = require('vscode');

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
	console.log('Congratulations, your extension "overture-vscode" is now active!');
	
	let disposable = vscode.commands.registerCommand('overture-vscode.helloWorld', function () {
		vscode.window.showInformationMessage('Hello World from Overture for VSCode!');
	});
	
	context.subscriptions.push(disposable);
}

function deactivate() {}

module.exports = {
	activate,
	deactivate
}
