<div align="center">
	<img src="https://raw.githubusercontent.com/devSparkle/overture-vscode/main/assets/icon-dark.png#gh-light-mode-only" alt="Overture" height="150" />
	<img src="https://raw.githubusercontent.com/devSparkle/overture-vscode/main/assets/icon.png#gh-dark-mode-only" alt="Overture" height="150" />
	<br/>
</div>
<br />

# Overture for VSCode 

Integrates [Overture] natively with VS Code and [Luau LSP] or [Roblox LSP].

# Installation Instructions

Download the extension from the [Visual Studio Marketplace][Overture-VSCode].

> [!IMPORTANT]
> In order to have autocomplete and type-checking, you must install [Luau LSP]. While it does support [Roblox LSP], it is not recommended as it is currently deprecated.


# Features
## Snippets
This extension implements several snippets that can help you get your code shipped even faster.

| Prefix      | Expands To                      |
| ----------- | ------------------------------- |
| overture    | `local Overture = require(...)` |
| get         | `Overture:Get(...)`             |
| LoadLibrary | `Overture:LoadLibrary()`        |

*For more information about snippets in VS Code, check [their help page](https://code.visualstudio.com/docs/editing/userdefinedsnippets).*

## Commands

> [!TIP]
> To use commands, right click the file you want to affect in the VS Code Explorer.

The extension implements the following commands:

| Command                            | Action                                                    |
| ---------------------------------- | --------------------------------------------------------- |
| Toggle Overture oLibrary Tag.      | Adds/Removes the `oLibrary` CollectionService tag from the selected module. |
| Mark Script with Server RunContext | Set the `RunContext` of the selected module to `Server`.  |
| Mark Script with Client RunContext | Set the `RunContext` of the selected module to `Client`.  |

## Configuration

- `overture-vscode.rojoUrl`: URL of the Rojo server, change if you have a custom port assigned.
- `overture-vscode.addRunContextMenu`: Toggles the option for the RunContext menu to be visible.


[Overture]: https://github.com/devSparkle/Overture
[Overture-VSCode]: https://marketplace.visualstudio.com/items?itemName=devSparkle.overture-vscode
[Luau LSP]: https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp
[Roblox LSP]: https://marketplace.visualstudio.com/items?itemName=Nightrains.robloxlsp