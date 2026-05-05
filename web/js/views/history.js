/* U2DIA 재설계 — History 뷰 (2026-04-17) */
const HistoryView = {
  _teamsCache: null,

  async renderList(listEl, activeId) {
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
        if (res && res.teams) {
          teams = res.teams;
          this._teamsCache = teams;
        }
      } catch(e) {}
    }
    let html = '<div class="shell-list__header"><span class="shell-list__title">\ud788\uc2a4\ud1a0\ub9ac</span><span class="u-badge">' + teams.length + '</span></div><div class="shell-list__body">';
    html += '<div class="u-list-item' + (!activeId ? ' u-list-item--active' : '') + '" onclick="Router.navigate(\'#/history\')">' +
      '<div style="flex:1;min-width:0">' +
      '<div class="shell-list__item-title">\uc804\uccb4 \uc6b4\uc601 \uae30\ub85d</div>' +
      '<div class="shell-list__item-meta"><span>BI</span><span>\ubca4\uce58\ub9c8\ud06c</span></div>' +
      '</div></div>';
    if (!teams.length) {
      if (activeId) {
        html += '<div class="u-list-item u-list-item--active" onclick="Router.navigate(\'#/history/' + Utils.esc(activeId) + '\')">' +
          '<div style="flex:1;min-width:0">' +
          '<div class="shell-list__item-title" title="' + Utils.attr(activeId) + '">' + Utils.esc(activeId) + '</div>' +
          '<div class="shell-list__item-meta"><span class="shell-list__mini-bar"><span style="width:100%"></span></span><span>\uc0c1\uc138</span></div>' +
          '</div></div>';
      } else {
        html += '<div class="u-empty"><div class="u-empty__desc">\uae30\ub85d \uc5c6\uc74c</div></div>';
      }
    } else {
      teams.slice(0, 42).forEach(t => {
        const team = t.team || t;
        const tid = team.team_id || t.team_id || team.id || t.id;
        const active = tid === activeId;
        const name = team.name || team.team_name || t.name || t.team_name || tid;
        const metrics = t.metrics || {};
        const pct = Number(metrics.progress || t.progress || 0);
        const total = Number(metrics.total_tickets || t.total_tickets || 0);
        const done = Number(metrics.done_tickets || t.done_tickets || 0);
        html += '<div class="u-list-item' + (active ? ' u-list-item--active' : '') + '" onclick="Router.navigate(\'#/history/' + Utils.esc(tid) + '\')">' +
          '<div style="flex:1;min-width:0">' +
          '<div class="shell-list__item-title" title="' + Utils.attr(name) + '">' + Utils.esc(name) + '</div>' +
          '<div class="shell-list__item-meta">' +
          '<span class="shell-list__mini-bar"><span style="width:' + Math.max(0, Math.min(100, pct)) + '%"></span></span>' +
          '<span>' + pct + '%</span><span>' + done + '/' + total + '</span>' +
          '</div></div>' +
          '</div>';
      });
      if (teams.length > 42) {
        html += '<div class="shell-list__item-meta" style="padding:6px 10px">' + (teams.length - 42) + '\uac1c \ud300\uc740 \ubcf8\ubb38 \ud14c\uc774\ube14\uc5d0\uc11c \ud655\uc778</div>';
      }
    }
    html += '</div>';
    listEl.innerHTML = html;
  },

  render(mainEl, teamId) {
    if (typeof TeamHistory !== 'undefined') {
      if (teamId && TeamHistory.renderDetail) TeamHistory.renderDetail(mainEl, teamId);
      else if (TeamHistory.render) TeamHistory.render(mainEl);
    } else {
      mainEl.innerHTML = '<div class="shell-main__content"><div class="u-empty"><div class="u-empty__icon">' + Utils.icon('history', 40, 1.25) + '</div><div class="u-empty__title">\ud788\uc2a4\ud1a0\ub9ac</div><div class="u-empty__desc">\uc88c\uce21\uc5d0\uc11c \ud300\uc744 \uc120\ud0dd\ud558\uc138\uc694</div></div></div>';
    }
  }
};

if (typeof App !== 'undefined') App.registerView('history', HistoryView);
