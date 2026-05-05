const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // Server
  serverStart: () => ipcRenderer.invoke('server:start'),
  serverStop: () => ipcRenderer.invoke('server:stop'),
  serverRestart: () => ipcRenderer.invoke('server:restart'),
  serverStatus: () => ipcRenderer.invoke('server:status'),
  onServerStateChanged: (cb) => ipcRenderer.on('server:state-changed', (_e, state, msg) => cb(state, msg)),
  onServerLog: (cb) => ipcRenderer.on('server:log', (_e, text) => cb(text)),

  // Settings
  getSettings: () => ipcRenderer.invoke('settings:get'),
  setSettings: (s) => ipcRenderer.invoke('settings:set', s),

  // Tokens
  getTokens: () => ipcRenderer.invoke('tokens:list'),
  createToken: (data) => ipcRenderer.invoke('tokens:create', data),
  deleteToken: (id) => ipcRenderer.invoke('tokens:delete', id),

  // Metrics
  getMetrics: () => ipcRenderer.invoke('metrics:get'),
  getClients: () => ipcRenderer.invoke('clients:get'),

  // Window controls
  windowMinimize: () => ipcRenderer.invoke('window:minimize'),
  windowMaximize: () => ipcRenderer.invoke('window:maximize'),
  windowFullscreen: () => ipcRenderer.invoke('window:fullscreen'),
  windowIsMaximized: () => ipcRenderer.invoke('window:is-maximized'),
  windowIsFullscreen: () => ipcRenderer.invoke('window:is-fullscreen'),
  onWindowStateChanged: (cb) => ipcRenderer.on('window:state-changed', (_e, state) => cb(state)),
});
