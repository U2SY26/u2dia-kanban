/* U2DIA AI SERVER AGENT — Competitions Monitor */
const Competitions = {
  _data: null,
  _sseRemover: null,

  _startSSE(el, mode, name) {
    var self = this;
    var timer = null;
    if (this._sseRemover) { this._sseRemover(); this._sseRemover = null; }
    this._sseRemover = SSE.onGlobalEvent(function(data) {
      var evt = data.event_type || data.type || '';
      if (evt !== 'competition_updated') return;
      if (timer) clearTimeout(timer);
      timer = setTimeout(function() {
        if (mode === 'list') self.render(el);
        else self.renderDetail(el, name);
      }, 1000);
    });
  },

  async render(el) {
    el.innerHTML = '<div class="dash-layout"><div class="loading">Loading competitions...</div></div>';
    const res = await API.fetch('/api/competitions/summary');
    if (!res.ok) { el.innerHTML = '<div class="empty-state">대회 데이터 로드 실패</div>'; return; }
    this._data = res.competitions;

    const cards = res.competitions.map(c => {
      const dist = c.event_distribution || {};
      const commits = dist.git_commit || 0;
      const reviews = c.review_count || 0;
      const avg = c.avg_score != null ? c.avg_score.toFixed(1) : '-';
      const latest = c.latest_event;
      const latestTime = latest ? Utils.timeAgo(latest.created_at) : '-';
      const latestTitle = latest ? Utils.esc(latest.title || '').slice(0, 60) : '';
      const slug = encodeURIComponent(c.competition);
      const total = c.total_events || 0;

      // 색상 판정
      const scoreColor = c.avg_score >= 4 ? 'var(--green)' : c.avg_score >= 3 ? 'var(--yellow)' : 'var(--red)';

      // 확장 메타데이터
      const title = c.title || c.competition;
      const deadline = c.deadline || '';
      const track = c.track || '';
      const prizeUsd = c.prize_usd;
      const writeupUrl = c.writeup_url || '';
      const writeupTitle = c.writeup_title || '';
      const kaggleUrl = c.kaggle_url || '';
      const submissionStatus = c.submission_status || 'in_progress';
      const statusLabel = submissionStatus === 'writeup_posted' ? 'WRITEUP POSTED'
                       : submissionStatus === 'submitted' ? 'SUBMITTED'
                       : 'IN PROGRESS';
      const statusColor = submissionStatus === 'writeup_posted' || submissionStatus === 'submitted'
                        ? 'var(--green)' : 'var(--yellow)';

      // D-day 계산
      let dDay = '';
      if (deadline) {
        try {
          const dl = new Date(deadline + 'T23:59:59Z');
          const now = new Date();
          const diffDays = Math.ceil((dl - now) / (1000 * 60 * 60 * 24));
          if (diffDays > 0) dDay = `D-${diffDays}`;
          else if (diffDays === 0) dDay = 'D-DAY';
          else dDay = `D+${Math.abs(diffDays)}`;
        } catch (e) { /* ignore */ }
      }
      const dDayColor = dDay.startsWith('D-')
        ? (parseInt(dDay.slice(2)) <= 7 ? 'var(--red)' : parseInt(dDay.slice(2)) <= 30 ? 'var(--yellow)' : 'var(--text-muted)')
        : dDay === 'D-DAY' ? 'var(--red)' : 'var(--text-muted)';

      return `
        <div class="card" style="cursor:pointer;transition:all .15s;border-left:3px solid ${scoreColor}"
             onclick="Router.navigate('#/competitions/${slug}')"
             onmouseenter="this.style.background='var(--card-hover)'" onmouseleave="this.style.background=''">
          <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px">
            <div style="flex:1;min-width:0">
              <div style="display:flex;gap:8px;align-items:center;margin-bottom:4px;flex-wrap:wrap">
                <span style="font-size:var(--fs-lg);font-weight:700">${Utils.esc(title)}</span>
                <span style="font-size:10px;background:${statusColor};color:#000;padding:2px 6px;border-radius:4px;font-weight:700">${statusLabel}</span>
                ${dDay ? `<span style="font-size:10px;background:${dDayColor};color:#000;padding:2px 6px;border-radius:4px;font-weight:700;font-family:monospace">${dDay}</span>` : ''}
              </div>
              <div style="font-size:var(--fs-xs);color:var(--text-muted);margin-bottom:8px">
                ${Utils.esc(c.project_group)}${deadline ? ` · 마감 ${Utils.esc(deadline)}` : ''}${track ? ` · ${Utils.esc(track)}` : ''}${prizeUsd ? ` · $${prizeUsd.toLocaleString()}` : ''}
              </div>
              <div style="display:flex;gap:16px;flex-wrap:wrap">
                <span style="font-size:var(--fs-sm)"><span style="color:var(--text-muted)">이벤트</span> <b>${total}</b></span>
                <span style="font-size:var(--fs-sm)"><span style="color:var(--text-muted)">커밋</span> <b style="color:var(--blue)">${commits}</b></span>
                <span style="font-size:var(--fs-sm)"><span style="color:var(--text-muted)">검수</span> <b>${reviews}</b></span>
                <span style="font-size:var(--fs-sm)"><span style="color:var(--text-muted)">평균</span> <b style="color:${scoreColor}">${avg}</b></span>
              </div>
            </div>
            <div style="text-align:right;flex-shrink:0">
              <div style="font-size:28px;font-weight:800;color:${scoreColor};font-family:monospace;line-height:1">${avg}</div>
              <div style="font-size:var(--fs-xs);color:var(--text-muted);margin-top:2px">avg score</div>
            </div>
          </div>
          ${(writeupUrl || kaggleUrl) ? `
          <div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap" onclick="event.stopPropagation()">
            ${writeupUrl ? `<a href="${Utils.esc(writeupUrl)}" target="_blank" rel="noopener" style="font-size:var(--fs-xs);padding:3px 8px;background:var(--purple, #a371f7);color:#000;border-radius:4px;text-decoration:none;font-weight:700">Writeup${writeupTitle ? ': ' + Utils.esc(writeupTitle).slice(0, 50) : ''}</a>` : ''}
            ${kaggleUrl ? `<a href="${Utils.esc(kaggleUrl)}" target="_blank" rel="noopener" style="font-size:var(--fs-xs);padding:3px 8px;background:var(--blue);color:#000;border-radius:4px;text-decoration:none;font-weight:700">Kaggle</a>` : ''}
          </div>` : ''}
          <div style="margin-top:10px;padding-top:8px;border-top:1px solid var(--border)">
            <div style="font-size:var(--fs-xs);color:var(--text-muted);display:flex;gap:8px;align-items:center">
              <span>최근: ${latestTime}</span>
              <span style="color:var(--text-secondary);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${latestTitle}</span>
            </div>
          </div>
          ${this._miniBar(dist, total)}
        </div>`;
    }).join('');

    el.innerHTML = `
      <div class="dash-layout">
        <div class="dash-header-row">
          <h2 style="font-size:var(--fs-xl);font-weight:700">Competitions</h2>
          <a href="#/" class="btn btn-sm">Dashboard</a>
        </div>
        <div style="display:flex;flex-direction:column;gap:12px">${cards}</div>
      </div>`;
    this._startSSE(el, 'list');
  },

  _miniBar(dist, total) {
    if (!total) return '';
    const types = [
      ['status_changed', 'var(--blue)', 'Status'],
      ['ticket_created', 'var(--green)', 'Create'],
      ['artifact_created', 'var(--purple, #a371f7)', 'Artifact'],
      ['supervisor_review', 'var(--yellow)', 'Review'],
      ['git_commit', 'var(--cyan, #79c0ff)', 'Commit'],
    ];
    const bars = types.map(([k, color, label]) => {
      const pct = ((dist[k] || 0) / total * 100);
      return pct > 0 ? `<div style="width:${pct}%;background:${color};height:4px;border-radius:2px" title="${label}: ${dist[k]}"></div>` : '';
    }).join('');
    return `<div style="display:flex;gap:1px;margin-top:8px;border-radius:2px;overflow:hidden">${bars}</div>`;
  },

  async renderDetail(el, name) {
    el.innerHTML = '<div class="dash-layout"><div class="loading">Loading...</div></div>';

    const [histRes, summRes] = await Promise.all([
      API.fetch(`/api/competitions/history?competition=${encodeURIComponent(name)}&limit=200`),
      API.fetch('/api/competitions/summary'),
    ]);

    const comp = (summRes.competitions || []).find(c => c.competition === name) || {};
    const events = histRes.events || [];
    const dist = comp.event_distribution || {};
    const avg = comp.avg_score != null ? comp.avg_score.toFixed(1) : '-';

    // 이벤트 타입별 아이콘/색상
    const typeMap = {
      status_changed: ['', 'var(--blue)'],
      ticket_created: ['', 'var(--green)'],
      ticket_claimed: ['', 'var(--yellow)'],
      artifact_created: ['', 'var(--purple, #a371f7)'],
      supervisor_review: ['', 'var(--yellow)'],
      git_commit: ['', 'var(--cyan, #79c0ff)'],
      progress_updated: ['', 'var(--text-muted)'],
    };

    // 통계 카드
    const statCards = [
      { label: 'Total Events', value: comp.total_events || 0, color: 'var(--text-primary)' },
      { label: 'Reviews', value: comp.review_count || 0, color: 'var(--yellow)' },
      { label: 'Avg Score', value: avg, color: comp.avg_score >= 4 ? 'var(--green)' : comp.avg_score >= 3 ? 'var(--yellow)' : 'var(--red)' },
      { label: 'Commits', value: dist.git_commit || 0, color: 'var(--cyan, #79c0ff)' },
      { label: 'Artifacts', value: dist.artifact_created || 0, color: 'var(--purple, #a371f7)' },
      { label: 'Tickets', value: dist.ticket_created || 0, color: 'var(--green)' },
    ].map(s => `
      <div class="bi-kpi-card" style="--kpi-color:${s.color}">
        <div class="bi-kpi-label">${s.label}</div>
        <div class="bi-kpi-value">${s.value}</div>
      </div>
    `).join('');

    // 이벤트 리스트
    const rows = events.map(e => {
      const [icon, color] = typeMap[e.event_type] || ['', 'var(--text-muted)'];
      const time = Utils.timeAgo(e.created_at);
      const title = Utils.esc(e.title || '').slice(0, 100);
      const scoreTag = e.score != null ? `<span style="background:${e.score >= 4 ? 'var(--green)' : e.score >= 3 ? 'var(--yellow)' : 'var(--red)'};color:#000;padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700">${e.score}</span>` : '';
      return `
        <div style="display:flex;align-items:flex-start;gap:8px;padding:6px 0;border-bottom:1px solid rgba(48,54,61,0.3)">
          <span style="flex-shrink:0;font-size:13px">${icon}</span>
          <div style="flex:1;min-width:0">
            <div style="font-size:var(--fs-sm);color:var(--text-primary);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${title} ${scoreTag}</div>
            <div style="font-size:var(--fs-xs);color:var(--text-muted)">${e.event_type}</div>
          </div>
          <span style="font-size:var(--fs-xs);color:var(--text-muted);flex-shrink:0;font-family:monospace">${time}</span>
        </div>`;
    }).join('');

    // 메타데이터 링크 (writeup, kaggle)
    const writeupUrl = comp.writeup_url || '';
    const kaggleUrl = comp.kaggle_url || '';
    const deadline = comp.deadline || '';
    const track = comp.track || '';
    const submissionStatus = comp.submission_status || 'in_progress';

    let dDay = '';
    if (deadline) {
      try {
        const dl = new Date(deadline + 'T23:59:59Z');
        const diffDays = Math.ceil((dl - new Date()) / (1000 * 60 * 60 * 24));
        if (diffDays > 0) dDay = `D-${diffDays}`;
        else if (diffDays === 0) dDay = 'D-DAY';
        else dDay = `D+${Math.abs(diffDays)}`;
      } catch (e) { /* ignore */ }
    }

    const metaBar = (writeupUrl || kaggleUrl || deadline) ? `
      <div class="competition-meta-bar">
        <div class="competition-meta-line">
          ${submissionStatus === 'writeup_posted' ? '<span class="competition-chip competition-chip--success">WRITEUP POSTED</span>' : ''}
          ${dDay ? `<span class="competition-chip competition-chip--warn">${dDay}</span>` : ''}
          ${deadline ? `<span class="competition-meta-text">마감 ${Utils.esc(deadline)}</span>` : ''}
          ${track ? `<span class="competition-meta-text">${Utils.esc(track)}</span>` : ''}
        </div>
        <div class="competition-meta-links">
          ${writeupUrl ? `<a href="${Utils.esc(writeupUrl)}" target="_blank" rel="noopener" class="competition-link competition-link--writeup">Writeup</a>` : ''}
          ${kaggleUrl ? `<a href="${Utils.esc(kaggleUrl)}" target="_blank" rel="noopener" class="competition-link competition-link--kaggle">Kaggle</a>` : ''}
        </div>
      </div>` : '';

    el.innerHTML = `
      <div class="enterprise-page">
        <div class="enterprise-header">
          <div class="enterprise-heading">
            <h2 class="enterprise-title">${Utils.esc(comp.title || name)}</h2>
            <div class="enterprise-subtitle">${Utils.esc(comp.project_group || '')}</div>
          </div>
          <div class="enterprise-actions"><a href="#/competitions" class="btn btn-sm">Back</a></div>
        </div>
        ${metaBar}
        <div class="bi-kpi-grid bi-kpi-grid--six competition-detail-kpis">${statCards}</div>
        <div class="u-panel competition-event-panel">
          <div class="u-panel__header">
            <div class="u-panel__title">Event History (${events.length}/${comp.total_events || 0})</div>
          </div>
          <div class="u-panel__body competition-event-list">
            ${rows || '<div class="empty-state">No events</div>'}
          </div>
        </div>
      </div>`;
    this._startSSE(el, 'detail', name);
  },
};
