/* U2DIA 재설계 — Teams 뷰 (2026-04-17) */
const TeamsView = {
  _teams: [],
  _selectedTeamId: null,
  _collapsed: undefined,  // Set(\uc811\ud78c \uadf8\ub8f9\uba85) | null(\uccab \ubc29\ubb38=\uc804\uccb4 \uc811\ud798)

  _loadCollapsed() {
    if (this._collapsed !== undefined) return;
    try {
      const saved = localStorage.getItem('u2dia.teamGroupsCollapsed');
      this._collapsed = saved ? new Set(JSON.parse(saved)) : null;
    } catch(e) { this._collapsed = null; }
  },
  _saveCollapsed() {
    try { localStorage.setItem('u2dia.teamGroupsCollapsed', JSON.stringify([...(this._collapsed||[])])); } catch(e){}
  },
  toggleGroup(g) {
    if (!this._collapsed) this._collapsed = new Set();
    if (this._collapsed.has(g)) this._collapsed.delete(g); else this._collapsed.add(g);
    this._saveCollapsed();
    this.renderList(document.getElementById('shellList'), this._selectedTeamId);
  },

  async renderList(listEl, selectedItem) {
    this._selectedTeamId = selectedItem || null;
    this._loadCollapsed();
    let res;
    try { res = await API.overview(); } catch(e) { res = { teams: [] }; }
    this._teams = res.teams || [];

    const grouped = this._groupByProject(this._teams);
    const groupNames = Object.keys(grouped).sort();
    if (this._collapsed === null) this._collapsed = new Set(groupNames);  // \uccab \ubc29\ubb38 \uc804\uccb4 \uc811\ud798

    // \uc120\ud0dd\ub41c \ud300\uc774 \uc18d\ud55c \uadf8\ub8f9\uc740 \uac15\uc81c \ud3bc\uce68
    let selGroup = null;
    if (this._selectedTeamId) {
      groupNames.forEach(g => grouped[g].forEach(t => {
        const tid = (t.team||t).team_id || t.team_id;
        if (tid === this._selectedTeamId) selGroup = g;
      }));
    }

    let html =
      '<div class="shell-list__header">' +
      '  <span class="shell-list__title">\ud300 <span class="shell-list__count">' + this._teams.length + '</span></span>' +
      '  <button class="u-btn u-btn--xs u-btn--primary" onclick="TeamsView.createTeam()">+</button>' +
      '</div>' +
      '<div class="shell-list__body">';

    if (!this._teams.length) {
      html += '<div class="u-empty"><div class="u-empty__title">\ud300 \uc5c6\uc74c</div><div class="u-empty__desc">+ \ubc84\ud2bc\uc73c\ub85c \ud300\uc744 \uc0dd\uc131\ud558\uc138\uc694</div></div>';
    } else {
      groupNames.forEach(g => {
        const teams = grouped[g];
        const collapsed = this._collapsed.has(g) && g !== selGroup;
        const gDone = teams.reduce((a,t)=>a+(t.done_tickets||(t.team&&t.team.done_tickets)||0),0);
        const gTotal = teams.reduce((a,t)=>a+(t.total_tickets||(t.team&&t.team.total_tickets)||0),0);
        const gPct = gTotal>0 ? Math.round(gDone/gTotal*100) : 0;
        const gKey = g.replace(/'/g, "\\'");
        html +=
          '<div class="shell-group' + (collapsed ? '' : ' shell-group--open') + '" onclick="TeamsView.toggleGroup(\'' + Utils.esc(gKey) + '\')">' +
          '  <svg class="shell-group__chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>' +
          '  <span class="shell-group__name">' + Utils.esc(g) + '</span>' +
          '  <span class="shell-group__count">' + teams.length + '</span>' +
          '  <span class="shell-group__pct">' + gPct + '%</span>' +
          '</div>';
        if (!collapsed) {
          html += '<div class="shell-group__body">';
          teams.forEach(t => {
            const team = t.team || t;
            const teamId = team.team_id || t.team_id;
            const total = t.total_tickets || team.total_tickets || 0;
            const done = t.done_tickets || team.done_tickets || 0;
            const blocked = t.blocked_tickets || team.blocked_tickets || 0;
            const pct = total > 0 ? Math.round(done/total*100) : 0;
            const active = teamId === this._selectedTeamId;
            const barCls = blocked>0 ? ' shell-team__bar-fill--warn' : (pct>=100 ? ' shell-team__bar-fill--done' : '');
            html +=
              '<div class="shell-team' + (active ? ' shell-team--active' : '') + '" onclick="event.stopPropagation();Router.navigate(\'#/board/' + Utils.esc(teamId) + '\')">' +
              '  <div class="shell-team__name">' + Utils.esc(team.name || teamId) + '</div>' +
              '  <div class="shell-team__meta">' +
              '    <div class="shell-team__bar"><div class="shell-team__bar-fill' + barCls + '" style="width:' + pct + '%"></div></div>' +
              '    <span class="shell-team__nums">' + done + '/' + total + (blocked>0?' <span class="shell-team__blocked">\u26d4'+blocked+'</span>':'') + '</span>' +
              '  </div>' +
              '</div>';
          });
          html += '</div>';
        }
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
