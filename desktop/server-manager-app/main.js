const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, screen, shell } = require('electron');
const path = require('path');
const http = require('http');
const os = require('os');
const fs = require('fs');

const sharedDir = app.isPackaged ? path.join(__dirname, 'shared') : path.join(__dirname, '..', 'shared');
const SettingsStore = require(path.join(sharedDir, 'settings-store'));
const ServerManager = require(path.join(sharedDir, 'server-manager'));
const NotificationManager = require(path.join(sharedDir, 'notification-manager'));

let settingsStore, serverManager, notificationManager;
let mainWindow, tray;

const isLinux = process.platform === 'linux';
const isWindows = process.platform === 'win32';

const launchedHidden = process.argv.includes('--hidden') ||
  (!isLinux && app.getLoginItemSettings().wasOpenedAtLogin);

app.whenReady().then(async () => {
  settingsStore = new SettingsStore(app.getPath('userData'));
  const serverPy = app.isPackaged
    ? path.join(process.resourcesPath, 'server.py')
    : path.resolve(__dirname, '../../server.py');
  const dbDir = app.isPackaged ? app.getPath('userData') : null;
  serverManager = new ServerManager(settingsStore, serverPy, dbDir);
  notificationManager = new NotificationManager(settingsStore);

  applyAutoStart(settingsStore.get('startWithWindows') || settingsStore.get('startWithSystem'));
  registerIpcHandlers();

  serverManager.on('state-changed', (state, msg) => {
    broadcast('server:state-changed', state, msg);
    if (state === 'running') notificationManager.connect();
    else if (state === 'stopped' || state === 'error') notificationManager.disconnect();
  });
  serverManager.on('log', (t) => broadcast('server:log', t));
  notificationManager.on('notification-clicked', () => {
    if (mainWindow) { mainWindow.show(); mainWindow.focus(); }
    else { const p = serverManager.port || 5555; const ts = getTailscaleIp(); shell.openExternal('http://' + (ts || 'localhost') + ':' + p); }
  });

  if (launchedHidden) {
    try { await serverManager.start(); } catch (_) {}
  } else {
    createMainWindow();
    try { await serverManager.start(); } catch (err) {
      const { dialog } = require('electron');
      dialog.showErrorBox('서버 시작 실패', err.message || '알 수 없는 오류');
    }
  }
  createTray();
});

app.on('before-quit', async () => {
  notificationManager.disconnect();
  await serverManager.stop();
});
app.on('window-all-closed', () => {});
app.on('activate', () => { if (!mainWindow) createMainWindow(); });

function createMainWindow() {
  if (mainWindow && !mainWindow.isDestroyed()) { mainWindow.show(); mainWindow.focus(); return; }
  const saved = settingsStore.get('windowBounds');
  let bounds = { width: 1280, height: 860 };
  if (saved && saved.width >= 900 && saved.height >= 650) {
    const displays = screen.getAllDisplays();
    const visible = displays.some(d => {
      const { x, y, width, height } = d.workArea;
      return saved.x >= x - 100 && saved.x < x + width && saved.y >= y - 100 && saved.y < y + height;
    });
    if (visible) bounds = saved;
    else bounds = { width: saved.width, height: saved.height };
  }
  mainWindow = new BrowserWindow({
    ...bounds,
    minWidth: 900, minHeight: 650,
    frame: false,
    titleBarStyle: 'hidden',
    title: 'U2DIA Server Manager',
    backgroundColor: '#0f1117',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    }
  });
  mainWindow.setMenuBarVisibility(false);
  mainWindow.maximize();
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  mainWindow.on('maximize', () => broadcast('window:state-changed', 'maximized'));
  mainWindow.on('unmaximize', () => broadcast('window:state-changed', 'normal'));
  mainWindow.on('enter-full-screen', () => broadcast('window:state-changed', 'fullscreen'));
  mainWindow.on('leave-full-screen', () => broadcast('window:state-changed', 'normal'));
  mainWindow.on('close', (e) => {
    if (settingsStore.get('minimizeToTray') && !app.isQuitting) {
      e.preventDefault(); mainWindow.hide(); return;
    }
    settingsStore.set('windowBounds', mainWindow.getBounds());
  });
  mainWindow.on('closed', () => { mainWindow = null; });
}

