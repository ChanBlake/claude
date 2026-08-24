/* DRIFT — native shell.
 * Steam ships an executable, not a URL, so the browser build is wrapped here.
 * The renderer stays fully sandboxed: no node integration, no remote content.
 * Progress is written to Electron's userData directory via preload, which is
 * also where Steam Cloud should be pointed. */
const { app, BrowserWindow, ipcMain, screen } = require("electron");
const path = require("node:path");
const fs = require("node:fs");

const SAVE = () => path.join(app.getPath("userData"), "save.json");
let win = null;

function createWindow() {
  const { width } = screen.getPrimaryDisplay().workAreaSize;
  const w = Math.min(1280, Math.max(960, Math.floor(width * 0.7)));
  win = new BrowserWindow({
    width: w,
    height: Math.round((w * 3) / 5) + 96,
    minWidth: 800,
    minHeight: 540,
    backgroundColor: "#070912",
    autoHideMenuBar: true,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  win.once("ready-to-show", () => win.show());
  win.loadFile(path.join(__dirname, "..", "index.html"));

  // never let the game navigate away from itself
  win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  win.webContents.on("will-navigate", (e) => e.preventDefault());
}

ipcMain.handle("save:read", async () => {
  try { return JSON.parse(fs.readFileSync(SAVE(), "utf8")); }
  catch { return null; }
});
ipcMain.handle("save:write", async (_e, data) => {
  try {
    fs.mkdirSync(path.dirname(SAVE()), { recursive: true });
    fs.writeFileSync(SAVE(), JSON.stringify(data));   // small file; atomicity is not a concern
    return true;
  } catch { return false; }
});

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => { if (!BrowserWindow.getAllWindows().length) createWindow(); });
});
app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
