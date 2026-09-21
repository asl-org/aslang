// Starts `asl lsp` over stdio and connects it to VSCode. Plain JS so
// the extension runs without a build step; `npm install` once in this
// folder pulls in vscode-languageclient.

const fs = require("fs");
const path = require("path");
const vscode = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");

let client;

function workspaceRoot() {
  const folders = vscode.workspace.workspaceFolders;
  return folders && folders.length > 0 ? folders[0].uri.fsPath : undefined;
}

// `asl.compilerPath` if set; else `asl` in the workspace root (the
// compiler repo itself); else `asl` on PATH.
function compilerPath(config, root) {
  const configured = config.get("compilerPath");
  const local = root ? path.join(root, "asl") : undefined;
  if (configured) return configured;
  return local && fs.existsSync(local) ? local : "asl";
}

function createClient() {
  const config = vscode.workspace.getConfiguration("asl");
  const root = workspaceRoot();
  const args = [
    "lsp",
    `--indent-width=${config.get("indentWidth")}`,
    ...config.get("vendors").map((vendor) => `--vendor=${vendor}`),
  ];
  const serverOptions = {
    command: compilerPath(config, root),
    args,
    options: { cwd: root },
  };
  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "asl" }],
  };
  return new LanguageClient("asl", "ASLang", serverOptions, clientOptions);
}

async function restart() {
  if (client) await client.stop();
  client = createClient();
  await client.start();
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("asl.restartServer", restart),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("asl")) restart();
    })
  );
  return restart();
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };
