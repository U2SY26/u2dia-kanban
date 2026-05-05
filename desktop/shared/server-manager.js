const { spawn } = require('child_process');
const { EventEmitter } = require('events');
const http = require('http');
const net = require('net');
const path = require('path');

class ServerManager extends EventEmitter {
  constructor(settingsStore, serverPyPath, userDataPath) {
    super();
    this.settings = settingsStore;
    this.serverPyPath = serverPyPath;
    this.userDataPath = userDataPath;
    this.process = null;
    this.state = 'stopped'; // stopped | starting | running | error
    this.port = null;
    this.host = null;
    this._restartCount = 0;
  }

  async _isPortAvailable(port) {
    return new Promise((resolve) => {
      const server = net.createServer();
      server.once('error', () => resolve(false));
      server.once('listening', () => { server.close(); resolve(true); });
      server.listen(port, '127.0.0.1');
    });
  }

  async start() {
    if (this.state === 'running' || this.state === 'starting') return;

    const settings = this.settings.getAll();
    this.port = settings.port || 5555;
    this.host = settings.allowRemoteAccess ? '0.0.0.0' : '127.0.0.1';
    const pythonPath = settings.pythonPath || 'python';

    const available = await this._isPortAvailable(this.port);
    if (!available) {
      // 이미 서버가 실행 중인지 확인 (외부에서 직접 실행한 경우)
      try {
        await this._healthCheck();
        this.state = 'running';
        this._restartCount = 0;
        this.emit('state-changed', this.state, `외부 서버 감지 (포트 ${this.port})`);
        return;
      } catch (_) {
        this.state = 'error';
        this.emit('state-changed', this.state, `포트 ${this.port}이 이미 사용 중입니다`);
        return;
      }
    }

    this.state = 'starting';
    this.emit('state-changed', this.state);

    // DB를 앱 데이터 폴더에 저장 (업데이트 시에도 유지)
    // web/은 server.py와 같은 디렉토리에 위치
    const env = { ...process.env };
    if (this.userDataPath) {
      env.KANBAN_DB_PATH = path.join(this.userDataPath, 'agent_teams.db');
    }
    env.KANBAN_WEB_DIR = path.join(path.dirname(this.serverPyPath), 'web');

    this.process = spawn(pythonPath, [
      this.serverPyPath,
      '--port', String(this.port),
      '--host', this.host,
      '--no-browser'
    ], {
      cwd: path.dirname(this.serverPyPath),
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });

    this.process.stdout.on('data', (data) => {
      const text = data.toString();
      this.emit('log', text);
      if (text.includes('Ctrl+C to stop')) {
        this.state = 'running';
        this._restartCount = 0;
        this.emit('state-changed', this.state);
      }
    });

    this.process.stderr.on('data', (data) => {
      this.emit('log', data.toString());
    });

    this.process.on('error', (err) => {
      this.state = 'error';
      this.process = null;
      this.emit('state-changed', this.state, err.message);
    });

    this.process.on('exit', (code) => {
      const wasRunning = this.state === 'running';
      this.state = code === 0 ? 'stopped' : 'error';
      this.process = null;
      this.emit('state-changed', this.state);
      this.emit('exit', code);

      if (wasRunning && code !== 0 && this._restartCount < 3) {
        this._restartCount++;
        const delay = Math.pow(2, this._restartCount) * 1000;
        this.emit('log', `서버 비정상 종료. ${delay / 1000}초 후 재시작 (${this._restartCount}/3)\n`);
        setTimeout(() => this.start(), delay);
      }
    });

    await this._waitForReady(15000);
  }

  async _waitForReady(timeoutMs) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      if (this.state === 'running') return;
      if (this.state === 'error' || this.state === 'stopped') return;
      try {
        await this._healthCheck();
        if (this.state === 'starting') {
          this.state = 'running';
          this._restartCount = 0;
          this.emit('state-changed', this.state);
        }
        return;
      } catch (_) {
        await new Promise(r => setTimeout(r, 500));
      }
    }
    if (this.state === 'starting') {
      this.state = 'error';
      this.emit('state-changed', this.state, '서버 시작 시간 초과');
    }
  }

  _healthCheck() {
    return new Promise((resolve, reject) => {
      const req = http.get(`http://127.0.0.1:${this.port}/api/teams`, (res) => {
        let body = '';
        res.on('data', d => body += d);
        res.on('end', () => {
          try {
            const json = JSON.parse(body);
            json.ok ? resolve() : reject(new Error('not ok'));
          } catch { reject(new Error('bad json')); }
        });
      });
      req.on('error', reject);
      req.setTimeout(2000, () => { req.destroy(); reject(new Error('timeout')); });
    });
  }

  async stop() {
    if (!this.process) return;
    return new Promise((resolve) => {
      const onExit = () => resolve();
      this.process.once('exit', onExit);

      if (process.platform === 'win32') {
        spawn('taskkill', ['/pid', String(this.process.pid), '/f', '/t'], { windowsHide: true });
      } else {
        this.process.kill('SIGINT');
      }

      setTimeout(() => {
        if (this.process) {
          try { this.process.kill('SIGKILL'); } catch (_) {}
        }
        resolve();
      }, 5000);
    });
  }

  async restart() {
    await this.stop();
    await new Promise(r => setTimeout(r, 500));
    await this.start();
  }

  getBaseUrl() {
    return `http://127.0.0.1:${this.port}`;
  }
}

module.exports = ServerManager;
