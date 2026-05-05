/* U2DIA 재설계 — Home 뷰 (2026-04-17) */
const HomeView = {
  _feedItems: [],
  _sseBound: false,

  async renderList(listEl) {
    /* 홈 섹션에서는 좌측 목록을 접는다 (중복 제거 — 섹션 레일로 이미 이동 가능) */
    listEl.innerHTML =
      '<div class="shell-list__header"><span class="shell-list__title">\ub300\uc2dc\ubcf4\ub4dc</span></div>' +
      '<div class="shell-list__body">' +
      '<div class="u-list-item u-list-item--active"><span>\uc804\uccb4 \ud604\ud669</span></div>' +
      '</div>';
  },

  async render(mainEl) {
    mainEl.innerHTML =
      '<div class="shell-main__content home-row">' +
      '  <div id="homeWelcome" class="home-welcome"></div>' +
      '  <div id="homeTopRow" class="home-grid-top">' +
      '    <div id="homeYudiCard" class="u-panel"></div>' +
      '    <div id="homeKpiCard" class="u-panel"></div>' +
      '  </div>' +
      '  <div id="homeTeamsCard" class="u-panel"></div>' +
      '  <div id="homeLowerRow" class="home-grid-bottom">' +
      '    <div id="homeFeedCard" class="u-panel"></div>' +
      '    <div id="homeHeatmapCard" class="u-panel"></div>' +
      '  </div>' +
      '</div>';
    await this.refresh();
    this._bindSse();
  },

  async refresh() {
    this._renderWelcome();
    await Promise.all([
      this._renderYudi(),
      this._renderKpi(),
      this._renderTeams(),
      this._renderHeatmap()
    ]);
    this._renderFeed();
  },

  _renderWelcome() {
    const el = document.getElementById('homeWelcome');
    if (!el) return;
    const hour = new Date().getHours();
    const greet = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
    el.innerHTML =
      '<h1>' + Utils.esc(greet) + '</h1>' +
      '<span class="home-welcome__date">' + new Date().toISOString().slice(0,10) + '</span>';
  },

  async _renderYudi() {
    const el = document.getElementById('homeYudiCard');
    if (!el) return;
    let status = { running: false, backend: '', ollama_model: '', active_sessions: 0 };
    try {
      const res = await API.get('/api/agent/status');
      if (res) status = Object.assign(status, res);
    } catch(e) {}
    const running = !!status.running;
    const modelLabel = status.ollama_model || status.backend || 'anthropic';
    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\uc720\ub514</h2>' +
      '  <span class="u-badge' + (running ? ' u-badge--success' : '') + '">' + (running ? '\uc0c1\uc8fc' : '\ub300\uae30') + '</span>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-yudi__status">' +
      '    <span class="home-yudi__status-dot' + (running ? ' home-yudi__status-dot--active' : '') + '"></span>' +
      '    <span>' + Utils.esc(modelLabel) + '</span>' +
      '    <span class="home-yudi__meta"> \u00b7 \ud65c\uc131 \uc138\uc158 ' + (status.active_sessions || 0) + '</span>' +
      '  </div>' +
      '  <div class="home-yudi__msg">' +
         (status.last_message ? Utils.esc(status.last_message) : '\uba54\uc2dc\uc9c0 \uc5c6\uc74c') +
      '  </div>' +
      '  <div class="u-toolbar" style="margin-top:var(--space-3)">' +
      '    <button class="u-btn u-btn--sm u-btn--primary" onclick="HomeView._askYudi()">\uc9c8\ubb38\ud558\uae30</button>' +
      '    <button class="u-btn u-btn--sm" onclick="HomeView._yudiLog()">\ub85c\uadf8</button>' +
         (running ? '<button class="u-btn u-btn--sm u-btn--danger" onclick="HomeView._stopYudi()">\uc911\ub2e8</button>' : '') +
      '  </div>' +
      '</div>';
  },

  async _renderKpi() {
    const el = document.getElementById('homeKpiCard');
    if (!el) return;
    let s = {}, agentKpi = {};
    try {
      const res = await API.globalStats();
      s = (res && res.stats) || {};
    } catch(e) {}
    try {
      const r2 = await fetch('/api/agents/global/kpi').then(r => r.json());
      if (r2 && r2.ok) agentKpi = r2;
    } catch(e) {}
    const total = s.total_tickets || 0;
    const done = s.done_tickets || 0;
    const blocked = s.blocked_tickets || 0;
    const working = s.working_agents || 0;
    const remaining = Math.max(0, total - done - blocked);
    const dist = agentKpi.grade_distribution || {};
    const top = (agentKpi.top_agents || []).slice(0, 3);
    const gradeLine = ['S','A','B','C'].map(g => {
      const n = dist[g] || 0;
      const cls = g === 'S' ? 'home-grade--s' : g === 'A' ? 'home-grade--a' : g === 'B' ? 'home-grade--b' : 'home-grade--c';
      return '<span class="home-grade ' + cls + '">' + g + ' ' + n + '</span>';
    }).join('');
    const topLine = top.length
      ? top.map(t => {
          const done = t.completed_tickets || 0;
          const qa = Number(t.avg_qa_score || 0);
          const rework = t.rework_count || 0;
          const reworkRate = done > 0 ? rework / Math.max(done,1) : 0;
          const flags = [];
          if (qa > 0 && qa < 3.5)            flags.push('<span class="home-flag home-flag--qa" title="\uc800\ud488\uc9c8">QA</span>');
          if (reworkRate > 0.3)              flags.push('<span class="home-flag home-flag--rework" title="\uc7ac\uc791\uc5c5 \ub2e4\ubc1c">REWORK</span>');
          if ((t.progress_note_count || 0) === 0 && done > 0) flags.push('<span class="home-flag home-flag--noprogress" title="\ubcf4\uace0 \uc5c6\uc74c">NO-NOTE</span>');
          const cls = flags.length ? ' home-top-agent--danger' : '';
          return '<div class="home-top-agent' + cls + '">'
              + '<span class="home-top-agent__grade">' + (t.grade || '-') + '</span>'
              + '<span class="home-top-agent__name">' + Utils.esc(t.display_name || t.member_id) + '</span>'
              + '<span class="home-top-agent__meta">done ' + done + ' \u00b7 QA ' + qa.toFixed(1) + '</span>'
              + (flags.length ? '<span class="home-top-agent__flags">' + flags.join('') + '</span>' : '')
              + '</div>';
        }).join('')
      : '<div class="home-top-agent home-top-agent--empty">KPI \uc9d1\uacc4 \ub300\uae30 \uc911</div>';
    el.innerHTML =
      '<div class="u-panel__header"><h2 class="u-panel__title">\uc624\ub298\uc758 \uc694\uc57d</h2></div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-kpi-grid">' +
      '    <div class="home-kpi"><div class="home-kpi-label">\uc644\ub8cc \ud2f0\ucf13</div><div class="home-kpi-value">' + done + '</div></div>' +
      '    <div class="home-kpi"><div class="home-kpi-label">\uc9c4\ud589 \uc911</div><div class="home-kpi-value">' + remaining + '</div></div>' +
      '    <div class="home-kpi"><div class="home-kpi-label">\ud65c\uc131 \uc5d0\uc774\uc804\ud2b8</div><div class="home-kpi-value home-kpi-value--info">' + working + '</div></div>' +
      '    <div class="home-kpi"><div class="home-kpi-label">Blocked</div><div class="home-kpi-value home-kpi-value--danger">' + blocked + '</div></div>' +
      '  </div>' +
      '  <div class="home-kpi__meta">\uc804\uccb4 \uc9c4\ud589\ub960 ' + Number(s.global_progress || 0).toFixed(1) + '% \u00b7 \uc544\uce74\uc774\ube0c ' + (s.archived_teams || 0) + '</div>' +
      '  <div class="home-grade-row">\uc5d0\uc774\uc804\ud2b8 \ub4f1\uae09 ' + gradeLine + '</div>' +
      '  <div class="home-top-agents"><div class="home-top-agents__title">Top 3</div>' + topLine + '</div>' +
      '</div>';
  },

  async _renderTeams() {
    const el = document.getElementById('homeTeamsCard');
    if (!el) return;
    let teams = [];
    try {
      const res = await API.overview();
      teams = (res.teams || []).slice(0, 10);
    } catch(e) {}
    const cards = teams.length
      ? teams.map(t => {
          const team = t.team || t;
          const total = t.total_tickets || team.total_tickets || 0;
          const done = t.done_tickets || team.done_tickets || 0;
          const pct = total > 0 ? Math.round(done/total*100) : 0;
          return '<div class="u-card u-card--interactive home-team-card" onclick="Router.navigate(\'#/board/' + Utils.esc(team.team_id) + '\')">' +
            '<div class="home-team-card__name">' + Utils.esc(team.name || team.team_id) + '</div>' +
            '<div class="home-team-card__meta">' + done + '/' + total + ' \u00b7 ' + pct + '%</div>' +
            '<div class="home-team-card__bar"><div class="home-team-card__bar-fill" style="width:' + pct + '%"></div></div>' +
            '</div>';
        }).join('')
      : '<div class="u-empty"><div class="u-empty__title">\ud300 \uc5c6\uc74c</div></div>';
    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\uc9c4\ud589 \uc911\uc778 \ud300</h2>' +
      '  <button class="u-btn u-btn--sm u-btn--ghost" onclick="Router.navigate(\'#/teams\')">\ubaa8\ub450 \ubcf4\uae30</button>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-teams-scroll">' + cards + '</div>' +
      '</div>';
  },

  _renderFeed() {
    const el = document.getElementById('homeFeedCard');
    if (!el) return;
    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">Live Feed</h2>' +
      '  <span class="u-badge" id="homeFeedCount">' + this._feedItems.length + '</span>' +
      '</div>' +
      '<div class="u-panel__body home-feed__body" id="homeFeedBody"></div>';
    this._renderFeedBody();
  },

  _renderFeedBody() {
    const body = document.getElementById('homeFeedBody');
    const count = document.getElementById('homeFeedCount');
    if (!body) return;
    if (count) count.textContent = this._feedItems.length;
    if (!this._feedItems.length) {
      body.innerHTML = '<div class="u-empty"><div class="u-empty__desc">\uc774\ubca4\ud2b8 \ub300\uae30 \uc911\u2026</div></div>';
      return;
    }
    const iconMap = {
      ticket_created: 'plus', ticket_status_changed: 'activity', ticket_claimed: 'zap',
      member_spawned: 'bot', team_created: 'layers', team_archived: 'archives', feedback_created: 'check'
    };
    const colorMap = {
      ticket_created: 'var(--info-fg)', ticket_status_changed: 'var(--brand-light)',
      ticket_claimed: 'var(--warning-fg)', member_spawned: 'var(--text-secondary)',
      team_created: 'var(--success-fg)', team_archived: 'var(--text-muted-new)',
      feedback_created: 'var(--success-fg)'
    };
    body.innerHTML = this._feedItems.slice(0, 30).map(it => {
      const t = new Date(it.at).toTimeString().slice(0,5);
      const iconName = iconMap[it.type] || 'info';
      const color = colorMap[it.type] || 'var(--text-muted-new)';
      const title = it.payload.title || it.payload.ticket_title || it.payload.name || it.type;
      const team = it.team ? '<span class="home-feed__team">\u00b7 ' + Utils.esc(it.team) + '</span>' : '';
      return '<div class="home-feed__row">' +
        '<span class="home-feed__time">' + t + '</span>' +
        '<span class="home-feed__icon" style="color:' + color + '">' + Utils.icon(iconName, 14, 2) + '</span>' +
        '<span class="home-feed__title">' + Utils.esc(title) + '</span>' + team +
      '</div>';
    }).join('');
  },

  _bindSse() {
    if (this._sseBound) return;
    if (typeof SSE === 'undefined' || !SSE.connectGlobal) return;
    this._sseBound = true;
    SSE.connectGlobal((data) => {
      this._feedItems.unshift({
        type: data.event_type || data.type || 'event',
        team: data.team_name || '',
        payload: data.data || {},
        at: Date.now()
      });
      if (this._feedItems.length > 50) this._feedItems.pop();
      this._renderFeedBody();
      if (typeof Header !== 'undefined') Header.setSseStatus(true);
    });
  },

  async _renderHeatmap() {
    const el = document.getElementById('homeHeatmapCard');
    if (!el) return;
    el.innerHTML =
      '<div class="u-panel__header"><h2 class="u-panel__title">Activity 48h</h2></div>' +
      '<div class="u-panel__body home-heatmap__body" id="homeHeatmapBody"></div>';
    const body = document.getElementById('homeHeatmapBody');
    try {
      const res = await API.heatmap10min();
      const buckets = (res && res.data) || [];
      if (!buckets.length) {
        body.innerHTML = '<div class="u-empty"><div class="u-empty__desc">\ub370\uc774\ud130 \uc5c6\uc74c</div></div>';
        return;
      }
      const max = Math.max(1, ...buckets.map(b => (typeof b === 'number' ? b : (b.count || b.value || 0))));
      const html = buckets.slice(-288).map(b => {
        const count = typeof b === 'number' ? b : (b.count || b.value || 0);
        const ts = typeof b === 'object' ? (b.ts || b.time || '') : '';
        const intensity = Math.min(1, count / max);
        return '<div class="home-heatmap__cell" style="--heat:' + intensity.toFixed(2) + '" title="' + Utils.esc(String(ts)) + ' \u00b7 ' + count + '"></div>';
      }).join('');
      body.innerHTML = '<div class="home-heatmap__grid">' + html + '</div>';
    } catch(e) {
      body.innerHTML = '<div class="u-empty"><div class="u-empty__desc">\ub85c\ub529 \uc2e4\ud328</div></div>';
    }
  },

  async _askYudi() {
    const q = prompt('\uc720\ub514\uc5d0\uac8c \uc9c8\ubb38:');
    if (!q) return;
    try {
      const res = await API.post('/api/agent/chat', { message: q });
      alert(res.response || res.answer || res.message || (res.error ? ('\uc624\ub958: ' + res.error) : '\uc751\ub2f5 \uc5c6\uc74c'));
    } catch(e) { alert('\uc694\uccad \uc2e4\ud328: ' + e.message); }
  },

  async _yudiLog() {
    try {
      const res = await API.residentHistory(50, 'all');
      const items = (res && res.history) || [];
      const body = items.length
        ? items.map(h => '<div class="home-feed__row"><span class="home-feed__time">' + Utils.dateFmt(h.created_at || h.timestamp) + '</span><span class="home-feed__icon" style="color:var(--info-fg)">' + Utils.icon('info', 14, 2) + '</span><span class="home-feed__title">' + Utils.esc((h.message || h.content || h.type || '').slice(0, 120)) + '</span></div>').join('')
        : '<div class="u-empty"><div class="u-empty__desc">\uc720\ub514 \ub85c\uadf8 \uc5c6\uc74c</div></div>';
      const html = '<div style="max-height:60vh;overflow-y:auto">' + body + '</div>';
      const win = window.open('', '_blank', 'width=720,height=600');
      if (win) {
        win.document.title = '\uc720\ub514 \ub85c\uadf8';
        win.document.body.innerHTML = '<style>body{background:#16181D;color:#ECEDEE;font-family:Inter,sans-serif;padding:16px;margin:0}.home-feed__row{display:grid;grid-template-columns:36px 16px 1fr;gap:8px;align-items:center;padding:6px 0;border-bottom:1px solid rgba(255,255,255,0.05);font-size:13px}.home-feed__time{color:#5E6C84;font-family:monospace;font-size:11px}.u-empty{text-align:center;padding:40px;color:#5E6C84}</style>' + html;
      }
    } catch(e) { alert('\ub85c\uadf8 \ub85c\ub529 \uc2e4\ud328: ' + e.message); }
  },

  async _stopYudi() {
    if (!confirm('\uc720\ub514\ub97c \uc911\ub2e8\ud558\uc2dc\uaca0\uc2b5\ub2c8\uae4c?')) return;
    try { await API.post('/api/agent/stop'); this.refresh(); }
    catch(e) { alert('\uc2e4\ud328: ' + e.message); }
  }
};

if (typeof App !== 'undefined') App.registerView('home', HomeView);
