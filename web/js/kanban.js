/* U2DIA AI SERVER AGENT — 칸반보드 (팀 상세) */
const Kanban = {
  _teamId: null,
  _data: null,
  _memberMap: {},
  _prevTicketPositions: {},
  _dragTicketId: null,
  _isDragging: false,

  async render(container, teamId) {
    this._teamId = teamId;
    this._prevTicketPositions = {};
    container.innerHTML = `
      <div class="kanban-layout">
        <div class="kanban-sidebar" id="kbSidebar"></div>
        <div class="kanban-board-area">
          <div id="kbBannerArea"></div>
          <div class="kanban-board-columns" id="kbColumns"></div>
        </div>
      </div>
      <div class="app-footer" id="kbFooter">
        <div class="footer-header">
          <span>실시간 로그</span>
          <span id="kbLogCount">0건</span>
        </div>
        <div class="footer-scroll" id="kbLogs"></div>
      </div>`;
    await this.refresh();
    this._startSSE();
    this._startProgressPoller();
    this._startBoardRefreshTimer();
  },

  async refresh() {
    const [boardRes, activity, usage] = await Promise.all([
      API.teamBoard(this._teamId),
      API.teamActivity(this._teamId, 100),
      API.teamUsage(this._teamId)
    ]);
    if (boardRes.ok) {
      const board = boardRes.board;
      this._data = board;
      this._buildMemberMap(board.members || []);
      this._renderSidebar(board, usage.ok ? usage : null);
      this._renderColumns(board);
      this._checkAutoArchive(board);
    }
    if (activity.ok) this._renderLogs(activity.logs || []);
    this._updateHeaderForTeam(boardRes.ok ? boardRes.board : null);
  },

  async _refreshBoard() {
    if (this._isDragging) return;
    const boardRes = await API.teamBoard(this._teamId);
    if (boardRes.ok) {
      const board = boardRes.board;
      this._data = board;
      this._buildMemberMap(board.members || []);
      this._renderColumns(board);
      this._renderSidebar(board, null);
      this._checkAutoArchive(board);
    }
  },

  _buildMemberMap(members) {
    this._memberMap = {};
    members.forEach(m => { this._memberMap[m.member_id] = m; });
  },

  _renderSidebar(data, usage) {
    const el = Utils.$('kbSidebar');
    if (!el) return;
    const team = data.team || {};
    const members = data.members || [];
    const tickets = data.tickets || [];
    const total = tickets.length;
    const done = tickets.filter(t => t.status === 'Done').length;
    const progress = total > 0 ? Math.round(done / total * 100) : 0;

    let html = `
      <div class="section-title">팀 정보</div>
      <div class="text-sm fw-bold" style="margin-bottom:4px">${Utils.esc(team.name || '')}</div>
      <div class="text-xs text-muted" style="margin-bottom:8px">리더: ${Utils.esc(team.leader_agent || '-')}</div>
      <div class="progress-bar"><div class="progress-fill" style="width:${progress}%;background:${Utils.progressColor(progress)}"></div></div>
      <div class="text-xs text-muted" style="margin:4px 0 12px">완료 ${done}/${total} (${progress}%)</div>

      <div style="margin-bottom:12px">
        <button class="btn btn-sm btn-primary" onclick="AgentOffice.open('${Utils.esc(this._teamId)}')" style="width:100%;display:flex;align-items:center;justify-content:center;gap:6px">
          <span style="font-size:14px">🏢</span> Agent Office
        </button>
      </div>

      <div class="section-title">에이전트 (${members.length})</div>`;

    members.forEach(m => {
      const dotClass = m.status === 'Working' ? 'working' : m.status === 'Blocked' ? 'blocked' : 'idle';
      const task = m.current_ticket_id || '-';
      html += `
        <div class="agent-card" style="margin-bottom:4px">
          <span class="agent-dot ${dotClass}"></span>
          <div class="agent-info">
            <div class="agent-name">${Utils.esc(m.display_name || m.role)}</div>
            <div class="agent-task">${Utils.esc(task)}</div>
          </div>
        </div>`;
    });

    // Token usage
    if (usage && usage.ok) {
      html += `<div class="section-title" style="margin-top:16px">토큰 사용량</div>`;
      html += `
        <div class="token-stat"><span class="token-label">총 입력</span><span class="token-value">${Utils.numFmt(usage.total_input || 0)}</span></div>
        <div class="token-stat"><span class="token-label">총 출력</span><span class="token-value">${Utils.numFmt(usage.total_output || 0)}</span></div>
        <div class="token-stat"><span class="token-label">예상 비용</span><span class="token-value token-cost">${Utils.costFmt(usage.total_cost || 0)}</span></div>`;
      if (usage.by_model) {
        Object.entries(usage.by_model).forEach(([model, stats]) => {
          html += `<div class="token-stat"><span class="token-label" style="color:var(--cyan)">${Utils.esc(model)}</span><span class="token-value">${Utils.numFmt(stats.tokens || 0)}</span></div>`;
        });
      }
    }

    // Status distribution
    html += `<div class="section-title" style="margin-top:16px">상태 분포</div>`;
    const sc = {};
    tickets.forEach(t => { sc[t.status] = (sc[t.status] || 0) + 1; });
    Utils.COLUMNS.forEach(col => {
      const n = sc[col] || 0;
      if (!n && total > 0) return;
      html += `<div class="token-stat"><span class="token-label" style="color:${Utils.statusColor(col)}">${Utils.colName(col)}</span><span class="token-value">${n}</span></div>`;
    });

    el.innerHTML = html;
  },

  _renderColumns(data) {
    const el = Utils.$('kbColumns');
    if (!el) return;
    const tickets = data.tickets || [];

    // Track positions for animation
    const newPositions = {};
    tickets.forEach(t => { newPositions[t.ticket_id] = t.status; });
    const oldPositions = this._prevTicketPositions;

    let html = '';
    Utils.COLUMNS.forEach(col => {
      const colTickets = tickets
        .filter(t => t.status === col)
        .sort((a, b) => Utils.priorityOrder(a.priority) - Utils.priorityOrder(b.priority));

      html += `
        <div class="kb-col" data-status="${col}"
             ondragover="event.preventDefault();this.classList.add('drop-target')"
             ondragleave="this.classList.remove('drop-target')"
             ondrop="Kanban.onDrop(event,'${col}')">
          <div class="kb-col-header" style="border-bottom-color:${Utils.statusColor(col)}">
            <span>${Utils.colName(col)}</span>
            <span class="kb-col-count">${colTickets.length}</span>
          </div>
          <div class="kb-col-body">
            ${colTickets.length ? colTickets.map(t => {
              const wasMoved = oldPositions[t.ticket_id] && oldPositions[t.ticket_id] !== col;
              const isNew = !oldPositions[t.ticket_id] && Object.keys(oldPositions).length > 0;
              const animClass = wasMoved ? 'kb-card-moved' : (isNew ? 'kb-card-enter' : '');
              return this._buildCard(t, animClass);
            }).join('') : `<div class="kb-col-empty">카드 없음</div>`}
          </div>
        </div>`;
    });

    el.innerHTML = html;
    this._prevTicketPositions = newPositions;
  },

  _buildCard(t, animClass) {
    const member = this._memberMap[t.assigned_member_id];
    const agentName = member ? (member.display_name || member.role) : '';
    const initial = Utils.agentInitial(agentName);
    const tags = Array.isArray(t.tags) ? t.tags : [];
    const pri = t.priority || 'Medium';

    let agentHtml = '';
    if (agentName) {
      agentHtml = `
        <div class="kb-card-agent">
          <span class="kb-card-avatar">${Utils.esc(initial)}</span>
          <span>${Utils.esc(agentName)}</span>
        </div>`;
    }

    let tagsHtml = '';
    if (tags.length) {
      tagsHtml = `<div class="kb-card-tags">${tags.slice(0, 3).map(tag =>
        `<span class="kb-card-tag">${Utils.esc(tag)}</span>`
      ).join('')}${tags.length > 3 ? `<span class="kb-card-tag">+${tags.length - 3}</span>` : ''}</div>`;
    }

    const isInProgress = t.status === 'InProgress';
    const progressNote = t.progress_note ? Utils.esc(t.progress_note.substring(0, 80)) : '';
    const lastPing = t.last_ping_at;
    const pingAge = lastPing ? Math.floor((Date.now() - new Date(lastPing).getTime()) / 1000) : null;
    const pingRecent = pingAge !== null && pingAge < 30;

    const progressHtml = isInProgress ? `
      <div class="kb-card-progress" id="prog-${t.ticket_id}">
        ${pingRecent ? '<span class="kb-live-dot"></span>' : ''}
        <span class="kb-progress-text">${progressNote || '진행 중...'}</span>
      </div>` : '';

    return `
      <div class="kb-card ${animClass}" draggable="true"
           data-ticket-id="${t.ticket_id}"
           data-priority="${pri}"
           ondragstart="Kanban.onDragStart(event,'${t.ticket_id}')"
           ondragend="Kanban.onDragEnd(event)"
           onclick="Modal.open('${t.ticket_id}')">
        <div class="kb-card-title">${Utils.esc(t.title)}</div>
        ${progressHtml}
        <div class="kb-card-meta">
          <span class="pri pri-${pri}">${pri}</span>
          ${agentHtml}
        </div>
        ${tagsHtml}
        <div class="kb-card-footer">
          <span>${Utils.relTime(t.started_at || t.created_at)}</span>
          <span>${t.ticket_id}</span>
        </div>
      </div>`;
  },

  _renderLogs(logs) {
    const el = Utils.$('kbLogs');
    const cnt = Utils.$('kbLogCount');
    if (!el) return;
    if (cnt) cnt.textContent = logs.length + '건';
    el.innerHTML = logs.map(l =>
      `<div class="log-entry" data-type="${Utils.esc(l.action || '')}">
        <div class="log-head">
          <span class="log-time">${Utils.timeFmt(l.created_at)}</span>
          <span class="log-agent">${Utils.esc(l.agent_name || l.member_id || '-')}</span>
          <span class="log-action">${Utils.esc(l.action)}</span>
        </div>
        <div class="log-msg">${Utils.esc(l.message || '')}</div>
      </div>`
    ).join('');
  },

  _updateHeaderForTeam(data) {
    const el = Utils.$('headerStats');
    if (!el || !data) return;
    const team = data.team || {};
    const tickets = data.tickets || [];
    const done = tickets.filter(t => t.status === 'Done').length;
    el.innerHTML = `
      <div class="header-stat fw-bold" style="color:var(--brand)">${Utils.esc(team.name || '')}</div>
      <div class="header-stat"><span class="val">${data.members?.length || 0}</span> 에이전트</div>
      <div class="header-stat"><span class="val">${tickets.length}</span> 티켓</div>
      <div class="header-stat"><span class="val">${done}</span> 완료</div>
    `;
  },

  // ── Drag & Drop ──
  onDragStart(e, ticketId) {
    this._dragTicketId = ticketId;
    this._isDragging = true;
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', ticketId);
    requestAnimationFrame(() => {
      const card = document.querySelector(`[data-ticket-id="${ticketId}"]`);
      if (card) card.classList.add('dragging');
    });
  },

  onDragEnd(e) {
    this._isDragging = false;
    document.querySelectorAll('.dragging').forEach(el => el.classList.remove('dragging'));
    document.querySelectorAll('.drop-target').forEach(el => el.classList.remove('drop-target'));
  },

  async onDrop(e, newStatus) {
    e.preventDefault();
    e.currentTarget.classList.remove('drop-target');
    if (!this._dragTicketId) return;

    const ticketId = this._dragTicketId;
    this._dragTicketId = null;
    this._isDragging = false;
    document.querySelectorAll('.dragging').forEach(el => el.classList.remove('dragging'));

    const res = await API.ticketStatus(ticketId, newStatus);
    if (res.ok) {
      await this._refreshBoard();
    }
  },

  // ── Auto Archive ──
  _checkAutoArchive(data) {
    const banner = Utils.$('kbBannerArea');
    if (!banner) return;
    const tickets = data.tickets || [];
    const total = tickets.length;
    const done = tickets.filter(t => t.status === 'Done').length;

    // 🏢 Agent Office 버튼 (항상 표시)
    let bannerHtml = `<div style="display:flex;align-items:center;gap:8px;padding:6px 12px">
      <button class="btn btn-sm btn-primary" onclick="AgentOffice.open('${Utils.esc(this._teamId)}')" style="display:flex;align-items:center;gap:6px;font-size:12px">
        <span style="font-size:16px">🏢</span> Agent Office
      </button>
      <span style="font-size:11px;color:var(--muted)">${done}/${total} (${total > 0 ? Math.round(done/total*100) : 0}%)</span>
    </div>`;

    if (total > 0 && done === total) {
      bannerHtml += `
        <div class="kb-complete-banner">
          <h3>모든 작업 완료!</h3>
          <p>전체 ${total}개 티켓이 완료되었습니다</p>
          <button class="btn btn-primary" onclick="Kanban.archiveTeam()">팀 아카이브</button>
        </div>`;
    }
    banner.innerHTML = bannerHtml;
  },

  async archiveTeam() {
    if (!confirm('이 팀을 아카이브하시겠습니까? 대시보드에서 제거됩니다.')) return;
    const res = await API.teamArchive(this._teamId);
    if (res.ok) {
      Router.navigate('#/');
    } else {
      alert(res.message || '아카이브 실패');
    }
  },

  // ── SSE 메시지 포맷터 ──
  _fmtSSE(evtType, d) {
    if (!d) return evtType;
    if (typeof d === 'string') return d;
    if (d.message) return d.message;
    if (d.title) return d.title;
    if (d.ticket_title) return d.ticket_title + (d.status ? ' → ' + d.status : '');
    if (d.content) return typeof d.content === 'string' ? d.content.substring(0, 120) : String(d.content);
    if (d.name) return d.name;
    if (d.status) return (d.ticket_id || '') + ' → ' + d.status;
    if (d.role) return (d.member_id || '') + ' (' + d.role + ')';
    if (d.score != null) return '점수: ' + d.score;
    if (d.result) return String(d.result);
    if (d.alive != null) return (d.ticket_id || '') + (d.alive ? ' ♥' : ' ✖');
    return evtType;
  },

  // ── SSE ──
  _startSSE() {
    SSE.connectTeam(this._teamId, (data) => {
      // Log feed
      const el = Utils.$('kbLogs');
      if (el) {
        const evtType = data.event_type || data.type || '-';
        // heartbeat은 로그에 추가하지 않음 (노이즈 방지)
        if (evtType === 'ticket_heartbeat') { /* skip */ }
        else {
          const d = data.data || data.payload || {};
          const agentName = (d.member_id || d.from || d.sender || data.agent_name || '-');
          const msg = this._fmtSSE(evtType, d);
          const entry = `<div class="log-entry" data-type="${Utils.esc(evtType)}">
            <div class="log-head">
              <span class="log-time">${Utils.timeFmt(data.ts || data.timestamp || new Date().toISOString())}</span>
              <span class="log-agent">${Utils.esc(agentName)}</span>
              <span class="log-action">${Utils.esc(evtType)}</span>
            </div>
            <div class="log-msg">${Utils.esc(msg)}</div>
          </div>`;
          el.insertAdjacentHTML('afterbegin', entry);
          while (el.children.length > 300) el.removeChild(el.lastChild);
        }
      }

      // Auto-refresh for key events (triggers card animation)
      const refreshEvents = ['ticket_created', 'ticket_status_changed', 'member_spawned', 'ticket_claimed'];
      const evType = data.event_type || data.type;
      if (refreshEvents.includes(evType)) {
        this._refreshBoard();
      }
      // 진행상황 업데이트: 카드 패치 (전체 리렌더 없이)
      if (evType === 'activity_logged' && data.data && data.data.ticket_id && data.data.action === 'progress') {
        this._patchCardProgress(data.data.ticket_id, data.data.message, new Date().toISOString());
      }
    });
  },

  // ── 19초 전체 보드 리프레시 ──
  _boardRefreshTimer: null,

  _startBoardRefreshTimer() {
    if (this._boardRefreshTimer) clearInterval(this._boardRefreshTimer);
    const self = this;
    this._boardRefreshTimer = setInterval(function() {
      if (!self._isDragging) self._refreshBoard();
    }, 19000);
  },

  _stopBoardRefreshTimer() {
    if (this._boardRefreshTimer) { clearInterval(this._boardRefreshTimer); this._boardRefreshTimer = null; }
  },

  // ── 2초 진행상황 폴러 ──
  _progressPoller: null,
  _progressPollActive: false,

  _startProgressPoller() {
    this._stopProgressPoller();
    this._progressPollActive = true;
    const self = this;
    async function poll() {
      if (!self._progressPollActive || !self._teamId) return;
      try {
        const res = await API.get('/api/teams/' + self._teamId + '/inprogress');
        if (res.ok && res.tickets) {
          res.tickets.forEach(function(t) {
            self._patchCardProgress(t.ticket_id, t.progress_note, t.last_ping_at, t.process_alive);
          });
        }
      } catch(e) {}
      if (self._progressPollActive) {
        self._progressPoller = setTimeout(poll, 2000);
      }
    }
    this._progressPoller = setTimeout(poll, 2000);
  },

  _stopProgressPoller() {
    this._progressPollActive = false;
    if (this._progressPoller) { clearTimeout(this._progressPoller); this._progressPoller = null; }
  },

  _patchCardProgress(ticketId, note, lastPingAt, alive) {
    const el = document.getElementById('prog-' + ticketId);
    if (!el) return;
    const pingAge = lastPingAt ? Math.floor((Date.now() - new Date(lastPingAt).getTime()) / 1000) : null;
    const pingRecent = pingAge !== null && pingAge < 30;
    const dotHtml = pingRecent ? '<span class="kb-live-dot"></span>' : '';
    const textHtml = '<span class="kb-progress-text">' + Utils.esc((note || '진행 중...').substring(0, 80)) + '</span>';
    el.innerHTML = dotHtml + textHtml;
    // 카드 테두리 펄스
    const card = el.closest('.kb-card');
    if (card && pingRecent) {
      card.classList.add('kb-card-live');
      clearTimeout(card._livePulseTimer);
      card._livePulseTimer = setTimeout(function() { card.classList.remove('kb-card-live'); }, 2500);
    }
  }
};
