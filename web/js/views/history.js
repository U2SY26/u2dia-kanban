/* U2DIA 재설계 — History 뷰 (2026-04-17) */
const HistoryView = {
  _teamsCache: null,
  _collapsed: undefined,

  _loadCollapsed() {
    if (this._collapsed !== undefined) return;
    try {
      const saved = localStorage.getItem('u2dia.historyGroupsCollapsed');
      this._collapsed = saved ? new Set(JSON.parse(saved)) : null;
    } catch(e) { this._collapsed = null; }
  },
  _saveCollapsed() {
    try { localStorage.setItem('u2dia.historyGroupsCollapsed', JSON.stringify([...(this._collapsed||[])])); } catch(e){}
  },
  toggleGroup(g) {
    if (!this._collapsed) this._collapsed = new Set();
    if (this._collapsed.has(g)) this._collapsed.delete(g); else this._collapsed.add(g);
    this._saveCollapsed();
    this.renderList(document.getElementById('shellList'), this._activeId);
  },
  _groupByProject(teams) {
    const g = {};
    teams.forEach(t => {
      const team = t.team || t;
      const proj = team.project_group || t.project_group || '\uae30\ud0c0';
      (g[proj] = g[proj] || []).push(t);
    });
    return g;
  },

  async renderList(listEl, activeId) {
    this._activeId = activeId || null;
    this._loadCollapsed();
    let teams = this._teamsCache || [];
    if (!teams.length) {
      try {
        const request = API.historyTeams();
        request.then(res => {
          if (res && res.teams) {
            this._teamsCache = res.teams;
            if (typeof Sidebar !== 'undefined' && Sidebar._activeSection === 'history') Sidebar.refreshList();
          }
        }).catch(() => {});
        const timeout = new Promise(resolve => setTimeout(() => resolve(null), 700));
        const res = await Promise.race([request, timeout]);
        if (res && res.teams) { teams = res.teams; this._teamsCache = teams; }
      } catch(e) {}
    }

    const grouped = this._groupByProject(teams);
    const groupNames = Object.keys(grouped).sort();
    if (this._collapsed === null) this._collapsed = new Set(groupNames);
    let selGroup = null;
    if (activeId) groupNames.forEach(g => grouped[g].forEach(t => {
      const tid = (t.team||t).team_id || t.team_id || (t.team||t).id || t.id;
      if (tid === activeId) selGroup = g;
    }));

    let html =
      '<div class="shell-list__header">' +
        '<span class="shell-list__title">\uc6b4\uc601\uae30\ub85d <span class="shell-list__count">' + teams.length + '</span></span>' +
      '</div>' +
      '<div class="shell-list__body">' +
      '<div class="shell-team' + (!activeId ? ' shell-team--active' : '') + '" onclick="Router.navigate(\'#/history\')" style="margin:6px 6px 4px">' +
      '  <div class="shell-team__name">\ud83d\udcca \uc804\uccb4 \uc6b4\uc601 \uae30\ub85d</div>' +
      '  <div class="shell-team__meta"><span class="shell-team__nums">BI \u00b7 \ubca4\uce58\ub9c8\ud06c</span></div>' +
      '</div>';

    if (!teams.length) {
      html += '<div class="u-empty"><div class="u-empty__title">\ud65c\ub3d9 \uae30\ub85d \uc5c6\uc74c</div>' +
        '<div class="u-empty__desc">\ud300\uc5d0\uc11c \ud65c\ub3d9\uc774 \ubc1c\uc0dd\ud558\uba74 \uc2e4\uc2dc\uac04\uc73c\ub85c \uae30\ub85d\ub429\ub2c8\ub2e4</div></div>';
    } else {
      groupNames.forEach(g => {
        const ts = grouped[g];
        const collapsed = this._collapsed.has(g) && g !== selGroup;
        const gKey = g.replace(/'/g, "\\'");
        html +=
          '<div class="shell-group' + (collapsed ? '' : ' shell-group--open') + '" onclick="HistoryView.toggleGroup(\'' + Utils.esc(gKey) + '\')">' +
          '  <svg class="shell-group__chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>' +
          '  <span class="shell-group__name">' + Utils.esc(g) + '</span>' +
          '  <span class="shell-group__count">' + ts.length + '</span>' +
          '</div>';
        if (!collapsed) {
          html += '<div class="shell-group__body">';
          ts.forEach(t => {
            const team = t.team || t;
            const tid = team.team_id || t.team_id || team.id || t.id;
            const active = tid === activeId;
            const name = team.name || team.team_name || t.name || tid;
            const metrics = t.metrics || {};
            const pct = Number(metrics.progress || t.progress || 0);
            const total = Number(metrics.total_tickets || t.total_tickets || 0);
            const done = Number(metrics.done_tickets || t.done_tickets || 0);
            html +=
              '<div class="shell-team' + (active ? ' shell-team--active' : '') + '" onclick="event.stopPropagation();Router.navigate(\'#/history/' + Utils.esc(tid) + '\')">' +
              '  <div class="shell-team__name">' + Utils.esc(name) + '</div>' +
              '  <div class="shell-team__meta">' +
              '    <div class="shell-team__bar"><div class="shell-team__bar-fill' + (pct>=100?' shell-team__bar-fill--done':'') + '" style="width:' + Math.max(0,Math.min(100,pct)) + '%"></div></div>' +
              '    <span class="shell-team__nums">' + done + '/' + total + '</span>' +
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

  render(mainEl, teamId) {
    if (typeof TeamHistory !== 'undefined') {
      if (teamId && TeamHistory.renderDetail) TeamHistory.renderDetail(mainEl, teamId);
      else if (TeamHistory.render) TeamHistory.render(mainEl);
    } else {
      mainEl.innerHTML = '<div class="shell-main__content"><div class="u-empty"><div class="u-empty__icon" style="font-size:64px;opacity:0.3;color:#3b82f6">\ud83d\udcdc</div><div class="u-empty__title">\uc6b4\uc601\uae30\ub85d (Live)</div><div class="u-empty__desc">\uc9c4\ud589 \uc911\uc778 \ud300\uc758 \uc2e4\uc2dc\uac04 \ud65c\ub3d9/\uba54\ud2b8\ub9ad\uc744 \ud655\uc778\ud569\ub2c8\ub2e4.<br/>\uc67c\ucabd\uc5d0\uc11c \ud300\uc744 \uc120\ud0dd\ud558\uc138\uc694.</div></div></div>';
    }
  }
};

if (typeof App !== 'undefined') App.registerView('history', HistoryView);
