/* U2DIA 재설계 — Teams 뷰 (2026-04-17) */
const TeamsView = {
  _teams: [],
  _selectedTeamId: null,

  async renderList(listEl, selectedItem) {
    this._selectedTeamId = selectedItem || null;
    let res;
    try { res = await API.overview(); } catch(e) { res = { teams: [] }; }
    this._teams = res.teams || [];

    const grouped = this._groupByProject(this._teams);
    const groupNames = Object.keys(grouped).sort();

    let html =
      '<div class="shell-list__header">' +
      '  <span class="shell-list__title">\ud300</span>' +
      '  <button class="u-btn u-btn--xs u-btn--primary" onclick="TeamsView.createTeam()">+</button>' +
      '</div>' +
      '<div class="shell-list__body">';

    if (!this._teams.length) {
      html += '<div class="u-empty"><div class="u-empty__title">\ud300 \uc5c6\uc74c</div><div class="u-empty__desc">+ \ubc84\ud2bc\uc73c\ub85c \ud300\uc744 \uc0dd\uc131\ud558\uc138\uc694</div></div>';
    } else {
      groupNames.forEach(g => {
        html += '<div style="padding:var(--space-2) var(--space-3);font-size:var(--text-xs);color:var(--text-muted-new);text-transform:uppercase;letter-spacing:0.5px;margin-top:var(--space-2)">' + Utils.esc(g) + '</div>';
        grouped[g].forEach(t => {
          const team = t.team || t;
          const teamId = team.team_id || t.team_id;
          const total = t.total_tickets || team.total_tickets || 0;
          const done = t.done_tickets || team.done_tickets || 0;
          const pct = total > 0 ? Math.round(done/total*100) : 0;
          const active = teamId === this._selectedTeamId;
          html +=
            '<div class="u-list-item' + (active ? ' u-list-item--active' : '') + '" onclick="Router.navigate(\'#/board/' + Utils.esc(teamId) + '\')">' +
            '  <div style="flex:1;min-width:0">' +
            '    <div style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">' + Utils.esc(team.name || teamId) + '</div>' +
            '    <div style="display:flex;align-items:center;gap:var(--space-2);margin-top:2px">' +
            '      <div style="flex:1;height:3px;background:var(--surface-0);border-radius:2px;overflow:hidden"><div style="width:' + pct + '%;height:100%;background:var(--brand)"></div></div>' +
            '      <span style="font-size:var(--text-xs);color:var(--text-muted-new)">' + done + '/' + total + '</span>' +
            '    </div>' +
            '  </div>' +
            '</div>';
        });
      });
    }

    html += '</div>';
    listEl.innerHTML = html;
  },

  _groupByProject(teams) {
    const g = {};
    teams.forEach(t => {
      const team = t.team || t;
      const proj = team.project_group || t.project_group || '\uae30\ud0c0';
      if (!g[proj]) g[proj] = [];
      g[proj].push(t);
    });
    return g;
  },

  async render(mainEl, teamId) {
    if (!teamId) {
      mainEl.innerHTML =
        '<div class="shell-main__content">' +
        '  <div class="u-empty">' +
        '    <div class="u-empty__icon">' + Utils.icon('kanban', 40, 1.25) + '</div>' +
        '    <div class="u-empty__title">\ud300\uc744 \uc120\ud0dd\ud558\uc138\uc694</div>' +
        '    <div class="u-empty__desc">\uc88c\uce21 \ubaa9\ub85d\uc5d0\uc11c \ud300\uc744 \ud074\ub9ad\ud558\uba74 \uce78\ubc18\ubcf4\ub4dc\uac00 \uc5f4\ub9bd\ub2c8\ub2e4</div>' +
        '  </div>' +
        '</div>';
      return;
    }
    if (typeof Kanban !== 'undefined' && typeof Kanban.render === 'function') {
      Kanban.render(mainEl, teamId);
    } else {
      mainEl.innerHTML = '<div class="u-empty"><div class="u-empty__desc">Kanban \ub80c\ub354\ub7ec \ub85c\ub529 \uc2e4\ud328</div></div>';
    }
  },

  refresh() {
    if (this._selectedTeamId && typeof Kanban !== 'undefined' && Kanban.refresh) Kanban.refresh();
  },

  async createTeam() {
    const name = prompt('\ud300 \uc774\ub984:');
    if (!name) return;
    const group = prompt('\ud504\ub85c\uc81d\ud2b8 \uadf8\ub8f9 (\uc0dd\ub7b5 \uac00\ub2a5):') || '';
    try {
      const res = await API.post('/api/teams', { name, project_group: group });
      if (res && (res.ok || res.team_id)) {
        await this.renderList(document.getElementById('shellList'), this._selectedTeamId);
        if (res.team_id) Router.navigate('#/board/' + res.team_id);
      } else {
        alert('\ud300 \uc0dd\uc131 \uc2e4\ud328: ' + (res.error || ''));
      }
    } catch(e) {
      alert('\ud300 \uc0dd\uc131 \uc2e4\ud328: ' + e.message);
    }
  }
};

if (typeof App !== 'undefined') App.registerView('teams', TeamsView);
