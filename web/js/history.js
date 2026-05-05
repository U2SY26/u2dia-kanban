/* U2DIA AI SERVER AGENT — Enterprise History & Benchmarking */
const TeamHistory = {
  _data: null,
  _benchmarks: null,
  _tab: 'teams',

  async render(container) {
    container.innerHTML = `
      <div class="enterprise-page history-page" id="historyContent">
        <div class="enterprise-header">
          <div class="enterprise-heading">
            <h1 class="enterprise-title">Operations History</h1>
            <div class="enterprise-subtitle">팀 실행 이력, 처리량, 비용, 활동량을 한 화면에서 비교합니다.</div>
          </div>
          <div class="enterprise-actions">
            <a href="#/" class="u-btn u-btn--sm">${Utils.icon('home', 14, 1.75)}대시보드</a>
          </div>
        </div>

        <div class="tabs enterprise-tabs" id="historyTabs">
          <div class="tab active" data-tab="teams" onclick="TeamHistory.switchTab('teams')">팀 히스토리</div>
          <div class="tab" data-tab="benchmark" onclick="TeamHistory.switchTab('benchmark')">벤치마킹</div>
        </div>

        <div id="historyBody"></div>
      </div>`;
    await this.loadTeams();
  },

  switchTab(tab) {
    this._tab = tab;
    document.querySelectorAll('#historyTabs .tab').forEach(t => {
      t.classList.toggle('active', t.dataset.tab === tab);
    });
    if (tab === 'teams') this._renderTeams();
    else this._renderBenchmark();
  },

  async loadTeams() {
    const [teamsRes, benchRes] = await Promise.all([
      API.historyTeams(), API.historyBenchmark()
    ]);
    if (teamsRes.ok) this._data = teamsRes.teams || [];
    if (benchRes.ok) this._benchmarks = benchRes.benchmarks || [];
    this._renderTeams();
  },

  _summary(rows) {
    const s = {
      teams: rows.length,
      active: 0,
      archived: 0,
      tickets: 0,
      done: 0,
      agents: 0,
      logs: 0,
      cost: 0,
      avgProgress: 0
    };
    rows.forEach(d => {
      const t = d.team || d;
      const m = d.metrics || {};
      if (t.status === 'Archived') s.archived += 1;
      else s.active += 1;
      s.tickets += Number(m.total_tickets || 0);
      s.done += Number(m.done_tickets || 0);
      s.agents += Number(m.member_count || 0);
      s.logs += Number(m.total_logs || 0);
      s.cost += Number(m.estimated_cost || 0);
      s.avgProgress += Number(m.progress || 0);
    });
    s.avgProgress = rows.length ? Math.round(s.avgProgress / rows.length) : 0;
    return s;
  },

  _kpi(label, value, sub, color) {
    return `
      <div class="bi-kpi-card" style="--kpi-color:${color}">
        <div class="bi-kpi-label">${Utils.esc(label)}</div>
        <div class="bi-kpi-value">${value}</div>
        <div class="bi-kpi-sub">${Utils.esc(sub || '')}</div>
      </div>`;
  },

  _renderTeams() {
    const el = Utils.$('historyBody');
    if (!el || !this._data) return;

    if (!this._data.length) {
      el.innerHTML = '<div class="u-empty"><div class="u-empty__title">팀 히스토리가 없습니다</div></div>';
      return;
    }

    const s = this._summary(this._data);
    el.innerHTML = `
      <div class="bi-kpi-grid bi-kpi-grid--six">
        ${this._kpi('Teams', s.teams, 'Active ' + s.active + ' / Archived ' + s.archived, 'var(--brand-light)')}
        ${this._kpi('Progress', s.avgProgress + '%', '평균 완료율', 'var(--green)')}
        ${this._kpi('Tickets', s.done + '/' + s.tickets, '완료 / 전체', 'var(--cyan)')}
        ${this._kpi('Agents', Utils.numFmt(s.agents), '누적 멤버', 'var(--purple-light)')}
        ${this._kpi('Activity', Utils.numFmt(s.logs), '운영 로그', 'var(--yellow-light)')}
        ${this._kpi('Cost', Utils.costFmt(s.cost), '추정 비용', 'var(--orange)')}
      </div>

      <div class="history-health-grid">
        <section class="u-panel">
          <div class="u-panel__header">
            <h2 class="u-panel__title">Team Operations Ledger</h2>
            <span class="u-badge">${this._data.length} rows</span>
          </div>
          <div class="bi-table-wrap">
            <table class="bi-table history-table">
              <thead>
                <tr>
                  <th>팀</th>
                  <th>상태</th>
                  <th class="num">진행률</th>
                  <th class="num">티켓</th>
                  <th class="num">에이전트</th>
                  <th class="num">활동</th>
                  <th class="num">비용</th>
                  <th class="num">생성</th>
                </tr>
              </thead>
              <tbody>
                ${this._data.map(d => this._buildTeamRow(d)).join('')}
              </tbody>
            </table>
          </div>
        </section>

        <section class="u-panel">
          <div class="u-panel__header">
            <h2 class="u-panel__title">Portfolio Mix</h2>
            <span class="u-badge u-badge--brand">BI</span>
          </div>
          <div class="u-panel__body history-status-bars">
            ${this._statusBar('Active Teams', s.active, s.teams, 'var(--brand-light)')}
            ${this._statusBar('Archived Teams', s.archived, s.teams, 'var(--green)')}
            ${this._statusBar('Done Tickets', s.done, s.tickets, 'var(--cyan)')}
            ${this._statusBar('Open Tickets', Math.max(0, s.tickets - s.done), s.tickets, 'var(--orange)')}
            ${this._statusBar('Log Density', Math.min(s.logs, Math.max(1, s.teams * 120)), Math.max(1, s.teams * 120), 'var(--purple-light)')}
          </div>
        </section>
      </div>`;
  },

  _statusBar(name, value, total, color) {
    const pct = total ? Math.round(value / total * 100) : 0;
    return `
      <div class="history-status-row">
        <div class="history-status-name">${Utils.esc(name)}</div>
        <div class="bi-progress__bar">
          <div class="bi-progress__fill" style="--pct:${pct}%;--progress-color:${color}"></div>
        </div>
        <div class="history-status-count">${Utils.numFmt(value)}</div>
      </div>`;
  },

  _statusBadge(status) {
    const archived = status === 'Archived';
    return '<span class="u-badge ' + (archived ? 'u-badge--success' : 'u-badge--brand') + '">' + Utils.esc(status || 'Active') + '</span>';
  },

  _buildTeamRow(d) {
    const t = d.team || {};
    const m = d.metrics || {};
    const pct = Math.max(0, Math.min(100, Number(m.progress || 0)));
    const progressColor = pct >= 100 ? 'var(--green)' : pct >= 50 ? 'var(--brand-light)' : pct > 0 ? 'var(--orange)' : 'var(--muted)';
    return `
      <tr class="history-team-row" onclick="Router.navigate('#/history/${Utils.attr(t.team_id)}')">
        <td class="bi-name-cell">
          <div class="bi-title-line">${Utils.esc(t.name || t.team_id || '-')}</div>
          <div class="bi-sub-line">${Utils.esc(t.description || t.project_group || '')}</div>
        </td>
        <td>${this._statusBadge(t.status)}</td>
        <td class="num">
          <div class="bi-progress">
            <div class="bi-progress__bar">
              <div class="bi-progress__fill" style="--pct:${pct}%;--progress-color:${progressColor}"></div>
            </div>
            <div class="bi-progress__label"><span>${pct}%</span><span>${Utils.esc(t.status || '')}</span></div>
          </div>
        </td>
        <td class="num">${Number(m.done_tickets || 0)}/${Number(m.total_tickets || 0)}</td>
        <td class="num">${Number(m.member_count || 0)}</td>
        <td class="num">${Utils.numFmt(m.total_logs || 0)}</td>
        <td class="num" style="color:var(--orange)">${Utils.costFmt(m.estimated_cost || 0)}</td>
        <td class="num">${Utils.dateFmt(t.created_at)}</td>
      </tr>`;
  },

  _renderBenchmark() {
    const el = Utils.$('historyBody');
    if (!el || !this._benchmarks) return;

    if (!this._benchmarks.length) {
      el.innerHTML = '<div class="u-empty"><div class="u-empty__title">벤치마킹 데이터가 없습니다</div></div>';
      return;
    }

    const costs = this._benchmarks.map(b => Number(b.cost_per_ticket || 0)).filter(v => v > 0);
    const best = {
      progress: Math.max(...this._benchmarks.map(b => Number(b.progress || 0))),
      productivity: Math.max(...this._benchmarks.map(b => Number(b.productivity || 0))),
      costEfficiency: costs.length ? Math.min(...costs) : 0
    };

    const leader = this._benchmarks[0] || {};
    el.innerHTML = `
      <div class="bi-kpi-grid">
        ${this._kpi('Leader', Utils.esc((leader.name || '-').slice(0, 24)), '최상위 실행 지표', 'var(--yellow-light)')}
        ${this._kpi('Best Progress', best.progress + '%', '최고 완료율', 'var(--green)')}
        ${this._kpi('Best Productivity', Utils.numFmt(best.productivity), '생산성 최고값', 'var(--cyan)')}
        ${this._kpi('Best Cost/Ticket', Utils.costFmt(best.costEfficiency), '비용 효율', 'var(--orange)')}
      </div>
      <section class="u-panel">
        <div class="u-panel__header">
          <h2 class="u-panel__title">Benchmark Matrix</h2>
          <span class="u-badge">${this._benchmarks.length} teams</span>
        </div>
        <div class="bi-table-wrap">
          <table class="bi-table">
            <thead>
              <tr>
                <th>순위</th>
                <th>팀</th>
                <th class="num">진행률</th>
                <th class="num">티켓</th>
                <th class="num">에이전트</th>
                <th class="num">생산성</th>
                <th class="num">활동시간</th>
                <th class="num">총 비용</th>
                <th class="num">티켓당 비용</th>
                <th class="num">총 토큰</th>
              </tr>
            </thead>
            <tbody>
              ${this._benchmarks.map((b, i) => this._buildBenchRow(b, i, best)).join('')}
            </tbody>
          </table>
        </div>
      </section>`;
  },

  _buildBenchRow(b, idx, best) {
    const progress = Number(b.progress || 0);
    const productivity = Number(b.productivity || 0);
    const costPerTicket = Number(b.cost_per_ticket || 0);
    const isBestProg = progress === best.progress && progress > 0;
    const isBestProd = productivity === best.productivity && productivity > 0;
    const isBestCost = costPerTicket === best.costEfficiency && costPerTicket > 0;
    const statusColor = b.status === 'Archived' ? 'var(--green)' : 'var(--brand-light)';
    return `
      <tr>
        <td><span class="bi-rank ${idx < 3 ? 'bi-rank--top' : ''}">${idx + 1}</span></td>
        <td class="bi-name-cell">
          <div class="bi-title-line">${Utils.esc(b.name || '-')}</div>
          <div class="bi-sub-line" style="color:${statusColor}">${Utils.esc(b.status || '-')}</div>
        </td>
        <td class="num">
          <div class="bi-progress">
            <div class="bi-progress__bar">
              <div class="bi-progress__fill" style="--pct:${Math.max(0, Math.min(100, progress))}%;--progress-color:${isBestProg ? 'var(--green)' : 'var(--brand-light)'}"></div>
            </div>
            <div class="bi-progress__label"><span>${progress}%</span><span>${isBestProg ? 'best' : ''}</span></div>
          </div>
        </td>
        <td class="num">${Number(b.done_tickets || 0)}/${Number(b.total_tickets || 0)}</td>
        <td class="num">${Number(b.member_count || 0)}</td>
        <td class="num" style="${isBestProd ? 'color:var(--green);font-weight:800' : ''}">${Utils.numFmt(productivity)}</td>
        <td class="num">${Number(b.duration_hours || 0)}h</td>
        <td class="num" style="color:var(--orange)">${Utils.costFmt(b.total_cost || 0)}</td>
        <td class="num" style="${isBestCost ? 'color:var(--green);font-weight:800' : ''}">${Utils.costFmt(costPerTicket)}</td>
        <td class="num">${Utils.numFmt(b.total_tokens || 0)}</td>
      </tr>`;
  },

  async renderDetail(container, teamId) {
    container.innerHTML = '<div class="enterprise-page"><div class="u-empty"><div class="u-empty__title">로딩중...</div></div></div>';
    const res = await API.historyTimeline(teamId);
    if (!res.ok) {
      container.innerHTML = '<div class="enterprise-page"><div class="u-empty"><div class="u-empty__title">팀을 찾을 수 없습니다</div></div></div>';
      return;
    }

    const { team, logs, members, tickets } = res;
    const total = tickets.length;
    const done = tickets.filter(t => t.status === 'Done').length;
    const blocked = tickets.filter(t => t.status === 'Blocked').length;
    const review = tickets.filter(t => t.status === 'Review').length;
    const progress = total > 0 ? Math.round(done / total * 100) : 0;

    container.innerHTML = `
      <div class="enterprise-page" id="historyDetailContent">
        <div class="enterprise-header">
          <div class="enterprise-heading">
            <h1 class="enterprise-title">${Utils.esc(team.name)}</h1>
            <div class="enterprise-subtitle">${Utils.esc(team.description || team.project_group || '')} · ${Utils.esc(team.status || '')}</div>
          </div>
          <div class="enterprise-actions">
            <a href="#/history" class="u-btn u-btn--sm">${Utils.icon('chevronRight', 13, 1.75)}목록</a>
            <button class="u-btn u-btn--sm u-btn--primary" onclick="TeamHistory.takeSnapshot('${Utils.attr(teamId)}')">${Utils.icon('download', 13, 1.75)}스냅샷</button>
          </div>
        </div>

        <div class="bi-kpi-grid bi-kpi-grid--six">
          ${this._kpi('Progress', progress + '%', done + '/' + total + ' done', 'var(--green)')}
          ${this._kpi('Tickets', total, 'Review ' + review + ' / Blocked ' + blocked, 'var(--brand-light)')}
          ${this._kpi('Agents', members.length, members.map(m => m.display_name || m.role).slice(0, 2).join(', '), 'var(--cyan)')}
          ${this._kpi('Activity', logs.length, 'timeline events', 'var(--purple-light)')}
          ${this._kpi('Open', Math.max(0, total - done), 'remaining work', 'var(--orange)')}
          ${this._kpi('Status', Utils.esc(team.status || '-'), 'team state', 'var(--yellow-light)')}
        </div>

        <div class="history-detail-grid">
          <section class="u-panel">
            <div class="u-panel__header">
              <h2 class="u-panel__title">Tickets</h2>
              <span class="u-badge">${tickets.length} rows</span>
            </div>
            <div class="bi-table-wrap">
              <table class="bi-table">
                <thead>
                  <tr>
                    <th>티켓</th>
                    <th>상태</th>
                    <th>우선순위</th>
                    <th class="num">생성</th>
                    <th class="num">완료</th>
                  </tr>
                </thead>
                <tbody>
                  ${tickets.map(tk => `
                    <tr>
                      <td class="bi-name-cell">
                        <div class="bi-title-line">${Utils.esc(tk.title)}</div>
                        <div class="bi-sub-line">${Utils.esc(tk.ticket_id || '')}</div>
                      </td>
                      <td><span class="status-badge status-${Utils.attr(tk.status)}">${Utils.statusLabel(tk.status)}</span></td>
                      <td><span class="pri pri-${Utils.attr(tk.priority || 'Medium')}">${Utils.esc(tk.priority || 'Medium')}</span></td>
                      <td class="num">${Utils.dateFmt(tk.created_at)}</td>
                      <td class="num">${Utils.dateFmt(tk.completed_at)}</td>
                    </tr>`).join('')}
                </tbody>
              </table>
            </div>
          </section>

          <section class="u-panel">
            <div class="u-panel__header">
              <h2 class="u-panel__title">Activity Timeline</h2>
              <span class="u-badge">${logs.length}</span>
            </div>
            <div class="history-activity-panel">
              ${logs.map(l => `
                <div class="log-entry" data-type="${Utils.esc(l.action || '')}">
                  <div class="log-head">
                    <span class="log-time">${Utils.dateFmt(l.created_at)}</span>
                    <span class="log-agent">${Utils.esc(l.agent_name || l.member_id || '-')}</span>
                    <span class="log-action">${Utils.esc(l.action || '-')}</span>
                  </div>
                  <div class="log-msg">${Utils.esc(l.message || '')}</div>
                </div>`).join('') || '<div class="u-empty"><div class="u-empty__desc">활동 없음</div></div>'}
            </div>
          </section>
        </div>
      </div>`;
  },

  async takeSnapshot(teamId) {
    const res = await API.historySnapshot(teamId);
    if (res.ok) alert('스냅샷이 저장되었습니다.');
    else alert('스냅샷 저장 실패');
  }
};
