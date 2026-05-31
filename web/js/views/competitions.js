/* U2DIA — Competitions 뷰 (Kaggle 스타일, 2026-05-31) */
const CompetitionsView = {
  _comps: [
    {
      title: 'Gemma 4 Good Hackathon',
      host: 'Kaggle · Google DeepMind', track: 'AI for Education',
      status: '진행 중', statusCls: 'live', stage: 2,
      desc: 'Gemma 4 + 3D 입자 물리 시뮬레이터로 과학 교육 — text-to-3D 구조 생성과 실시간 물리 시뮬레이션',
      tags: ['Gemma 4', 'Education', '3D Physics'],
      url: 'https://www.kaggle.com/competitions'
    },
    {
      title: 'The Uncharted Data Challenge',
      host: 'Adaption', track: 'Low-resource NLP',
      status: '제출 완료', statusCls: 'done', stage: 4,
      desc: '제주어(UNESCO 소멸위기 언어) 멀티소스 강화 코퍼스 Jejueo+ — Adaptive Data 기반',
      tags: ['Jejueo', 'Corpus', 'CC BY-SA 4.0'],
      url: 'https://www.adaption.dev'
    }
  ],
  _stages: ['Enroll', 'Build', 'Train', 'Submit', 'Result'],

  async renderList() { /* NO_LIST — 좌측 목록 없음 */ },

  render(mainEl) {
    const stages = this._stages;
    const card = (c) => {
      const stepper = stages.map((s, i) =>
        '<div class="comp-step' + (i <= c.stage ? ' comp-step--done' : '') + '">' +
        '<span class="comp-step__dot"></span><span class="comp-step__label">' + Utils.esc(s) + '</span></div>'
      ).join('<span class="comp-step__line"></span>');
      return '<a class="comp-card" href="' + c.url + '" target="_blank" rel="noopener noreferrer">' +
        '<div class="comp-card__top">' +
        '  <div><div class="comp-card__track">' + Utils.esc(c.track) + '</div>' +
        '       <div class="comp-card__title">' + Utils.esc(c.title) + '</div>' +
        '       <div class="comp-card__host">' + Utils.esc(c.host) + '</div></div>' +
        '  <span class="comp-badge comp-badge--' + c.statusCls + '">' + Utils.esc(c.status) + '</span>' +
        '</div>' +
        '<div class="comp-card__desc">' + Utils.esc(c.desc) + '</div>' +
        '<div class="comp-stepper">' + stepper + '</div>' +
        '<div class="comp-tags">' + c.tags.map(t => '<span class="comp-tag">' + Utils.esc(t) + '</span>').join('') + '</div>' +
        '</a>';
    };
    mainEl.innerHTML =
      '<div class="shell-main__content">' +
      '  <div class="bill-toolbar"><h1 class="u-panel__title" style="font-size:18px;margin:0">대회 참가 현황</h1>' +
      '    <span class="u-badge" style="margin-left:8px">' + this._comps.length + ' Competitions</span></div>' +
      '  <div class="comp-grid">' + this._comps.map(card).join('') + '</div>' +
      '</div>';
  }
};

if (typeof App !== 'undefined') App.registerView('competitions', CompetitionsView);
