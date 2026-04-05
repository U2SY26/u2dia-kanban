/* U2DIA AI SERVER AGENT — SSE Manager */
const SSE = {
  _connections: {},
  _listeners: [],
  _globalConn: null,

  /** 글로벌 SSE 연결 */
  connectGlobal(onEvent) {
    if (this._globalConn) this._globalConn.close();
    const es = new EventSource('/api/supervisor/events');
    es.onmessage = (e) => {
      try {
        const data = JSON.parse(e.data);
        this._listeners.forEach(fn => fn(data));
        if (onEvent) onEvent(data);
      } catch {}
    };
    es.addEventListener('connected', () => {
      this._updateStatus(true);
    });
    es.onerror = () => {
      this._updateStatus(false);
      setTimeout(() => this.connectGlobal(onEvent), 5000);
    };
    this._globalConn = es;
  },

  /** 팀별 SSE 연결 */
  connectTeam(teamId, onEvent) {
    this.disconnectTeam(teamId);
    const es = new EventSource(`/api/teams/${teamId}/events`);
    es.onmessage = (e) => {
      try {
        const data = JSON.parse(e.data);
        data._teamId = teamId;
        if (onEvent) onEvent(data);
      } catch {}
    };
    es.onerror = () => {
      setTimeout(() => this.connectTeam(teamId, onEvent), 5000);
    };
    this._connections[teamId] = es;
  },

  disconnectTeam(teamId) {
    if (this._connections[teamId]) {
      this._connections[teamId].close();
      delete this._connections[teamId];
    }
  },

  disconnectAll() {
    Object.keys(this._connections).forEach(id => this.disconnectTeam(id));
    if (this._globalConn) {
      this._globalConn.close();
      this._globalConn = null;
    }
  },

  /** 전역 이벤트 리스너 추가 */
  onGlobalEvent(fn) {
    this._listeners.push(fn);
    return () => { this._listeners = this._listeners.filter(f => f !== fn); };
  },

  _updateStatus(connected) {
    const dot = document.getElementById('sseStatus');
    if (dot) {
      dot.className = 'sse-dot ' + (connected ? 'connected' : 'error');
      dot.title = connected ? '실시간 연결됨' : '연결 끊김';
    }
  }
};
