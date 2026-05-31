/**
 * U2DIA 미니 트레이 앱
 * 실행: node tray-mini.js (또는 start-tray-mini.sh)
 * 기능: 서버 상태 확인 / 시작 / 정지 / 브라우저 열기
 */
const { app, Tray, Menu, nativeImage, shell, dialog, BrowserWindow } = require('electron');
const path = require('path');
const http = require('http');
const { spawn, execSync } = require('child_process');
const fs = require('fs');

// ── 설정 ──────────────────────────────────────────
const SERVER_PORT = 5555;
const SERVER_PY = path.resolve(__dirname, '../server.py');
const ICON_DIR = path.join(__dirname, 'assets');

let tray = null;
let serverProcess = null;
let serverState = 'unknown'; // 'running' | 'stopped' | 'starting' | 'stopping' | 'unknown'
let checkTimer = null;
let statusWindow = null;

// ── 단일 인스턴스 ──────────────────────────────────
const lock = app.requestSingleInstanceLock();
if (!lock) { app.quit(); }

// ── 아이콘 ────────────────────────────────────────
function makeIcon(state) {
  const iconFile = {
    running:  path.join(ICON_DIR, 'tray-icon.png'),
    stopped:  path.join(ICON_DIR, 'tray-icon-off.png'),
    starting: path.join(ICON_DIR, 'tray-icon.png'),
    stopping: path.join(ICON_DIR, 'tray-icon-off.png'),
  }[state] || path.join(ICON_DIR, 'tray-icon.png');

  if (fs.existsSync(iconFile)) return nativeImage.createFromPath(iconFile);
  // fallback: 빈 아이콘
  return nativeImage.createFromBuffer(Buffer.alloc(16 * 16 * 4, 0), { width: 16, height: 16 });
}

// ── 서버 상태 체크 ────────────────────────────────
function checkServer() {
  return new Promise((resolve) => {
    const req = http.request(
      { hostname: '127.0.0.1', port: SERVER_PORT, path: '/api/system/metrics', method: 'GET' },
      (res) => {
        let data = '';
        res.on('data', d => data += d);
        res.on('end', () => {
          try {
            const j = JSON.parse(data);
            resolve({ running: j.ok === true, metrics: j.metrics || {} });
          } catch { resolve({ running: false, metrics: {} }); }
        });
      }
    );
    req.on('error', () => resolve({ running: false, metrics: {} }));
    req.setTimeout(2000, () => { req.destroy(); resolve({ running: false, metrics: {} }); });
    req.end();
  });
}

