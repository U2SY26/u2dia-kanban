/* U2DIA — Competitions 뷰 (실데이터 연동: /api/competitions + Brev 학습기록) */
const CompetitionsView = {
  _comps: [],
  _training: null,
  _stages: ['Enroll', 'Build', 'Train', 'Submit', 'Result'],

  async renderList() { /* NO_LIST — 좌측 목록 없음 */ },

  async render(mainEl) {
    mainEl.innerHTML = '<div class="shell-main__content"><div class="u-empty"><div class="u-empty__icon">◇</div><div class="u-empty__title">대회 데이터 불러오는 중…</div></div></div>';
    try { const r = await API.get('/api/competitions'); this._comps = (r && r.competitions) || []; } catch(e) { this._comps = []; }
    try { const t = await API.get('/api/competitions/training'); this._training = (t && t.available) ? t : null; } catch(e) { this._training = null; }
    this._renderContent(mainEl);
  },

  _statusOf(c) {
    if (c.submission_status === 'submitted' || c.has_submission) return { label: '제출 완료', cls: 'done', stage: 4 };
    if (c.status === 'active' || (c.team_count || 0) > 0) return { label: '진행 중', cls: 'live', stage: 2 };
    return { label: '준비 중', cls: 'idle', stage: 1 };
  },

  _renderContent(mainEl) {
    const stages = this._stages;
    const training = this._training;
    const fmtUsd = (n) => n ? '$' + Number(n).toLocaleString('en-US') : '';
    const num = (n) => Number(n || 0).toLocaleString('ko-KR');
    const statCell = (k, v) => '<div class="comp-brev__stat"><div class="comp-brev__v">' + v + '</div><div class="comp-brev__k">' + Utils.esc(k) + '</div></div>';

    const card = (c) => {
      const st = this._statusOf(c);
      const title = (c.title && c.title !== c.name) ? c.title : c.name;
      const stepper = stages.map((s, i) =>
        '<div class="comp-step' + (i <= st.stage ? ' comp-step--done' : '') + '"><span class="comp-step__dot"></span><span class="comp-step__label">' + Utils.esc(s) + '</span></div>'
      ).join('<span class="comp-step__line"></span>');
      const meta = [];
      if (c.track) meta.push(Utils.esc(c.track));
      if (c.prize_usd) meta.push('상금 ' + fmtUsd(c.prize_usd));
      if (c.deadline) meta.push('마감 ' + Utils.esc(c.deadline));
      if (c.team_count) meta.push('팀 ' + c.team_count);
      const descRaw = (c.description || '').split('\n').map(x => x.trim()).filter(x => x && x.charAt(0) !== '#' && x.indexOf('**Competition') !== 0)[0] || c.track || '';

      // Brev 학습 기록 패널 — nemotron 등 학습 대회에만
      let brev = '';
      const isBrev = training && (c.name === training.competition || (c.project_group || '').toLowerCase().indexOf('nemotron') !== -1);
      if (isBrev) {
        const t = training;
        const recent = (t.recent_runs || []).slice(0, 3).map(r => Utils.esc(String(r.version) + (r.gpu_id ? ' · gpu' + r.gpu_id : ''))).join('  ·  ');
        brev =
          '<div class="comp-brev">' +
          '  <div class="comp-brev__head">⚡ NVIDIA Brev 학습 기록</div>' +
          '  <div class="comp-brev__stats">' +
              statCell('학습 런', num(t.training_runs)) +
              statCell('제출', num(t.submissions)) +
              statCell('최고 점수', (t.best_public != null ? t.best_public : '-')) +
              statCell('학습 스텝', num(t.training_steps)) +
          '  </div>' +
          (recent ? '<div class="comp-brev__recent">최근 런: ' + recent + '</div>' : '') +
          '</div>';
      }

      const href = c.kaggle_url || c.writeup_url || '#';
      return '<a class="comp-card" href="' + href + '" target="_blank" rel="noopener noreferrer">' +
        '<div class="comp-card__top"><div>' +
        '  <div class="comp-card__track">' + Utils.esc(c.track || c.host || 'Competition') + '</div>' +
        '  <div class="comp-card__title">' + Utils.esc(title) + '</div>' +
        (c.host ? '  <div class="comp-card__host">' + Utils.esc(c.host) + '</div>' : '') +
        '</div><span class="comp-badge comp-badge--' + st.cls + '">' + Utils.esc(st.label) + '</span></div>' +
        (descRaw ? '<div class="comp-card__desc">' + Utils.esc(descRaw.slice(0, 160)) + '</div>' : '') +
        '<div class="comp-stepper">' + stepper + '</div>' +
        (meta.length ? '<div class="comp-tags">' + meta.map(m => '<span class="comp-tag">' + m + '</span>').join('') + '</div>' : '') +
        brev +
        '</a>';
    };

    const empty = '<div class="u-empty"><div class="u-empty__title">등록된 대회 없음</div><div class="u-empty__desc">설정에서 대회 디렉토리를 등록하세요</div></div>';
    mainEl.innerHTML =
      '<div class="shell-main__content">' +
      '  <div class="bill-toolbar"><h1 class="u-panel__title" style="font-size:var(--fs-xl);margin:0">대회 참가 현황</h1>' +
      '    <span class="u-badge" style="margin-left:8px">' + this._comps.length + ' Competitions</span></div>' +
      (this._comps.length ? '  <div class="comp-grid">' + this._comps.map(card).join('') + '</div>' : empty) +
      '</div>';
  }
};

if (typeof App !== 'undefined') App.registerView('competitions', CompetitionsView);
