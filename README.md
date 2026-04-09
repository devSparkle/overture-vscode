# Overture for VSCode 

Integrates Overture natively with VS Code and Luau LSP or Roblox LSP.

# Installation Instructions

Download the extension from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=devSparkle.overture-vscode). 

> [!NOTE]
> In order to have autocomplete and type-checking, you must install [Luau LSP](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp). While it does support [Roblox LSP](https://marketplace.visualstudio.com/items?itemName=Nightrains.robloxlsp), it is not recommended as it is currently deprecated.
 
## Snippets

- **overture**: Insert a require for Overture.
- **get**: Starts a get function.
- **LoadLibrary**: Loads a (tagged) Library.

## Commands

**To use commands you must right click the object you wish to use the command on, then select one of the following**

- Toggle Overture oLibrary Tag: Enables/Disables the `oLibrary` tag on the selected module.
- Mark Script with Server RunContext: Set the **RunContext** of the selected module to **Server**.
- Mark Script with Client RunContext: Set the **RunContext** of the selected module to **Client**.

## Configuration
- `overture-vscode.rojoUrl`: URL of the Rojo server, change if you have a custom port assigned.
- `overture-vscode.addRunContextMenu`: Toggles the option for the RunContext menu to be visible.