// ── 서버 시작 ─────────────────────────────────────
function startServer() {
  if (serverProcess) return;
  serverState = 'starting';
  updateTray();
  
  const python = ['python3', 'python'].find(p => {
    try { execSync(`${p} --version`, { stdio: 'ignore' }); return true; } catch { return false; }
  }) || 'python3';
  
  serverProcess = spawn(python, [SERVER_PY, '--no-browser'], {
    detached: false,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  
  serverProcess.stdout.on('data', () => {});
  serverProcess.stderr.on('data', () => {});
  serverProcess.on('exit', () => {
    serverProcess = null;
    serverState = 'stopped';
    updateTray();
  });
  
  // 3초 후 상태 확인
  setTimeout(() => pollStatus(), 3000);
}

// ── 서버 정지 ─────────────────────────────────────
async function stopServer() {
  serverState = 'stopping';
  updateTray();
  
  if (serverProcess) {
    serverProcess.kill('SIGTERM');
    serverProcess = null;
  } else {
    // 외부 프로세스 종료
    try { execSync(`pkill -f "python.*server.py"`, { stdio: 'ignore' }); } catch {}
  }
  
  await new Promise(r => setTimeout(r, 1000));
  serverState = 'stopped';
  updateTray();
}

// ── 상태 폴링 ─────────────────────────────────────
let _lastMetrics = {};
async function pollStatus() {
  const { running, metrics } = await checkServer();
  _lastMetrics = metrics;
  const newState = running ? 'running' : 'stopped';
  if (newState !== serverState) {
    serverState = newState;
    updateTray();
  }
}

// ── 미니 상태 창 ──────────────────────────────────
function showStatusWindow() {
  if (statusWindow && !statusWindow.isDestroyed()) {
    statusWindow.show();
    statusWindow.focus();
    updateStatusWindow();
    return;
  }
  
  const { screen } = require('electron');
  const display = screen.getPrimaryDisplay();
  const { width, height } = display.workArea;
  
  statusWindow = new BrowserWindow({
    width: 320,
    height: 400,
    x: width - 340,
    y: height - 420,
    frame: false,
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    transparent: false,
    backgroundColor: '#161b22',
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    }
  });
  
  statusWindow.on('blur', () => {
    if (statusWindow && !statusWindow.isDestroyed()) statusWindow.hide();
  });
  statusWindow.on('closed', () => { statusWindow = null; });
  
  statusWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(getStatusHtml())}`);
}

function getStatusHtml() {
  const m = _lastMetrics;
  const isRunning = serverState === 'running';
  const cpu = m.cpu_percent || 0;
  const memPct = m.memory_percent || 0;
  const diskPct = m.disk_percent || 0;
  const activeTeams = m.active_teams || 0;
  const activeTickets = m.active_tickets || 0;
  const sseClients = m.sse_clients || 0;

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  background: #161b22;
  color: #e6edf3;
  font-family: -apple-system, 'Segoe UI', sans-serif;
  font-size: 13px;
  user-select: none;
  -webkit-app-region: drag;
}
.header {
  background: #0d1117;
  padding: 12px 16px;
  display: flex;
  align-items: center;
  gap: 10px;
  border-bottom: 1px solid #30363d;
}
.logo {
  width: 24px; height: 24px;
  background: #1B96FF;
  border-radius: 6px;
  display: flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 13px; color: white;
  flex-shrink: 0;
}
.title { font-weight: 700; font-size: 13px; }
.status-dot {
  width: 8px; height: 8px; border-radius: 50%;
  background: ${isRunning ? '#3fb950' : '#f85149'};
  margin-left: auto; flex-shrink: 0;
  ${isRunning ? 'box-shadow: 0 0 6px #3fb950;' : ''}
}
.section {
  padding: 12px 16px 0;
}
.section-title {
  color: #8b949e; font-size: 10px; font-weight: 600;
  text-transform: uppercase; letter-spacing: 0.5px;
  margin-bottom: 8px;
}
.kpi-grid {
  display: grid; grid-template-columns: 1fr 1fr 1fr;
  gap: 8px; margin-bottom: 12px;
}
.kpi {
  background: #21262d;
  border: 1px solid #30363d;
  border-radius: 8px;
  padding: 8px;
  text-align: center;
}
.kpi-val { font-size: 16px; font-weight: 700; color: #1B96FF; }
.kpi-lbl { font-size: 9px; color: #8b949e; margin-top: 2px; }
.gauge-row { margin-bottom: 8px; }
.gauge-label {
  display: flex; justify-content: space-between;
  margin-bottom: 3px; font-size: 11px;
}
.gauge-label .name { color: #8b949e; }
.gauge-label .val { color: #e6edf3; font-weight: 600; }
.gauge-bar {
  height: 4px; background: #21262d;
  border-radius: 2px; overflow: hidden;
}
.gauge-fill {
  height: 100%; border-radius: 2px;
  transition: width 0.3s ease;
}
.btn-row {
  padding: 12px 16px;
  display: grid; grid-template-columns: 1fr 1fr;
  gap: 8px;
}
.btn {
  -webkit-app-region: no-drag;
  padding: 8px 12px;
  border: none; border-radius: 6px;
  font-size: 12px; font-weight: 600;
  cursor: pointer;
  transition: opacity 0.15s;
}
.btn:hover { opacity: 0.85; }
.btn:active { opacity: 0.7; }
.btn-primary { background: #1B96FF; color: white; }
.btn-danger { background: #f85149; color: white; }
.btn-success { background: #3fb950; color: #0d1117; }
.btn-secondary { background: #21262d; color: #e6edf3; border: 1px solid #30363d; }
.btn:disabled { opacity: 0.4; cursor: not-allowed; }
.state-badge {
  display: inline-flex; align-items: center; gap: 5px;
  font-size: 11px; font-weight: 600;
  color: ${isRunning ? '#3fb950' : '#f85149'};
}
</style>
</head>
<body>
<div class="header">
  <div class="logo">U</div>
  <span class="title">U2DIA Kanban</span>
  <span class="status-dot" title="${isRunning ? '서버 실행 중' : '서버 정지됨'}"></span>
</div>

<div class="section">
  <div class="section-title">서버 상태</div>
  <div style="margin-bottom:10px">
    <span class="state-badge">${isRunning ? '● 실행 중 (포트 ${SERVER_PORT})' : '● 정지됨'}</span>
  </div>
  <div class="kpi-grid">
    <div class="kpi"><div class="kpi-val">${activeTeams}</div><div class="kpi-lbl">활성 팀</div></div>
    <div class="kpi"><div class="kpi-val">${activeTickets}</div><div class="kpi-lbl">활성 티켓</div></div>
    <div class="kpi"><div class="kpi-val">${sseClients}</div><div class="kpi-lbl">연결</div></div>
  </div>
</div>

${isRunning ? `
<div class="section">
  <div class="section-title">PC 리소스</div>
  <div class="gauge-row">
    <div class="gauge-label"><span class="name">CPU</span><span class="val">${cpu}%</span></div>
    <div class="gauge-bar"><div class="gauge-fill" style="width:${cpu}%;background:${cpu > 80 ? '#f85149' : cpu > 60 ? '#d29922' : '#3fb950'}"></div></div>
  </div>
  <div class="gauge-row">
    <div class="gauge-label"><span class="name">메모리</span><span class="val">${memPct}%</span></div>
    <div class="gauge-bar"><div class="gauge-fill" style="width:${memPct}%;background:${memPct > 85 ? '#f85149' : '#1B96FF'}"></div></div>
  </div>
  <div class="gauge-row">
    <div class="gauge-label"><span class="name">디스크</span><span class="val">${diskPct}%</span></div>
    <div class="gauge-bar"><div class="gauge-fill" style="width:${diskPct}%;background:#a371f7"></div></div>
  </div>
</div>` : ''}

<div class="btn-row">
  ${isRunning
    ? `<button class="btn btn-primary" onclick="openBrowser()">🌐 브라우저</button>
       <button class="btn btn-danger" onclick="stopSrv()">■ 서버 정지</button>`
    : `<button class="btn btn-success" onclick="startSrv()">▶ 서버 시작</button>
       <button class="btn btn-secondary" onclick="closeWin()">✕ 닫기</button>`
  }
</div>

<script>
const { ipcRenderer } = require('electron');
function openBrowser() { ipcRenderer.send('mini:open-browser'); }
function startSrv()   { ipcRenderer.send('mini:start'); }
function stopSrv()    { ipcRenderer.send('mini:stop'); }
function closeWin()   { window.close(); }
</script>
</body>
</html>`;
}

