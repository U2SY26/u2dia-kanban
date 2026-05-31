/* U2DIA — Archives 뷰 (보관함: 완료된 팀의 Read-only 스냅샷) */
const ArchivesView = {
  async renderList(listEl, item) {
    let list = [];
    try {
      const res = await API.archives();
      list = (res && res.archives) || [];
    } catch(e) {}
    let html =
      '<div class="shell-list__header">' +
        '<span class="shell-list__title" style="display:inline-flex;align-items:center;gap:6px">' +
          '<span style="opacity:0.85">📦</span>보관함' +
        '</span>' +
        '<span class="u-badge" style="background:rgba(120,120,140,0.18);color:#a8acb8">' + list.length + '</span>' +
      '</div>' +
      '<div style="padding:8px 14px;font-size:11px;color:var(--text-muted-new);border-bottom:1px solid rgba(255,255,255,0.05);letter-spacing:0.02em">' +
        '완료/종료된 팀 · Read-only 스냅샷' +
      '</div>' +
      '<div class="shell-list__body">';
    if (!list.length) {
      html += '<div class="u-empty">' +
        '<div class="u-empty__icon" style="font-size:32px;opacity:0.4">📦</div>' +
        '<div class="u-empty__title">보관된 팀 없음</div>' +
        '<div class="u-empty__desc" style="font-size:11px;color:var(--text-muted-new);margin-top:4px">팀 보드에서 "팀 아카이브"를 누르면 여기로 이동합니다</div>' +
        '</div>';
    } else {
      list.forEach(t => {
        const active = t.team_id === item;
        html += '<div class="u-list-item' + (active ? ' u-list-item--active' : '') + '" onclick="Router.navigate(\'#/archives/' + Utils.esc(t.team_id) + '\')">' +
          '<div style="flex:1;min-width:0">' +
          '<div style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#c8ccd4">' + Utils.esc(t.name || t.team_id) + '</div>' +
          (t.archived_at ? '<div style="font-size:var(--text-xs);color:var(--text-muted-new);margin-top:2px">📅 ' + Utils.dateFmt(t.archived_at) + '</div>' : '') +
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
        '<div class="u-empty">' +
          '<div class="u-empty__icon" style="font-size:64px;opacity:0.3">📦</div>' +
          '<div class="u-empty__title">보관함 (Read-only)</div>' +
          '<div class="u-empty__desc">완료된 팀의 최종 상태가 보존됩니다.<br/>왼쪽에서 팀을 선택하면 당시의 보드/티켓/산출물을 그대로 볼 수 있습니다.</div>' +
        '</div>' +
        '</div>';
      return;
    }
    if (typeof ArchiveDetail !== 'undefined' && ArchiveDetail.render) {
      ArchiveDetail.render(mainEl, teamId);
    } else {
      mainEl.innerHTML = '<div class="u-empty"><div class="u-empty__desc">ArchiveDetail 로딩 실패</div></div>';
    }
  }
};

if (typeof App !== 'undefined') App.registerView('archives', ArchivesView);
