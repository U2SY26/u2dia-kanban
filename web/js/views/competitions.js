/* U2DIA 재설계 — Competitions 뷰 (2026-04-17) */
const CompetitionsView = {
  async renderList(listEl, item) {
    listEl.innerHTML =
      '<div class="shell-list__header"><span class="shell-list__title">\uacbd\uc7c1</span></div>' +
      '<div class="shell-list__body">' +
      '<div class="u-list-item u-list-item--active"><span>\uc804\uccb4 \ub300\ud68c</span></div>' +
      '</div>';
  },

  render(mainEl, name) {
    if (typeof Competitions !== 'undefined') {
      if (name && Competitions.renderDetail) Competitions.renderDetail(mainEl, name);
      else if (Competitions.render) Competitions.render(mainEl);
    } else {
      mainEl.innerHTML = '<div class="u-empty"><div class="u-empty__desc">Competitions \ub85c\ub529 \uc2e4\ud328</div></div>';
    }
  }
};

if (typeof App !== 'undefined') App.registerView('competitions', CompetitionsView);
