/* U2DIA AI SERVER AGENT — History & Benchmarking */
const TeamHistory = {
  _data: null,
  _benchmarks: null,
  _tab: 'teams', // 'teams' | 'benchmark'

  async render(container) {
    container.innerHTML = `
      <div class="dash-layout" id="historyContent">
        <div class="dash-header-row">
          <h2 style="font-size:var(--fs-xl);font-weight:800;letter-spacing:-0.5px">History & Benchmarking</h2>
          <div class="flex gap-8 items-center">
            <a href="#/" class="btn btn-sm">대시보드</a>
          </div>
        </div>

        <!-- Tab bar -->
        <div class="tabs" id="historyTabs">
          <div class="tab active" data-tab="teams" onclick="TeamHistory.switchTab('teams')">팀 히스토리</div>
          <div class="tab" data-tab="benchmark" onclick="TeamHistory.switchTab('benchmark')">벤치마킹</div>
        </div>

        <!-- Content -->
        <div id="historyBody" style="min-height:300px"></div>
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
    if (teamsRes.ok) this._data = teamsRes.teams;
    if (benchRes.ok) this._benchmarks = benchRes.benchmarks;
    this._renderTeams();
  },

  _renderTeams() {
    const el = Utils.$('historyBody');
    if (!el || !this._data) return;

    if (!this._data.length) {
      el.innerHTML = '<div class="empty-state">팀 히스토리가 없습니다</div>';
      return;
    }

    el.innerHTML = `
      <div style="display:flex;flex-direction:column;gap:12px;margin-top:16px">
        ${this._data.map(d => this._buildTeamRow(d)).join('')}
      </div>`;
  },

  _buildTeamRow(d) {
    const t = d.team, m = d.metrics;
    const statusBadge = t.status === 'Archived'
      ? '<span style="font-size:var(--fs-xs);padding:2px 8px;border-radius:4px;background:var(--green-bg);color:var(--green)">Archived</span>'
      : '<span style="font-size:var(--fs-xs);padding:2px 8px;border-radius:4px;background:var(--brand-bg);color:var(--brand-light)">Active</span>';

    return `
      <div class="card" style="padding:0;cursor:pointer;overflow:hidden" onclick="Router.navigate('#/history/${t.team_id}')">
        <div style="display:flex;align-items:center;gap:20px;padding:18px 24px">
          <div style="width:4px;height:60px;border-radius:2px;background:${m.progress >= 100 ? 'var(--green)' : m.progress > 0 ? 'var(--brand)' : 'var(--muted)'};flex-shrink:0"></div>
          <div style="flex:1;min-width:0">
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:4px">
              <span style="font-size:var(--fs-lg);font-weight:700">${Utils.esc(t.name)}</span>
              ${statusBadge}
            </div>
            <div style="font-size:var(--fs-xs);color:var(--muted)">${Utils.esc(t.description || '')} · 생성: ${Utils.dateFmt(t.created_at)}</div>
          </div>
          <div style="display:flex;gap:24px;align-items:center;flex-shrink:0">
            <div style="text-align:center">
              <div style="font-size:var(--fs-2xl);font-weight:800;font-family:var(--mono);color:var(${m.progress >= 100 ? '--green' : '--brand'})">${m.progress}%</div>
              <div style="font-size:var(--fs-xs);color:var(--muted)">진행률</div>
            </div>
            <div style="text-align:center">
              <div style="font-size:var(--fs-lg);font-weight:700;font-family:var(--mono)">${m.done_tickets}/${m.total_tickets}</div>
              <div style="font-size:var(--fs-xs);color:var(--muted)">완료/전체</div>
            </div>
            <div style="text-align:center">
              <div style="font-size:var(--fs-lg);font-weight:700;font-family:var(--mono)">${m.member_count}</div>
              <div style="font-size:var(--fs-xs);color:var(--muted)">에이전트</div>
            </div>
            <div style="text-align:center">
              <div style="font-size:var(--fs-lg);font-weight:700;font-family:var(--mono)">${m.total_logs}</div>
              <div style="font-size:var(--fs-xs);color:var(--muted)">활동</div>
            </div>
            <div style="text-align:center">
              <div style="font-size:var(--fs-lg);font-weight:700;font-family:var(--mono);color:var(--orange)">${Utils.costFmt(m.estimated_cost)}</div>
              <div style="font-size:var(--fs-xs);color:var(--muted)">비용</div>
            </div>
          </div>
        </div>
      </div>`;
  },

  _renderBenchmark() {
    const el = Utils.$('historyBody');
    if (!el || !this._benchmarks) return;

    if (!this._benchmarks.length) {
      el.innerHTML = '<div class="empty-state">벤치마킹 데이터가 없습니다</div>';
      return;
    }

    // Find best values for highlighting
    const best = {
      progress: Math.max(...this._benchmarks.map(b => b.progress)),
      productivity: Math.max(...this._benchmarks.map(b => b.productivity)),
      costEfficiency: Math.min(...this._benchmarks.filter(b => b.cost_per_ticket > 0).map(b => b.cost_per_ticket)) || 0
    };

    el.innerHTML = `
      <div style="margin-top:16px;overflow-x:auto">
        <table style="width:100%;border-collapse:collapse;font-size:var(--fs-sm)">
          <thead>
            <tr style="border-bottom:2px solid var(--line);text-align:left">
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px">순위</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px">팀</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px;text-align:right">진행률</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px;text-align:right">티켓</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px;text-align:right">에이전트</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px;text-align:right">생산성</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px;text-align:right">활동시간</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px;text-align:right">총 비용</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px;text-align:right">티켓당 비용</th>
              <th style="padding:12px 16px;color:var(--text-secondary);font-weight:700;text-transform:uppercase;letter-spacing:0.5px;text-align:right">총 토큰</th>
            </tr>
          </thead>
          <tbody>
            ${this._benchmarks.map((b, i) => this._buildBenchRow(b, i, best)).join('')}
          </tbody>
        </table>
      </div>`;
  },

  _buildBenchRow(b, idx, best) {
    const isBestProg = b.progress === best.progress && b.progress > 0;
    const isBestProd = b.productivity === best.productivity && b.productivity > 0;
    const isBestCost = b.cost_per_ticket === best.costEfficiency && b.cost_per_ticket > 0;
    const rankStyle = idx === 0 ? 'color:var(--yellow);font-weight:800' : idx === 1 ? 'color:var(--text-secondary)' : 'color:var(--muted)';
    const rankIcon = idx === 0 ? '🥇' : idx === 1 ? '🥈' : idx === 2 ? '🥉' : `${idx + 1}`;
    const statusColor = b.status === 'Archived' ? 'var(--green)' : 'var(--brand-light)';

    return `
      <tr style="border-bottom:1px solid var(--line);transition:background 0.15s" onmouseenter="this.style.background='var(--card-hover)'" onmouseleave="this.style.background='transparent'">
        <td style="padding:12px 16px;${rankStyle};font-size:var(--fs-lg)">${rankIcon}</td>
        <td style="padding:12px 16px">
          <div style="font-weight:700">${Utils.esc(b.name)}</div>
          <div style="font-size:var(--fs-xs);color:${statusColor}">${b.status}</div>
        </td>
        <td style="padding:12px 16px;text-align:right">
          <span style="font-weight:700;font-family:var(--mono);color:${isBestProg ? 'var(--green)' : 'var(--text)'}">${b.progress}%</span>
          <div style="height:4px;width:80px;background:var(--line);border-radius:2px;margin-top:4px;margin-left:auto">
            <div style="height:100%;width:${b.progress}%;background:${isBestProg ? 'var(--green)' : 'var(--brand)'};border-radius:2px"></div>
          </div>
        </td>
        <td style="padding:12px 16px;text-align:right;font-family:var(--mono)">${b.done_tickets}/${b.total_tickets}</td>
        <td style="padding:12px 16px;text-align:right;font-family:var(--mono)">${b.member_count}</td>
        <td style="padding:12px 16px;text-align:right;font-family:var(--mono);${isBestProd ? 'color:var(--green);font-weight:700' : ''}">${b.productivity}</td>
        <td style="padding:12px 16px;text-align:right;font-family:var(--mono)">${b.duration_hours}h</td>
        <td style="padding:12px 16px;text-align:right;font-family:var(--mono);color:var(--orange)">${Utils.costFmt(b.total_cost)}</td>
        <td style="padding:12px 16px;text-align:right;font-family:var(--mono);${isBestCost ? 'color:var(--green);font-weight:700' : ''}">${Utils.costFmt(b.cost_per_ticket)}</td>
        <td style="padding:12px 16px;text-align:right;font-family:var(--mono)">${Utils.numFmt(b.total_tokens)}</td>
      </tr>`;
  },

  /* ── Team Detail (Timeline) ── */
  async renderDetail(container, teamId) {
    container.innerHTML = '<div class="dash-layout"><div class="empty-state">로딩중...</div></div>';
    const res = await API.historyTimeline(teamId);
    if (!res.ok) {
      container.innerHTML = '<div class="dash-layout"><div class="empty-state">팀을 찾을 수 없습니다</div></div>';
      return;
    }

    const { team, logs, members, tickets, snapshots } = res;
    const total = tickets.length;
    const done = tickets.filter(t => t.status === 'Done').length;
    const progress = total > 0 ? Math.round(done / total * 100) : 0;

    container.innerHTML = `
      <div class="dash-layout" id="historyDetailContent">
        <div class="dash-header-row">
          <div>
            <h2 style="font-size:var(--fs-xl);font-weight:800;letter-spacing:-0.5px">${Utils.esc(team.name)}</h2>
            <div style="font-size:var(--fs-sm);color:var(--muted);margin-top:4px">${Utils.esc(team.description || '')} · ${team.status}</div>
          </div>
          <div class="flex gap-8 items-center">
            <a href="#/history" class="btn btn-sm">목록으로</a>
            <button class="btn btn-sm" onclick="TeamHistory.takeSnapshot('${teamId}')">스냅샷 저장</button>
          </div>
        </div>

        <!-- Summary KPIs -->
        <div class="dash-hero-stats">
          <div class="hero-stat">
            <div style="position:absolute;top:0;left:0;width:4px;height:100%;border-radius:0 2px 2px 0;background:var(--chart-blue)"></div>
            <div class="icon-ring" style="background:var(--grad-blue);color:#fff">▣</div>
            <div class="stat-info">
              <div class="label">티켓</div>
              <div class="value" style="color:var(--chart-blue)">${done}/${total}</div>
              <div class="sub">완료 / 전체</div>
            </div>
          </div>
          <div class="hero-stat">
            <div style="position:absolute;top:0;left:0;width:4px;height:100%;border-radius:0 2px 2px 0;background:var(--chart-green)"></div>
            <div class="icon-ring" style="background:var(--grad-green);color:#fff">◉</div>
            <div class="stat-info">
              <div class="label">진행률</div>
              <div class="value" style="color:var(--chart-green)">${progress}%</div>
              <div class="sub">${team.status === 'Archived' ? '아카이브됨' : '진행중'}</div>
            </div>
          </div>
          <div class="hero-stat">
            <div style="position:absolute;top:0;left:0;width:4px;height:100%;border-radius:0 2px 2px 0;background:var(--chart-cyan)"></div>
            <div class="icon-ring" style="background:var(--grad-cyan);color:#fff">⬡</div>
            <div class="stat-info">
              <div class="label">에이전트</div>
              <div class="value" style="color:var(--chart-cyan)">${members.length}</div>
              <div class="sub">${members.map(m => m.display_name || m.role).join(', ') || '-'}</div>
            </div>
          </div>
          <div class="hero-stat">
            <div style="position:absolute;top:0;left:0;width:4px;height:100%;border-radius:0 2px 2px 0;background:var(--chart-purple)"></div>
            <div class="icon-ring" style="background:var(--grad-purple);color:#fff">◈</div>
            <div class="stat-info">
              <div class="label">활동 로그</div>
              <div class="value" style="color:var(--chart-purple)">${logs.length}</div>
              <div class="sub">전체 기록</div>
            </div>
          </div>
        </div>

        <!-- Tickets List -->
        <div>
          <div class="dash-section-header" style="background:var(--card);border-radius:var(--radius-lg) var(--radius-lg) 0 0">
            <h3>티켓 목록</h3>
            <span class="badge">${tickets.length}개</span>
          </div>
          <div style="background:var(--card);border:1px solid var(--line);border-top:none;border-radius:0 0 var(--radius-lg) var(--radius-lg);overflow:hidden">
            ${tickets.length ? tickets.map(tk => `
              <div style="display:flex;align-items:center;gap:12px;padding:12px 20px;border-bottom:1px solid var(--line)">
                <span class="status-badge status-${tk.status}" style="min-width:48px;text-align:center">${Utils.statusLabel(tk.status)}</span>
                <span class="pri pri-${tk.priority}">${tk.priority}</span>
                <span style="flex:1;font-weight:600">${Utils.esc(tk.title)}</span>
                <span style="font-size:var(--fs-xs);color:var(--muted)">${Utils.dateFmt(tk.created_at)}</span>
              </div>
            `).join('') : '<div style="padding:20px;text-align:center;color:var(--muted)">티켓 없음</div>'}
          </div>
        </div>

        <!-- Activity Timeline -->
        <div>
          <div class="dash-section-header" style="background:var(--card);border-radius:var(--radius-lg) var(--radius-lg) 0 0">
            <h3>활동 타임라인</h3>
            <span class="badge">${logs.length}건</span>
          </div>
          <div class="dash-activity-panel" style="border-radius:0 0 var(--radius-lg) var(--radius-lg);border-top:none;max-height:600px">
            <div class="dash-activity-scroll" id="historyTimeline">
              ${logs.map(l => `
                <div class="log-entry" data-type="${Utils.esc(l.action || '')}">
                  <div class="log-head">
                    <span class="log-time">${Utils.dateFmt(l.created_at)}</span>
                    <span class="log-agent">${Utils.esc(l.agent_name || l.member_id || '-')}</span>
                    <span class="log-action">${Utils.esc(l.action)}</span>
                  </div>
                  <div class="log-msg">${Utils.esc(l.message || '')}</div>
                </div>
              `).join('')}
            </div>
          </div>
        </div>
      </div>`;
  },

  async takeSnapshot(teamId) {
    const res = await API.historySnapshot(teamId);
    if (res.ok) alert('스냅샷이 저장되었습니다.');
    else alert('스냅샷 저장 실패');
  }
};
