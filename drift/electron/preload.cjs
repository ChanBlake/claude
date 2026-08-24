/* Exposes exactly one thing to the page: a storage shim matching the browser
 * API the game already uses, so src/save.js needs no branch for native. */
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("storage", {
  async get(key) {
    const all = await ipcRenderer.invoke("save:read");
    return all && all[key] !== undefined ? { key, value: all[key] } : null;
  },
  async set(key, value) {
    const all = (await ipcRenderer.invoke("save:read")) || {};
    all[key] = value;
    await ipcRenderer.invoke("save:write", all);
    return { key, value };
  },
});
