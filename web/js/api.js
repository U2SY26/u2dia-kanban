/* U2DIA AI SERVER AGENT — API Client */
const API = {
  base: '',

  async fetch(path, options = {}) {
    const url = this.base + path;
    const opts = {
      headers: { 'Content-Type': 'application/json', ...options.headers },
      credentials: 'include',
      ...options
    };
    try {
      const res = await fetch(url, opts);
      if (res.status === 401) {
        location.href = '/login';
        return { ok: false, error: 'unauthorized' };
      }
      return await res.json();
    } catch (e) {
      console.error('[API]', path, e);
      return { ok: false, error: 'network', message: e.message };
    }
  },

  get(path) { return this.fetch(path); },

  post(path, body) {
    return this.fetch(path, { method: 'POST', body: JSON.stringify(body) });
  },

  put(path, body) {
    return this.fetch(path, { method: 'PUT', body: JSON.stringify(body) });
  },

  del(path) {
    return this.fetch(path, { method: 'DELETE' });
  },

  // ── 팀 ──
  teams()        { return this.get('/api/teams'); },
  teamBoard(id)  { return this.get(`/api/teams/${id}/board`); },
  teamStats(id)  { return this.get(`/api/teams/${id}/stats`); },
  teamActivity(id, limit=50) { return this.get(`/api/teams/${id}/activity?limit=${limit}`); },
  teamArchive(id, force=false) { return this.post(`/api/teams/${id}/archive`, { force }); },
  teamValidateCompletion(id) { return this.get(`/api/teams/${id}/validate-completion`); },

  // ── 슈퍼바이저 ──
  overview()    { return this.get('/api/supervisor/overview'); },
  globalStats() { return this.get('/api/supervisor/stats'); },
  globalActivity(limit=100) { return this.get(`/api/supervisor/activity?limit=${limit}`); },
  heatmap(weeks=16) { return this.get(`/api/supervisor/heatmap?weeks=${weeks}`); },
  heatmap24h() { return this.get('/api/supervisor/heatmap?mode=24h'); },
  heatmap10min() { return this.get('/api/supervisor/heatmap?mode=10min'); },
  timeline(hours=24) { return this.get(`/api/supervisor/timeline?hours=${hours}`); },

  // ── 티켓 ──
  ticketDetail(id) { return this.get(`/api/tickets/${id}/detail`); },
  ticketStatus(id, status) { return this.post(`/api/tickets/${id}/status`, { status }); },

  // ── 멤버 ──
  memberDetail(id) { return this.get(`/api/members/${id}/detail`); },

  // ── 메시지 ──
  messages(ticketId) { return this.get(`/api/tickets/${ticketId}/messages`); },

  // ── 산출물 ──
  artifacts(ticketId) { return this.get(`/api/tickets/${ticketId}/artifacts`); },
  ticketThread(ticketId) { return this.get(`/api/tickets/${ticketId}/thread`); },

  // ── 피드백 ──
  feedbackList(ticketId) { return this.get(`/api/tickets/${ticketId}/feedback`); },
  feedbackCreate(ticketId, data) { return this.post(`/api/tickets/${ticketId}/feedback`, data); },
  feedbackSummary(teamId) { return this.get(`/api/teams/${teamId}/feedback/summary`); },

  // ── 시스템 ──
  metrics() { return this.get('/api/system/metrics'); },
  clients() { return this.get('/api/system/clients'); },
  nodeProcesses() { return this.get('/api/system/node-processes'); },
  killZombieMcp() { return this.post('/api/system/kill-zombie-mcp', {}); },

  // ── 토큰 사용량 ──
  teamUsage(id) { return this.get(`/api/teams/${id}/usage`); },
  ticketUsage(id) { return this.get(`/api/tickets/${id}/usage`); },

  // ── 글로벌 사용량 ──
  usageGlobal() { return this.get('/api/usage/global'); },

  // ── 서버 설정 ──
  settings() { return this.get('/api/settings'); },
  settingsPut(data) { return this.put('/api/settings', data); },

  // ── Claude Code 세션 ──
  claudeLaunch(data) { return this.post('/api/claude/launch', data); },
  claudeSessions() { return this.get('/api/claude/sessions'); },
  claudeStop(session_id) { return this.post('/api/claude/stop', { session_id }); },

  // ── 에이전트 KPI ──
  agentsKpi(teamId) { return this.get('/api/agents/kpi' + (teamId ? '?team_id=' + teamId : '')); },
  residentKpi() { return this.get('/api/resident/kpi'); },

  // ── OKR / 전략과제 ──
  teamObjectives(teamId) { return this.get('/api/teams/' + teamId + '/objectives'); },
  createObjective(teamId, data) { return this.post('/api/teams/' + teamId + '/objectives', data); },
  updateObjective(objId, data) { return this.put('/api/objectives/' + objId, data); },
  updateKeyResult(krId, data) { return this.put('/api/key-results/' + krId, data); },

  // ── 상주 에이전트 ──
  residentHistory(limit=200, type='all') { return this.get(`/api/resident/history?limit=${limit}&type=${type}`); },

  // ── Project Inventory ──
  projectInventory() { return this.get('/api/projects/inventory'); },
  projectArchitecture() { return this.get('/api/projects/architecture'); },

  // ── Sprint (gstack-inspired) ──
  sprintCreate(teamId, data) { return this.post(`/api/teams/${teamId}/sprints`, data); },
  sprintList(teamId, status) { return this.get(`/api/teams/${teamId}/sprints` + (status ? '?status=' + status : '')); },
  sprintGet(sprintId) { return this.get(`/api/sprints/${sprintId}`); },
  sprintPhase(sprintId, phase) { return this.put(`/api/sprints/${sprintId}/phase`, { phase }); },
  sprintGate(sprintId, data) { return this.post(`/api/sprints/${sprintId}/gates`, data); },
  sprintMetrics(sprintId) { return this.post(`/api/sprints/${sprintId}/metrics`, {}); },
  sprintVelocity(teamId) { return this.get(`/api/teams/${teamId}/velocity`); },
  sprintBurndown(sprintId) { return this.get(`/api/sprints/${sprintId}/burndown`); },
  sprintCrossReview(sprintId, data) { return this.post(`/api/sprints/${sprintId}/cross-review`, data); },
  sprintRetro(sprintId) { return this.get(`/api/sprints/${sprintId}/retro`); },
  sprintGlobalStats() { return this.get('/api/sprints/global/stats'); },

  // ── 아카이브 ──
  archives()    { return this.get('/api/archives'); },
  archiveDetail(id) { return this.get(`/api/archives/${id}`); },

  // ── 히스토리 & 벤치마킹 ──
  historyTeams()       { return this.get('/api/history/teams'); },
  historyTimeline(id, limit=500) { return this.get(`/api/history/teams/${id}/timeline?limit=${limit}`); },
  historyBenchmark()   { return this.get('/api/history/benchmark'); },
  historySnapshot(id)  { return this.post(`/api/history/snapshot/${id}`, {}); }
};