function updateStatusWindow() {
  if (!statusWindow || statusWindow.isDestroyed()) return;
  statusWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(getStatusHtml())}`);
}

// ── 트레이 메뉴 업데이트 ──────────────────────────
function updateTray() {
  if (!tray) return;
  const isRunning = serverState === 'running';
  const isStarting = serverState === 'starting';
  const isStopping = serverState === 'stopping';

  const stateLabel = {
    running: `실행 중 (포트 ${SERVER_PORT})`,
    stopped: '정지됨',
    starting: '시작 중...',
    stopping: '종료 중...',
    unknown: '확인 중...',
  }[serverState] || '알 수 없음';

  tray.setToolTip(`U2DIA Kanban — ${stateLabel}`);
  tray.setImage(makeIcon(serverState));

  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'U2DIA Kanban Board', enabled: false },
    { label: `서버: ${stateLabel}`, enabled: false },
    { type: 'separator' },
    { label: '📊 상태 보기', click: () => showStatusWindow() },
    { label: '🌐 브라우저로 열기', enabled: isRunning, click: () => shell.openExternal(`http://localhost:${SERVER_PORT}`) },
    { type: 'separator' },
    { label: '▶ 서버 시작', enabled: !isRunning && !isStarting && !isStopping, click: () => startServer() },
    { label: '■ 서버 정지', enabled: isRunning, click: () => stopServer() },
    { label: '↺ 서버 재시작', enabled: isRunning, click: async () => { await stopServer(); setTimeout(() => startServer(), 1000); } },
    { type: 'separator' },
    { label: '⚙ Server Manager 열기', click: () => {
        const smDir = path.join(__dirname, 'server-manager-app');
        const electron = path.join(smDir, 'node_modules', 'electron', 'dist', 'electron');
        if (fs.existsSync(electron)) {
          const env = Object.assign({}, process.env);
          delete env.ELECTRON_RUN_AS_NODE;
          spawn(electron, [smDir], { detached: true, stdio: 'ignore', env });
        }
    }},
    { type: 'separator' },
    { label: '✕ 종료', click: () => { app.isQuitting = true; app.quit(); } }
  ]));
}

// ── IPC (상태 창에서 메시지) ──────────────────────
app.whenReady().then(() => {
  app.setAppUserModelId('com.u2dia.kanban-tray');
  app.dock && app.dock.hide();

  // IPC
  const { ipcMain } = require('electron');
  ipcMain.on('mini:open-browser', () => shell.openExternal(`http://localhost:${SERVER_PORT}`));
  ipcMain.on('mini:start', () => { statusWindow && statusWindow.hide(); startServer(); });
  ipcMain.on('mini:stop', () => { stopServer(); updateStatusWindow(); });

  // 트레이 생성
  tray = new Tray(makeIcon('unknown'));
  tray.setToolTip('U2DIA Kanban Board');

  // Linux: right-click → context menu, left-click → status window
  tray.on('click', () => showStatusWindow());
  tray.on('right-click', () => tray.popUpContextMenu());

  updateTray();

  // 초기 상태 확인 + 자동 시작
  pollStatus().then(() => {
    if (serverState === 'stopped') {
      startServer();
    }
  });

  // 5초마다 폴링
  checkTimer = setInterval(() => {
    pollStatus().then(() => {
      if (statusWindow && !statusWindow.isDestroyed() && !statusWindow.isVisible() === false) {
        updateStatusWindow();
      }
    });
  }, 5000);
});

app.on('window-all-closed', () => {});  // 창 없어도 유지
app.on('before-quit', async () => {
  if (checkTimer) clearInterval(checkTimer);
});
