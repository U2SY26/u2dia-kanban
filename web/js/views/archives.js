/* U2DIA 재설계 — Archives 뷰 (2026-04-17) */
const ArchivesView = {
  async renderList(listEl, item) {
    let list = [];
    try {
      const res = await API.archives();
      list = (res && res.archives) || [];
    } catch(e) {}
    let html = '<div class="shell-list__header"><span class="shell-list__title">\uc544\uce74\uc774\ube0c</span><span class="u-badge">' + list.length + '</span></div><div class="shell-list__body">';
    if (!list.length) {
      html += '<div class="u-empty"><div class="u-empty__title">\uc544\uce74\uc774\ube0c \uc5c6\uc74c</div></div>';
    } else {
      list.forEach(t => {
        const active = t.team_id === item;
        html += '<div class="u-list-item' + (active ? ' u-list-item--active' : '') + '" onclick="Router.navigate(\'#/archives/' + Utils.esc(t.team_id) + '\')">' +
          '<div style="flex:1;min-width:0">' +
          '<div style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">' + Utils.esc(t.name || t.team_id) + '</div>' +
          (t.archived_at ? '<div style="font-size:var(--text-xs);color:var(--text-muted-new);margin-top:2px">' + Utils.dateFmt(t.archived_at) + '</div>' : '') +
          '</div></div>';
      });
    }
    html += '</div>';
    listEl.innerHTML = html;
  },

  render(mainEl, teamId) {
    if (!teamId) {
      mainEl.innerHTML =
        '<div class="shell-main__content">' +
        '<div class="u-empty"><div class="u-empty__icon">' + Utils.icon('archives', 40, 1.25) + '</div><div class="u-empty__title">\uc544\uce74\uc774\ube0c</div><div class="u-empty__desc">\uc88c\uce21\uc5d0\uc11c \uc544\uce74\uc774\ube0c\ub41c \ud300\uc744 \uc120\ud0dd\ud558\uc138\uc694</div></div>' +
        '</div>';
      return;
    }
    if (typeof ArchiveDetail !== 'undefined' && ArchiveDetail.render) {
      ArchiveDetail.render(mainEl, teamId);
    } else {
      mainEl.innerHTML = '<div class="u-empty"><div class="u-empty__desc">ArchiveDetail \ub85c\ub529 \uc2e4\ud328</div></div>';
    }
  }
};

if (typeof App !== 'undefined') App.registerView('archives', ArchivesView);
