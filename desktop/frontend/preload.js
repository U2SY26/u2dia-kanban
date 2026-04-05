const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  getServerUrl: () => ipcRenderer.invoke('server:url'),
  serverConnect: (url) => ipcRenderer.invoke('server:connect', url),
});
