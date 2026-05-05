const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const http = require('http');

let mainWindow;
let tray;
let serverUrl = null;

app.whenReady().then(() => {
  ipcMain.handle('server:url', () => serverUrl);
  showConnectWindow();
  createTray();
});

app.on('window-all-closed', () => {});  // 트레이로 유지
app.on('activate', () => { if (!mainWindow) showConnectWindow(); });
app.on('before-quit', () => { app.isQuitting = true; });

function showConnectWindow() {
  mainWindow = new BrowserWindow({
    width: 1400, height: 900,
    minWidth: 800, minHeight: 600,
    resizable: true,
    title: 'U2DIA AI SERVER AGENT',
    backgroundColor: '#0f1117',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    }
  });
  mainWindow.setMenuBarVisibility(false);
  mainWindow.maximize();
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'connect.html'));
  mainWindow.on('close', (e) => {
    if (!app.isQuitting) { e.preventDefault(); mainWindow.hide(); }
  });
  mainWindow.on('closed', () => { mainWindow = null; });

  ipcMain.removeAllListeners('server:connect');
  ipcMain.handle('server:connect', async (_e, url) => {
    try {
      await healthCheck(url);
      serverUrl = url;
      openMainWindow(url);
      return { ok: true };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  });
}

function openMainWindow(baseUrl) {
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.close();
  mainWindow = new BrowserWindow({
    width: 1400, height: 900,
    minWidth: 1024, minHeight: 700,
    title: 'U2DIA AI SERVER AGENT',
    backgroundColor: '#0f1117',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    }
  });
  mainWindow.setMenuBarVisibility(false);
  mainWindow.maximize();
  mainWindow.loadURL(baseUrl);
  mainWindow.on('close', (e) => {
    if (!app.isQuitting) { e.preventDefault(); mainWindow.hide(); }
  });
  mainWindow.on('closed', () => { mainWindow = null; });
  updateTrayMenu();
}

function createTray() {
  const blank = nativeImage.createFromBuffer(Buffer.alloc(16 * 16 * 4, 0), { width: 16, height: 16 });
  try {
    const fs = require('fs');
    const p = app.isPackaged
      ? path.join(process.resourcesPath, 'assets', 'tray-icon.png')
      : path.join(__dirname, '..', 'assets', 'tray-icon.png');
    tray = fs.existsSync(p) ? new Tray(nativeImage.createFromPath(p)) : new Tray(blank);
  } catch (_) { tray = new Tray(blank); }
  tray.setToolTip('U2DIA AI SERVER AGENT');
  tray.on('double-click', () => {
    if (mainWindow) { mainWindow.show(); mainWindow.focus(); }
    else { showConnectWindow(); }
  });
  updateTrayMenu();
}

function updateTrayMenu() {
  if (!tray) return;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'U2DIA AI SERVER AGENT', enabled: false },
    { label: serverUrl ? `연결됨: ${serverUrl}` : '연결 안됨', enabled: false },
    { type: 'separator' },
    { label: '대시보드 열기', click: () => {
        if (mainWindow) { mainWindow.show(); mainWindow.focus(); }
        else if (serverUrl) { openMainWindow(serverUrl); }
        else { showConnectWindow(); }
      }
    },
    { label: '서버 연결 변경', click: () => { serverUrl = null; showConnectWindow(); } },
    { type: 'separator' },
    { label: '종료', click: () => { app.isQuitting = true; app.quit(); } }
  ]));
}

function healthCheck(baseUrl) {
  return new Promise((resolve, reject) => {
    const url = new URL('/api/teams', baseUrl);
    const req = http.get(url.href, (res) => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        try {
          const j = JSON.parse(body);
          j.ok ? resolve() : reject(new Error('서버 응답 오류'));
        } catch { reject(new Error('JSON 파싱 실패')); }
      });
    });
    req.on('error', (e) => reject(new Error('연결 실패: ' + e.message)));
    req.setTimeout(5000, () => { req.destroy(); reject(new Error('시간 초과')); });
  });
}
