const { Notification } = require('electron');
const http = require('http');
const { EventEmitter } = require('events');

class NotificationManager extends EventEmitter {
  constructor(settingsStore) {
    super();
    this.settings = settingsStore;
    this._connection = null;
    this._reconnectTimer = null;
    this._enabled = this.settings.get('notifications') !== false;
    this._connected = false;
    this._buffer = '';
  }

  get enabled() { return this._enabled; }
  set enabled(val) {
    this._enabled = val;
    this.settings.set('notifications', val);
    this.emit('toggled', val);
  }

  connect() {
    this.disconnect();
    const port = this.settings.get('port') || 5555;

    const req = http.get({
      hostname: '127.0.0.1', port,
      path: '/api/supervisor/events',
      headers: { 'Accept': 'text/event-stream' },
    }, (res) => {
      if (res.statusCode !== 200) { this._scheduleReconnect(); return; }
      this._connected = true;
      this._buffer = '';
      this.emit('connected');

      res.setEncoding('utf-8');
      res.on('data', (chunk) => { this._buffer += chunk; this._processBuffer(); });
      res.on('end', () => { this._connected = false; this.emit('disconnected'); this._scheduleReconnect(); });
      res.on('error', () => { this._connected = false; this.emit('disconnected'); this._scheduleReconnect(); });
    });
    req.on('error', () => { this._connected = false; this._scheduleReconnect(); });
    req.setTimeout(0);
    this._connection = req;
  }

  disconnect() {
    if (this._reconnectTimer) { clearTimeout(this._reconnectTimer); this._reconnectTimer = null; }
    if (this._connection) { try { this._connection.destroy(); } catch (_) {} this._connection = null; }
    this._connected = false;
    this._buffer = '';
  }

  _processBuffer() {
    const lines = this._buffer.split('\n');
    this._buffer = lines.pop() || '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith(':')) continue;
      if (trimmed.startsWith('data:')) {
        try {
          const event = JSON.parse(trimmed.slice(5).trim());
          this._handleEvent(event);
        } catch (_) {}
      }
    }
  }

  _handleEvent(event) {
    this.emit('event', event);
    if (!this._enabled || !Notification.isSupported()) return;
    const { type, data } = event;
    const info = this._getNotificationInfo(type, data);
    if (!info) return;
    const notif = new Notification({ title: info.title, body: info.body, silent: false });
    notif.on('click', () => this.emit('notification-clicked', event));
    notif.show();
  }

  _getNotificationInfo(type, data) {
    const prefix = 'U2DIA AI SERVER AGENT';
    switch (type) {
      case 'team_created': return { title: prefix, body: `새 팀: ${data.name || '(이름 없음)'}` };
      case 'ticket_created': return { title: prefix, body: `새 티켓: ${data.title || '(제목 없음)'}` };
      case 'ticket_status_changed': return { title: prefix, body: `상태 변경: ${data.status || '?'}` };
      case 'member_spawned': return { title: prefix, body: `새 에이전트: ${data.role || '?'}` };
      case 'feedback_created': return { title: prefix, body: `피드백: ${data.score || '?'}/5` };
      case 'team_archived': return { title: prefix, body: `팀 아카이브: ${data.team_name || '?'}` };
      default: return null;
    }
  }

  _scheduleReconnect() {
    if (this._reconnectTimer) return;
    this._reconnectTimer = setTimeout(() => { this._reconnectTimer = null; this.connect(); }, 5000);
  }
}

module.exports = NotificationManager;
