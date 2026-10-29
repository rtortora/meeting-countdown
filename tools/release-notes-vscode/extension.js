// scripts/release.sh opens the draft with `code --wait`, which returns once its tab closes.
// Apply saves and closes it; Cancel empties it first, which the script takes as a cancel.
const vscode = require('vscode');

async function finish(uri, clear) {
    const document = await vscode.workspace.openTextDocument(uri);
    if (clear) {
        const edit = new vscode.WorkspaceEdit();
        edit.delete(uri, new vscode.Range(0, 0, document.lineCount, 0));
        await vscode.workspace.applyEdit(edit);
    }
    await document.save();
    const tabs = vscode.window.tabGroups.all
        .flatMap((group) => group.tabs)
        .filter((tab) => tab.input instanceof vscode.TabInputText && tab.input.uri.toString() === uri.toString());
    await vscode.window.tabGroups.close(tabs);
}

function activate(context) {
    const target = (uri) => uri ?? vscode.window.activeTextEditor?.document.uri;
    context.subscriptions.push(
        vscode.commands.registerCommand('releaseNotes.apply', (uri) => finish(target(uri), false)),
        vscode.commands.registerCommand('releaseNotes.cancel', (uri) => finish(target(uri), true)),
    );
}

module.exports = { activate };
