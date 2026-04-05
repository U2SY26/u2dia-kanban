/* U2DIA AI SERVER AGENT — Archive Detail View (Git Workflow Style)
 * Security: All user-provided data is sanitized through Utils.esc() before rendering.
 */
const ArchiveDetail = {
  _data: null,
  _memberMap: {},
  _filter: 'all',

  async render(container, teamId) {
    container.textContent = '';
    const loading = document.createElement('div');
    loading.className = 'dash-layout';
    loading.innerHTML = '<div class="empty-state">로딩중...</div>';
    container.appendChild(loading);

    const res = await API.archiveDetail(teamId);
    if (!res.ok) {
      container.textContent = '';
      const err = document.createElement('div');
      err.className = 'dash-layout';
      err.innerHTML = '<div class="empty-state">아카이브를 찾을 수 없습니다</div>';
      container.appendChild(err);
      return;
    }

    this._data = res;
    this._filter = 'all';
    this._memberMap = {};
    (res.members || []).forEach(m => {
      this._memberMap[m.member_id] = m.display_name || m.role || m.member_id;
    });
    this._renderFull(container);
  },

  _memberName(id) {
    return this._memberMap[id] || id || '-';
  },

  _renderFull(container) {
    const d = this._data;
    const team = d.team;
    const tickets = d.tickets || [];
    const members = d.members || [];
    const messages = d.messages || [];
    const artifacts = d.artifacts || [];
    const logs = d.activity_logs || [];
    const feedbacks = d.feedbacks || [];
    const done = tickets.filter(t => t.status === 'Done').length;
    const blocked = tickets.filter(t => t.status === 'Blocked').length;
    const progress = tickets.length > 0 ? Math.round(done / tickets.length * 100) : 0;

    container.textContent = '';
    const wrap = document.createElement('div');
    wrap.className = 'dash-layout';
    wrap.id = 'archiveDetailContent';

    const artStats = d.artifact_stats || {};
    const byType = artStats.by_type || {};
    const totalFiles = artStats.total_files || 0;
    const linesAdded = artStats.total_lines_added || 0;
    const linesRemoved = artStats.total_lines_removed || 0;
    const codeArts = (byType['code'] || 0) + (byType['code_change'] || 0) + (byType['file_path'] || 0);

    const kpiCards = [
      { v: done + '/' + tickets.length, label: '완료', color: '--chart-blue', icon: '&#x2713;' },
      { v: progress + '%', label: '달성률', color: '--chart-green', icon: '&#x25C9;' },
      { v: members.length, label: '에이전트', color: '--chart-cyan', icon: '&#x2726;' },
      { v: blocked, label: 'Blocked', color: '--chart-red', icon: '&#x26A0;' },
      { v: artifacts.length, label: '산출물', color: '--chart-orange', icon: '&#x1F4CE;' },
      { v: codeArts, label: '코드', color: '--brand', icon: '&#x1F4DD;' },
      { v: totalFiles > 0 ? '+' + linesAdded + ' -' + linesRemoved : '-', label: '변경량', color: '--chart-lime', icon: '&#x1F4C4;' },
      { v: messages.length, label: '대화', color: '--chart-purple', icon: '&#x1F4AC;' },
      { v: feedbacks.length, label: '피드백', color: '--yellow', icon: '&#x2605;' },
      { v: logs.length, label: '액티비티', color: '--muted', icon: '&#x25B6;' },
    ];

    wrap.innerHTML = `
      <div class="dash-header-row">
        <div>
          <h2 style="font-size:var(--fs-xl);font-weight:800;letter-spacing:-0.5px">${Utils.esc(team.name)}</h2>
          <div style="font-size:var(--fs-sm);color:var(--muted);margin-top:4px">
            ${Utils.esc(team.description || '')}
            <span class="archive-badge">Archived</span>
          </div>
        </div>
        <div class="flex gap-8 items-center">
          <a href="#/archives" class="btn btn-sm">목록으로</a>
        </div>
      </div>

      <div class="archive-kpi-row">
        ${kpiCards.map(c => `
          <div class="archive-kpi-card" style="--kpi-color:var(${c.color})">
            <span class="archive-kpi-icon">${c.icon}</span>
            <span class="archive-kpi-val">${c.v}</span>
            <span class="archive-kpi-lbl">${c.label}</span>
          </div>`).join('')}
      </div>

      <div class="archive-filter-bar">
        <span class="archive-filter-label">필터:</span>
        <button class="archive-filter-btn active" data-f="all" onclick="ArchiveDetail.setFilter('all')">전체</button>
        <button class="archive-filter-btn" data-f="ticket" onclick="ArchiveDetail.setFilter('ticket')">티켓</button>
        <button class="archive-filter-btn" data-f="artifact" onclick="ArchiveDetail.setFilter('artifact')">산출물 전체</button>
        <button class="archive-filter-btn" data-f="art_code" onclick="ArchiveDetail.setFilter('art_code')">코드</button>
        <button class="archive-filter-btn" data-f="art_result" onclick="ArchiveDetail.setFilter('art_result')">결과</button>
        <button class="archive-filter-btn" data-f="art_docs" onclick="ArchiveDetail.setFilter('art_docs')">문서</button>
        <button class="archive-filter-btn" data-f="message" onclick="ArchiveDetail.setFilter('message')">대화</button>
        <button class="archive-filter-btn" data-f="feedback" onclick="ArchiveDetail.setFilter('feedback')">피드백</button>
        <button class="archive-filter-btn" data-f="activity" onclick="ArchiveDetail.setFilter('activity')">액티비티</button>
      </div>

      <div id="archiveTimeline"></div>

      <div id="ticketDetailModal" style="display:none;position:fixed;inset:0;z-index:1000;background:rgba(0,0,0,0.6);backdrop-filter:blur(4px);overflow-y:auto" onclick="if(event.target===this)ArchiveDetail.closeTicketModal()">
        <div style="max-width:800px;margin:40px auto;background:var(--card);border:1px solid var(--line);border-radius:var(--radius-lg);overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,0.5)">
          <div id="ticketDetailBody"></div>
        </div>
      </div>
    `;
    container.appendChild(wrap);
    this._renderTimeline();
  },

  setFilter(f) {
    this._filter = f;
    document.querySelectorAll('.archive-filter-btn').forEach(b => {
      b.classList.toggle('active', b.dataset.f === f);
    });
    this._renderTimeline();
  },

  _buildEvents() {
    const d = this._data;
    const events = [];
    const tickets = d.tickets || [];
    const ticketMap = {};
    tickets.forEach(t => { ticketMap[t.ticket_id] = t; });

    // 티켓 이벤트
    tickets.forEach(t => {
      events.push({
        type: 'ticket',
        time: t.created_at,
        icon: '&#x1F3AB;',
        color: 'var(--chart-blue)',
        label: '티켓 생성',
        title: t.title,
        ticketId: t.ticket_id,
        status: t.status,
        priority: t.priority,
        desc: t.description,
        assignee: this._memberName(t.assigned_member_id),
        completedAt: t.completed_at,
      });
      if (t.completed_at && t.status === 'Done') {
        events.push({
          type: 'ticket_done',
          time: t.completed_at,
          icon: '&#x2705;',
          color: 'var(--green)',
          label: '완료',
          title: t.title,
          ticketId: t.ticket_id,
        });
      }
      if (t.status === 'Blocked') {
        events.push({
          type: 'ticket_blocked',
          time: t.completed_at || t.created_at,
          icon: '&#x1F6D1;',
          color: 'var(--red)',
          label: 'Blocked',
          title: t.title,
          ticketId: t.ticket_id,
        });
      }
    });

    // 산출물
    var artTypeIcons = {code:'📄',file_path:'📁',code_change:'🔀',config:'⚙️',test:'🧪',docs:'📝',result:'✅',summary:'📋',log:'📜',diagram:'📊',screenshot:'🖼️',data:'💾'};
    var artTypeColors = {code:'var(--brand)',file_path:'var(--chart-cyan)',code_change:'var(--chart-lime)',result:'var(--chart-green)',summary:'var(--chart-purple)',test:'var(--chart-yellow)',docs:'var(--chart-teal)'};
    (d.artifacts || []).forEach(a => {
      var tk = ticketMap[a.ticket_id];
      var aType = a.artifact_type || 'other';
      var files = a.files || [];
      var filesSummary = '';
      if (files.length > 0) {
        var added = files.reduce(function(s,f){return s+(f.lines_added||0);},0);
        var removed = files.reduce(function(s,f){return s+(f.lines_removed||0);},0);
        filesSummary = ' — ' + files.length + '개 파일 (+' + added + ' -' + removed + ')';
      }
      events.push({
        type: 'artifact',
        sub_type: aType,
        time: a.created_at,
        icon: artTypeIcons[aType] || '📎',
        color: artTypeColors[aType] || 'var(--chart-orange)',
        label: aType,
        title: (a.title || '무제') + filesSummary,
        ticketTitle: tk ? tk.title : a.ticket_id,
        content: a.content,
        artifactType: aType,
        language: a.language,
        creator: this._memberName(a.creator_member_id),
        files: files,
      });
    });

    // 메시지
    (d.messages || []).forEach(m => {
      var tk = ticketMap[m.ticket_id];
      events.push({
        type: 'message',
        time: m.created_at,
        icon: '&#x1F4AC;',
        color: 'var(--chart-purple)',
        label: m.message_type || 'message',
        title: Utils.esc((m.content || '').substring(0, 80)),
        sender: this._memberName(m.sender_member_id),
        content: m.content,
        ticketTitle: tk ? tk.title : (m.ticket_id || ''),
        msgType: m.message_type,
      });
    });

    // 피드백
    (d.feedbacks || []).forEach(f => {
      var tk = ticketMap[f.ticket_id];
      events.push({
        type: 'feedback',
        time: f.created_at,
        icon: '&#x2B50;',
        color: 'var(--yellow)',
        label: '피드백 ' + (f.score || 0) + '/5',
        title: tk ? tk.title : f.ticket_id,
        score: f.score,
        comment: f.comment,
        ticketId: f.ticket_id,
      });
    });

    // 액티비티 로그 (주요만)
    (d.activity_logs || []).forEach(l => {
      events.push({
        type: 'activity',
        time: l.created_at,
        icon: this._actIcon(l.action),
        color: this._actColor(l.action),
        label: l.action,
        title: (l.message || '').substring(0, 120),
        actor: this._memberName(l.member_id),
        ticketId: l.ticket_id,
      });
    });

    // 시간 역순 정렬
    events.sort(function(a, b) {
      return (b.time || '') > (a.time || '') ? 1 : -1;
    });

    // 필터
    var f = this._filter;
    if (f !== 'all') {
      events = events.filter(function(e) {
        if (f === 'ticket') return e.type === 'ticket' || e.type === 'ticket_done' || e.type === 'ticket_blocked';
        if (f === 'artifact') return e.type === 'artifact';
        if (f === 'art_code') return e.type === 'artifact' && ['code','code_change','file_path','config','test'].indexOf(e.sub_type) >= 0;
        if (f === 'art_result') return e.type === 'artifact' && ['result','summary','log','data'].indexOf(e.sub_type) >= 0;
        if (f === 'art_docs') return e.type === 'artifact' && ['docs','diagram','screenshot'].indexOf(e.sub_type) >= 0;
        return e.type === f;
      });
    }

    return events;
  },

  _actIcon(action) {
    var m = {
      team_created: '&#x1F3D7;', ticket_created: '&#x1F3AB;', ticket_status_changed: '&#x1F504;',
      ticket_claimed: '&#x1F916;', member_spawned: '&#x1F47E;', artifact_created: '&#x1F4CE;',
      feedback_created: '&#x2B50;', message_sent: '&#x1F4AC;', progress: '&#x25B6;',
    };
    return m[action] || '&#x25AA;';
  },
  _actColor(action) {
    var m = {
      team_created: 'var(--chart-blue)', ticket_created: 'var(--chart-cyan)', ticket_status_changed: 'var(--chart-orange)',
      ticket_claimed: 'var(--brand)', member_spawned: 'var(--chart-purple)', artifact_created: 'var(--yellow)',
      feedback_created: 'var(--green)', progress: 'var(--chart-lime)',
    };
    return m[action] || 'var(--muted)';
  },

  _renderTimeline() {
    var el = Utils.$('archiveTimeline');
    if (!el) return;

    var events = this._buildEvents();
    if (!events.length) {
      el.innerHTML = '<div class="empty-state">기록 없음</div>';
      return;
    }

    // 날짜별 그룹핑
    var groups = {};
    events.forEach(function(e) {
      var day = (e.time || '').substring(0, 10);
      if (!groups[day]) groups[day] = [];
      groups[day].push(e);
    });

    var self = this;
    var html = '<div class="git-timeline">';

    Object.keys(groups).sort().reverse().forEach(function(day) {
      html += '<div class="git-day-header"><span class="git-day-dot"></span><span class="git-day-label">' + day + '</span></div>';

      groups[day].forEach(function(e, idx) {
        var time = (e.time || '').substring(11, 16);
        var isLast = idx === groups[day].length - 1;

        html += '<div class="git-commit">';
        html += '<div class="git-rail"><div class="git-dot" style="border-color:' + e.color + '"></div>';
        if (!isLast) html += '<div class="git-line"></div>';
        html += '</div>';
        html += '<div class="git-body">';

        // 커밋 헤더
        html += '<div class="git-header">';
        html += '<span class="git-type-badge" style="background:' + e.color + '">' + e.label + '</span>';
        html += '<span class="git-time">' + time + '</span>';
        html += '</div>';

        // 타입별 카드
        if (e.type === 'ticket') {
          html += self._renderTicketCard(e);
        } else if (e.type === 'ticket_done') {
          html += '<div class="git-card git-card-done" onclick="ArchiveDetail.openTicketModal(\'' + Utils.esc(e.ticketId) + '\')">';
          html += '<span class="git-card-title">' + Utils.esc(e.title) + '</span>';
          html += '</div>';
        } else if (e.type === 'ticket_blocked') {
          html += '<div class="git-card git-card-blocked">';
          html += '<span class="git-card-title">' + Utils.esc(e.title) + '</span>';
          html += '</div>';
        } else if (e.type === 'artifact') {
          html += self._renderArtifactCard(e);
        } else if (e.type === 'message') {
          html += self._renderMessageCard(e);
        } else if (e.type === 'feedback') {
          html += self._renderFeedbackCard(e);
        } else if (e.type === 'activity') {
          html += '<div class="git-card git-card-activity">';
          if (e.actor) html += '<span class="git-actor">' + Utils.esc(e.actor) + '</span>';
          html += '<span class="git-card-msg">' + Utils.esc(e.title) + '</span>';
          html += '</div>';
        }

        html += '</div></div>';
      });
    });

    html += '</div>';
    el.innerHTML = html;
  },

  _renderTicketCard(e) {
    var h = '<div class="git-card git-card-ticket" onclick="ArchiveDetail.openTicketModal(\'' + Utils.esc(e.ticketId) + '\')">';
    h += '<div class="git-card-top">';
    h += '<span class="status-badge status-' + Utils.esc(e.status) + '">' + Utils.statusLabel(e.status) + '</span>';
    h += '<span class="pri pri-' + Utils.esc(e.priority) + '">' + Utils.esc(e.priority) + '</span>';
    h += '<span class="git-ticket-id">' + Utils.esc(e.ticketId) + '</span>';
    h += '</div>';
    h += '<div class="git-card-title">' + Utils.esc(e.title) + '</div>';
    if (e.desc) h += '<div class="git-card-desc">' + Utils.esc((e.desc || '').substring(0, 150)) + '</div>';
    h += '<div class="git-card-meta">';
    h += '<span>담당: ' + Utils.esc(e.assignee) + '</span>';
    if (e.completedAt) h += '<span>완료: ' + Utils.dateFmt(e.completedAt) + '</span>';
    h += '</div>';
    h += '</div>';
    return h;
  },

  _renderArtifactCard(e) {
    var h = '<div class="git-card git-card-artifact">';
    h += '<div class="git-card-top">';
    h += '<span class="git-artifact-type" style="background:' + (e.color || 'var(--chart-orange)') + '">' + Utils.esc(e.artifactType || '') + (e.language ? ' · ' + Utils.esc(e.language) : '') + '</span>';
    h += '<span class="git-actor">' + Utils.esc(e.creator) + '</span>';
    h += '</div>';
    h += '<div class="git-card-title">' + Utils.esc(e.title) + '</div>';
    if (e.ticketTitle) h += '<div class="git-card-ref">' + Utils.esc(e.ticketTitle) + '</div>';
    // 파일 변경 상세
    var files = e.files || [];
    if (files.length > 0) {
      h += '<div style="margin:6px 0;border:1px solid var(--border-glass);border-radius:4px;overflow:hidden;font-size:11px">';
      files.forEach(function(f) {
        var added = f.lines_added || 0;
        var removed = f.lines_removed || 0;
        h += '<div style="display:flex;align-items:center;gap:6px;padding:3px 8px;border-bottom:1px solid var(--border-glass)">';
        h += '<span style="font-family:var(--mono);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--chart-cyan)">' + Utils.esc(f.file_path || f.path || '') + '</span>';
        if (added > 0) h += '<span style="color:var(--chart-green);font-family:var(--mono)">+' + added + '</span>';
        if (removed > 0) h += '<span style="color:var(--chart-red);font-family:var(--mono)">-' + removed + '</span>';
        h += '</div>';
      });
      h += '</div>';
    }
    if (e.content) {
      var preview = (e.content || '').substring(0, 300);
      h += '<pre class="git-code-preview">' + Utils.esc(preview) + (e.content.length > 300 ? '\n...' : '') + '</pre>';
    }
    h += '</div>';
    return h;
  },

  _renderMessageCard(e) {
    var h = '<div class="git-card git-card-message">';
    h += '<div class="git-card-top">';
    h += '<span class="git-actor">' + Utils.esc(e.sender) + '</span>';
    if (e.msgType && e.msgType !== 'text') h += '<span class="git-msg-type">' + Utils.esc(e.msgType) + '</span>';
    h += '</div>';
    h += '<div class="git-card-msg">' + Utils.esc((e.content || '').substring(0, 200)) + '</div>';
    if (e.ticketTitle) h += '<div class="git-card-ref">' + Utils.esc(e.ticketTitle) + '</div>';
    h += '</div>';
    return h;
  },

  _renderFeedbackCard(e) {
    var stars = '';
    for (var i = 0; i < 5; i++) {
      stars += '<span style="color:' + (i < (e.score || 0) ? 'var(--yellow)' : 'var(--line)') + '">&#9733;</span>';
    }
    var h = '<div class="git-card git-card-feedback">';
    h += '<div class="git-card-top">';
    h += '<span class="git-stars">' + stars + '</span>';
    h += '</div>';
    h += '<div class="git-card-title">' + Utils.esc(e.title) + '</div>';
    if (e.comment) h += '<div class="git-card-msg">' + Utils.esc(e.comment) + '</div>';
    h += '</div>';
    return h;
  },

  // ── Ticket Detail Modal (기존 유지) ──
  openTicketModal(ticketId) {
    if (window.TicketDetail) return TicketDetail.show(ticketId);

    const d = this._data;
    const tk = (d.tickets || []).find(t => t.ticket_id === ticketId);
    if (!tk) return;

    const messages = (d.messages || []).filter(m => m.ticket_id === ticketId);
    const artifacts = (d.artifacts || []).filter(a => a.ticket_id === ticketId);
    const logs = (d.activity_logs || []).filter(l =>
      l.ticket_id === ticketId ||
      (l.message && l.message.includes(ticketId)) ||
      (l.message && l.message.includes(tk.title))
    );
    const feedbacks = (d.feedbacks || []).filter(f => f.ticket_id === ticketId);
    const assignee = this._memberName(tk.assigned_member_id);

    const body = Utils.$('ticketDetailBody');
    body.innerHTML = `
      <div style="padding:20px 24px;background:var(--bg);border-bottom:1px solid var(--line);display:flex;justify-content:space-between;align-items:flex-start">
        <div style="flex:1;min-width:0">
          <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:8px">
            <span class="status-badge status-${Utils.esc(tk.status)}">${Utils.statusLabel(tk.status)}</span>
            <span class="pri pri-${Utils.esc(tk.priority)}">${Utils.esc(tk.priority)}</span>
            <span style="font-size:var(--fs-xs);color:var(--muted);font-family:monospace">${Utils.esc(ticketId)}</span>
          </div>
          <h3 style="font-size:var(--fs-lg);font-weight:800;margin:0">${Utils.esc(tk.title)}</h3>
          ${tk.description ? `<div style="font-size:var(--fs-sm);color:var(--muted);margin-top:8px;white-space:pre-wrap;line-height:1.6">${Utils.esc(tk.description)}</div>` : ''}
        </div>
        <button onclick="ArchiveDetail.closeTicketModal()" style="background:none;border:none;color:var(--muted);font-size:24px;cursor:pointer;padding:0 0 0 16px;line-height:1">&times;</button>
      </div>
      <div style="padding:12px 24px;border-bottom:1px solid var(--line);display:flex;gap:24px;flex-wrap:wrap;font-size:var(--fs-xs);color:var(--muted)">
        <span>담당: <strong style="color:var(--brand-light)">${Utils.esc(assignee)}</strong></span>
        <span>생성: ${Utils.dateFmt(tk.created_at)}</span>
        ${tk.completed_at ? `<span>완료: ${Utils.dateFmt(tk.completed_at)}</span>` : ''}
      </div>
      <div style="padding:20px 24px;display:flex;flex-direction:column;gap:20px;max-height:60vh;overflow-y:auto">
        ${this._renderModalSection('&#x1F4AC; 대화', 'var(--chart-purple)', messages, this._renderModalMessages.bind(this))}
        ${this._renderModalSection('&#x1F4CE; 산출물', 'var(--chart-orange)', artifacts, this._renderModalArtifacts.bind(this))}
        ${this._renderModalSection('&#x2605; 피드백', 'var(--yellow)', feedbacks, this._renderModalFeedbacks.bind(this))}
        ${this._renderModalSection('&#x25B6; 활동', 'var(--chart-blue)', logs, this._renderModalLogs.bind(this))}
      </div>
    `;
    Utils.$('ticketDetailModal').style.display = 'block';
    document.body.style.overflow = 'hidden';
  },

  _renderModalSection(title, color, items, renderer) {
    if (!items.length) return '';
    return `<div>
      <div style="font-weight:700;font-size:var(--fs-sm);margin-bottom:8px;color:${color}">${title} (${items.length})</div>
      ${renderer(items)}
    </div>`;
  },

  _renderModalMessages(messages) {
    return `<div style="background:var(--bg);border:1px solid var(--line);border-radius:var(--radius-md);overflow:hidden">
      ${messages.map(m => `
        <div style="padding:10px 16px;border-bottom:1px solid var(--line)">
          <div style="display:flex;justify-content:space-between;margin-bottom:4px">
            <span style="font-weight:600;font-size:var(--fs-sm);color:var(--brand-light)">${Utils.esc(this._memberName(m.sender_member_id))}</span>
            <span style="font-size:var(--fs-xs);color:var(--muted)">${Utils.dateFmt(m.created_at)}</span>
          </div>
          <div style="font-size:var(--fs-sm);white-space:pre-wrap;line-height:1.6">${Utils.esc(m.content || '')}</div>
        </div>`).join('')}
    </div>`;
  },

  _renderModalArtifacts(artifacts) {
    return artifacts.map(a => `
      <div style="background:var(--bg);border:1px solid var(--line);border-radius:var(--radius-md);padding:12px 16px;margin-bottom:8px">
        <div style="font-weight:700;font-size:var(--fs-sm);margin-bottom:4px">${Utils.esc(a.title || '무제')}</div>
        <div style="font-size:var(--fs-xs);color:var(--muted);margin-bottom:6px">${Utils.esc(a.artifact_type || '')} ${a.language ? '(' + Utils.esc(a.language) + ')' : ''} | ${Utils.esc(this._memberName(a.creator_member_id))} | ${Utils.dateFmt(a.created_at)}</div>
        ${a.content ? `<pre style="background:var(--card);padding:10px;border-radius:var(--radius-sm);font-size:var(--fs-xs);max-height:300px;overflow:auto;white-space:pre-wrap;word-break:break-all;border:1px solid var(--line);margin:0">${Utils.esc(a.content)}</pre>` : ''}
      </div>`).join('');
  },

  _renderModalFeedbacks(feedbacks) {
    return feedbacks.map(f => {
      var stars = '';
      for (var i = 0; i < 5; i++) stars += '<span style="color:' + (i < (f.score||0) ? 'var(--yellow)' : 'var(--line)') + '">&#9733;</span>';
      return `<div style="background:var(--bg);border:1px solid var(--line);border-radius:var(--radius-md);padding:12px 16px;margin-bottom:8px">
        <div style="margin-bottom:6px">${stars}</div>
        ${f.comment ? `<div style="font-size:var(--fs-sm);white-space:pre-wrap">${Utils.esc(f.comment)}</div>` : ''}
        <div style="font-size:var(--fs-xs);color:var(--muted);margin-top:4px">${Utils.dateFmt(f.created_at)}</div>
      </div>`;
    }).join('');
  },

  _renderModalLogs(logs) {
    return `<div style="background:var(--bg);border:1px solid var(--line);border-radius:var(--radius-md);padding:8px 0">
      ${logs.map(l => `
        <div style="padding:6px 16px;display:flex;gap:12px;font-size:var(--fs-xs)">
          <span style="color:var(--muted);white-space:nowrap;min-width:100px">${Utils.dateFmt(l.created_at)}</span>
          <span style="color:var(--brand-light);font-weight:600;min-width:80px">${Utils.esc(this._memberName(l.member_id))}</span>
          <span style="padding:1px 6px;border-radius:3px;background:var(--blue-bg);color:var(--chart-blue);font-weight:600">${Utils.esc(l.action)}</span>
          <span style="color:var(--text-secondary);flex:1">${Utils.esc((l.message || '').substring(0, 200))}</span>
        </div>`).join('')}
    </div>`;
  },

  closeTicketModal() {
    const modal = Utils.$('ticketDetailModal');
    if (modal) modal.style.display = 'none';
    document.body.style.overflow = '';
  },

  _parseTags(tags) {
    if (!tags) return [];
    if (Array.isArray(tags)) return tags;
    try { return JSON.parse(tags); } catch { return []; }
  }
};