function createTray() {
  const emptyIcon = nativeImage.createFromBuffer(Buffer.alloc(16 * 16 * 4, 0), { width: 16, height: 16 });
  try {
    const iconPath = app.isPackaged
      ? path.join(process.resourcesPath, 'assets', 'tray-icon.png')
      : path.join(__dirname, '..', 'assets', 'tray-icon.png');
    tray = fs.existsSync(iconPath)
      ? new Tray(nativeImage.createFromPath(iconPath))
      : new Tray(emptyIcon);
  } catch (_) { tray = new Tray(emptyIcon); }
  tray.setToolTip('U2DIA Kanban Board');
  // Linux: single click opens, double-click also opens
  tray.on('click', () => {
    if (isLinux) { if (mainWindow) { mainWindow.isVisible() ? mainWindow.hide() : mainWindow.show(); } else createMainWindow(); }
    else { if (mainWindow) { mainWindow.isVisible() ? mainWindow.hide() : mainWindow.show(); } else createMainWindow(); }
  });
  tray.on('double-click', () => createMainWindow());
  updateTrayMenu();
  serverManager.on('state-changed', updateTrayMenu);
}

function getTailscaleIp() {
  try {
    const ifaces = os.networkInterfaces();
    for (const [name, addrs] of Object.entries(ifaces)) {
      if (name.startsWith('tailscale') || name === 'tailscale0') {
        for (const a of addrs) {
          if (a.family === 'IPv4' && !a.internal) return a.address;
        }
      }
    }
    // fallback: 100.64.0.0/10 대역 탐색
    for (const addrs of Object.values(ifaces)) {
      for (const a of addrs) {
        if (a.family === 'IPv4' && !a.internal) {
          const first = parseInt(a.address.split('.')[0]);
          const second = parseInt(a.address.split('.')[1]);
          if (first === 100 && second >= 64 && second <= 127) return a.address;
        }
      }
    }
  } catch (_) {}
  return null;
}

function openBoardInBrowser() {
  const port = serverManager.port || settingsStore.get('port') || 5555;
  const tsIp = getTailscaleIp();
  const host = tsIp || 'localhost';
  shell.openExternal('http://' + host + ':' + port);
}

function updateTrayMenu() {
  if (!tray) return;
  const isRunning = serverManager.state === 'running';
  const port = serverManager.port || settingsStore.get('port') || 5555;
  const stateLabels = {
    stopped: '정지됨', starting: '시작 중...', running: `실행 중 (${getTailscaleIp() || 'localhost'}:${port})`, error: '오류'
  };
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: `U2DIA Kanban Board`, enabled: false, icon: null },
    { label: `서버: ${stateLabels[serverManager.state] || '알 수 없음'}`, enabled: false },
    { type: 'separator' },
    { label: '🌐 브라우저로 열기', click: () => openBoardInBrowser() },
    { label: '⚙ 매니저 열기', click: () => createMainWindow() },
    { type: 'separator' },
    { label: '▶ 서버 시작', enabled: !isRunning && serverManager.state !== 'starting', click: () => serverManager.start() },
    { label: '↺ 서버 재시작', enabled: isRunning, click: () => serverManager.restart() },
    { label: '■ 서버 정지', enabled: isRunning, click: () => serverManager.stop() },
    { type: 'separator' },
    { label: '✕ 종료', click: () => { app.isQuitting = true; app.quit(); } }
  ]));
}

// ── 자동시작 (Linux: ~/.config/autostart, Windows: 레지스트리) ──
function applyAutoStart(enabled) {
  if (isWindows) {
    try { app.setLoginItemSettings({ openAtLogin: !!enabled, openAsHidden: true, args: ['--hidden'] }); }
    catch (_) {}
  } else if (isLinux) {
    applyLinuxAutoStart(enabled);
  }
}

function applyLinuxAutoStart(enabled) {
  try {
    const autostartDir = path.join(os.homedir(), '.config', 'autostart');
    if (!fs.existsSync(autostartDir)) fs.mkdirSync(autostartDir, { recursive: true });
    const desktopFile = path.join(autostartDir, 'u2dia-server-manager.desktop');
    const exePath = app.isPackaged ? app.getPath('exe') : process.execPath;
    const appPath = app.isPackaged ? '' : ` ${path.resolve(__dirname, '.')}`;
    const content = [
      '[Desktop Entry]',
      'Type=Application',
      'Name=U2DIA Server Manager',
      `Exec=${exePath}${appPath} --hidden`,
      `Icon=${path.join(__dirname, '..', 'assets', 'icon.png')}`,
      'Terminal=false',
      'Hidden=false',
      'NoDisplay=false',
      `X-GNOME-Autostart-enabled=${enabled ? 'true' : 'false'}`,
      'Comment=U2DIA AI Kanban Board Server Manager',
    ].join('\n');
    fs.writeFileSync(desktopFile, content);
  } catch (e) { console.error('[autostart]', e.message); }
}

function registerIpcHandlers() {
  ipcMain.handle('server:start', async () => { await serverManager.start(); return { state: serverManager.state }; });
  ipcMain.handle('server:stop', async () => { await serverManager.stop(); return { state: serverManager.state }; });
  ipcMain.handle('server:restart', async () => { await serverManager.restart(); return { state: serverManager.state }; });
  ipcMain.handle('server:status', () => ({ state: serverManager.state, port: serverManager.port, host: serverManager.host }));

  ipcMain.handle('settings:get', () => settingsStore.getAll());
  ipcMain.handle('settings:set', async (_e, s) => {
    const oldPort = settingsStore.get('port');
    const oldHost = settingsStore.get('host');
    settingsStore.setMultiple(s);
    const autoStartKey = isWindows ? 'startWithWindows' : 'startWithSystem';
    if (autoStartKey in s) applyAutoStart(s[autoStartKey]);
    if ('startWithWindows' in s) applyAutoStart(s.startWithWindows);
    if ('notifications' in s) notificationManager.enabled = s.notifications;
    if (serverManager.state === 'running' && (s.port !== oldPort || s.host !== oldHost)) {
      await serverManager.restart();
    }
    return { ok: true };
  });

  ipcMain.handle('window:minimize', () => { if (mainWindow) mainWindow.minimize(); });
  ipcMain.handle('window:maximize', () => {
    if (!mainWindow) return;
    mainWindow.isMaximized() ? mainWindow.unmaximize() : mainWindow.maximize();
  });
  ipcMain.handle('window:fullscreen', () => {
    if (!mainWindow) return;
    mainWindow.setFullScreen(!mainWindow.isFullScreen());
  });
  ipcMain.handle('window:is-maximized', () => mainWindow ? mainWindow.isMaximized() : false);
  ipcMain.handle('window:is-fullscreen', () => mainWindow ? mainWindow.isFullScreen() : false);

  ipcMain.handle('tokens:list', () => apiCall('/api/tokens'));
  ipcMain.handle('tokens:create', (_e, data) => apiCall('/api/tokens', 'POST', data));
  ipcMain.handle('tokens:delete', (_e, id) => apiCall(`/api/tokens/${id}`, 'DELETE'));

  ipcMain.handle('metrics:get', () => apiCall('/api/system/metrics'));
  ipcMain.handle('clients:get', () => apiCall('/api/system/clients'));

  // Linux autostart 상태 조회
  ipcMain.handle('autostart:get', () => {
    if (isWindows) return { enabled: app.getLoginItemSettings().openAtLogin };
    const desktopFile = path.join(os.homedir(), '.config', 'autostart', 'u2dia-server-manager.desktop');
    if (!fs.existsSync(desktopFile)) return { enabled: false };
    const content = fs.readFileSync(desktopFile, 'utf-8');
    return { enabled: content.includes('X-GNOME-Autostart-enabled=true') };
  });
  ipcMain.handle('autostart:set', (_e, enabled) => {
    applyAutoStart(enabled);
    return { ok: true };
  });
  ipcMain.handle('open-browser', () => { openBoardInBrowser(); });
}

function apiCall(apiPath, method = 'GET', body = null) {
  return new Promise((resolve) => {
    const port = serverManager.port || settingsStore.get('port') || 5555;
    const opts = { hostname: '127.0.0.1', port, path: apiPath, method, headers: { 'Content-Type': 'application/json' } };
    const req = http.request(opts, (res) => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch { resolve({ ok: false, error: 'parse' }); } });
    });
    req.on('error', (e) => resolve({ ok: false, error: e.message }));
    req.setTimeout(5000, () => { req.destroy(); resolve({ ok: false, error: 'timeout' }); });
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function broadcast(channel, ...args) {
  for (const win of BrowserWindow.getAllWindows()) {
    if (!win.isDestroyed()) win.webContents.send(channel, ...args);
  }
}
