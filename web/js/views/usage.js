/* U2DIA — Usage 뷰 (토큰 사용량 추정 대시보드)
   Anthropic 청구 애드온 크레딧($)을 모델 평균 단가로 역산한 추정 토큰량.
   정적 데이터 (SSE 없음). API.get + Charts(inline SVG) + billing.css 재사용.
   주의: 실제 token_usage 테이블이 아닌 청구 기반 역산치. */
const UsageView = {

  // 선택된 모델 시나리오 ('sonnet' | 'opus')
  _model: 'sonnet',

  // 마지막으로 로드한 데이터 캐시
  _data: null,          // 선택 모델 /api/billing/tokens 응답
  _compare: null,       // { sonnet:{...}, opus:{...} } 비교용

  // 모델별 강조 색
  _modelColor: {
    sonnet: 'var(--chart-blue)',
    opus:   'var(--chart-purple)'
  },

  // ── 토큰 포맷 ─────────────────────────────────────────────
  _fmtTok(n) {
    const v = Number(n) || 0;
    const a = Math.abs(v);
    if (a >= 1e9) return (v / 1e9).toFixed(2) + 'B';
    if (a >= 1e6) return (v / 1e6).toFixed(2) + 'M';
    if (a >= 1e3) return Math.round(v).toLocaleString('en-US');
    return String(Math.round(v));
  },

  // tokens_per_usd 환산율 표기 (1500000 → 1.5M)
  _fmtRate(n) {
    const v = Number(n) || 0;
    if (v >= 1e6) return (v / 1e6).toFixed(v % 1e6 === 0 ? 0 : 1) + 'M';
    if (v >= 1e3) return (v / 1e3).toFixed(0) + 'K';
    return String(v);
  },

  _fmtUSD(n) {
    return '$' + (Number(n) || 0).toLocaleString('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  },

  _color(model) {
    return this._modelColor[model] || 'var(--chart-gray)';
  },

  // ── 셸 ────────────────────────────────────────────────────
  async render(mainEl) {
    mainEl.innerHTML =
      '<div class="shell-main__content">' +
      '  <div class="bill-toolbar">' +
      '    <h1 class="u-panel__title" style="font-size:18px;margin:0">토큰 사용량 (추정)</h1>' +
      '    <div class="bill-toolbar__spacer"></div>' +
      '    <div class="bill-seg" id="usageModelSeg">' +
      '      <button class="bill-seg__btn" data-model="sonnet">Sonnet</button>' +
      '      <button class="bill-seg__btn" data-model="opus">Opus</button>' +
      '    </div>' +
      '    <button class="u-btn u-btn--sm u-btn--ghost" id="usageRefreshBtn">' +
             Utils.icon('refresh', 14) + ' 새로고침</button>' +
      '  </div>' +
      '  <div id="usageNote"></div>' +
      '  <div id="usageKpiRow" class="bill-kpi-row"></div>' +
      '  <div id="usageTrend" class="u-panel" style="margin-bottom:20px"></div>' +
      '  <div id="usageCompare" class="u-panel" style="margin-bottom:20px"></div>' +
      '  <div id="usageReal"></div>' +
      '</div>';

    // 모델 토글
    const seg = mainEl.querySelector('#usageModelSeg');
    if (seg) {
      seg.querySelectorAll('.bill-seg__btn').forEach(btn => {
        btn.addEventListener('click', () => {
          const m = btn.getAttribute('data-model');
          if (!m || m === this._model) return;
          this._model = m;
          this.refresh();
        });
      });
    }

    const btn = mainEl.querySelector('#usageRefreshBtn');
    if (btn) btn.addEventListener('click', () => this.refresh());

    await this.refresh();
  },

  // 토글 active 상태 동기화
  _syncSeg() {
    document.querySelectorAll('#usageModelSeg .bill-seg__btn').forEach(b =>
      b.classList.toggle('bill-seg__btn--active',
        b.getAttribute('data-model') === this._model));
  },

  // ── 데이터 로드 + 전체 렌더 ───────────────────────────────
  async refresh() {
    const noteEl    = document.getElementById('usageNote');
    const kpiEl     = document.getElementById('usageKpiRow');
    const trendEl   = document.getElementById('usageTrend');
    const compareEl = document.getElementById('usageCompare');
    const realEl    = document.getElementById('usageReal');
    if (!kpiEl) return;

    this._syncSeg();

    let data;
    try {
      // 선택 모델 + 비교용 양쪽 모델 동시 fetch
      const [rSel, rSonnet, rOpus] = await Promise.all([
        API.get('/api/billing/tokens?model=' + encodeURIComponent(this._model)),
        API.get('/api/billing/tokens?model=sonnet'),
        API.get('/api/billing/tokens?model=opus')
      ]);
      if (!rSel || rSel.ok === false) throw new Error((rSel && rSel.message) || 'API 오류');
      data = rSel;
      this._data = data;
      this._compare = {
        sonnet: rSonnet && rSonnet.ok !== false ? rSonnet : null,
        opus:   rOpus   && rOpus.ok   !== false ? rOpus   : null
      };
    } catch (e) {
      const err = '<div class="u-panel__body"><div class="u-empty">' +
        '<div class="u-empty__title">사용량 데이터를 불러오지 못했습니다</div>' +
        '<div class="u-empty__desc">' + Utils.esc(e && e.message ? e.message : 'API 오류') + '</div>' +
        '</div></div>';
      if (noteEl)    noteEl.innerHTML = '';
      kpiEl.innerHTML = '';
      trendEl.innerHTML = err;
      if (compareEl) compareEl.innerHTML = '';
      if (realEl)    realEl.innerHTML = '';
      return;
    }

    this._renderNote(noteEl, data);
    this._renderKpi(kpiEl, data);
    this._renderTrend(trendEl, data);
    this._renderCompare(compareEl);
    this._renderReal(realEl);   // 비동기 — 실패 시 자체 생략
  },

  // ── 0. 안내 박스 (info note) ──────────────────────────────
  _renderNote(el, data) {
    if (!el) return;
    const label = data.label || (this._model === 'opus' ? 'Claude Opus' : 'Claude Sonnet');
    const rate = this._fmtRate(data.tokens_per_usd);
    el.innerHTML =
      '<div style="display:flex;gap:10px;align-items:flex-start;' +
        'background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--orange);' +
        'border-radius:8px;padding:12px 14px;margin-bottom:18px;font-size:13px;line-height:1.6;' +
        'color:var(--text-secondary)">' +
        '<span style="flex-shrink:0;margin-top:1px">' + Utils.icon('alert', 16) + '</span>' +
        '<span>이 수치는 청구 애드온 크레딧을 모델 평균 단가(<b style="color:var(--text)">' +
          Utils.esc(label) + ' · ' + rate + ' tok/$</b>)로 나눈 <b style="color:var(--orange)">추정치</b>입니다. ' +
          '실제 token_usage 테이블의 측정값이 아니라 결제 금액 기반 역산값이며, ' +
          '모델 가정에 따라 토큰량이 크게 달라집니다.</span>' +
      '</div>';
  },

  // ── 1. KPI Row ────────────────────────────────────────────
  _renderKpi(el, data) {
    const monthly = data.monthly || [];
    const last = monthly.length ? monthly[monthly.length - 1] : null;
    const lifetimeTok = Number(data.lifetime_est_tokens) || 0;
    const monthTok = last ? (Number(last.est_tokens) || 0) : 0;
    const addonUsd = Number(data.lifetime_addon_usd) || 0;
    const dailyTok = monthTok / 30;
    const accent = this._color(this._model);

    // 최근 6개월 추정 토큰 (sparkline)
    const spark6 = monthly.slice(-6).map(m => Number(m.est_tokens) || 0);
    const sparkSvg = spark6.length > 1
      ? '<div class="bill-kpi__spark">' +
          SvgCharts.sparkline(spark6, { w: 160, h: 30, stroke: accent }) +
        '</div>'
      : '';

    const cards = [
      {
        label: '누적 추정 토큰',
        value: this._fmtTok(lifetimeTok),
        sub: '애드온 ' + this._fmtUSD(addonUsd) + ' 기준',
        mod: ' bill-kpi--accent',
        spark: true
      },
      {
        label: '이번 달 추정 토큰',
        value: this._fmtTok(monthTok),
        sub: last ? (Utils.esc(last.month) + ' · ' + this._fmtUSD(last.addon_usd)) : '데이터 없음',
        mod: '',
        spark: false
      },
      {
        label: '환산율 (가정)',
        value: this._fmtRate(data.tokens_per_usd) + ' tok/$',
        sub: Utils.esc(data.label || this._model),
        mod: '',
        spark: false
      },
      {
        label: '일평균 추정',
        value: this._fmtTok(dailyTok),
        sub: '이번 달 ÷ 30일',
        mod: '',
        spark: false
      }
    ];

    el.innerHTML = cards.map(c =>
      '<div class="bill-kpi' + c.mod + '">' +
        '<div class="bill-kpi__label">' + Utils.esc(c.label) + '</div>' +
        '<div class="bill-kpi__value">' + Utils.esc(c.value) + '</div>' +
        '<div class="bill-kpi__sub">' + c.sub + '</div>' +
        (c.spark ? sparkSvg : '') +
      '</div>'
    ).join('');
  },

  // ── 2. 월별 추정 토큰 막대 (full width) ────────────────────
  _renderTrend(el, data) {
    const monthly = data.monthly || [];
    const accent = this._color(this._model);

    const rows = monthly.map(m => ({
      label: String(m.month || '').slice(2),  // YYYY-MM → YY-MM
      value: Number(m.est_tokens) || 0,
      color: accent
    }));

    const chart = rows.length
      ? SvgCharts.bars(rows, {
          w: 1100, h: 300,
          fmt: (v) => this._fmtTok(v),
          maxBars: 24
        })
      : '<div class="u-empty"><div class="u-empty__title">데이터 없음</div></div>';

    el.innerHTML =
      '<div class="u-panel__header"><h2 class="u-panel__title">월별 추정 토큰</h2></div>' +
      '<div class="u-panel__body">' +
        '<div class="bill-chart-wrap">' + chart + '</div>' +
      '</div>';
  },

  // ── 3. Sonnet vs Opus 비교 ────────────────────────────────
  _renderCompare(el) {
    if (!el) return;
    const cmp = this._compare || {};
    const sonnet = cmp.sonnet;
    const opus = cmp.opus;

    if (!sonnet && !opus) {
      el.innerHTML =
        '<div class="u-panel__header"><h2 class="u-panel__title">Sonnet vs Opus</h2></div>' +
        '<div class="u-panel__body"><div class="u-empty">' +
          '<div class="u-empty__title">비교 데이터 없음</div></div></div>';
      return;
    }

    const sTok = sonnet ? (Number(sonnet.lifetime_est_tokens) || 0) : 0;
    const oTok = opus   ? (Number(opus.lifetime_est_tokens)   || 0) : 0;

    // 누적 토큰 비교 막대 2개
    const rows = [
      { label: 'Sonnet', value: sTok, color: this._modelColor.sonnet },
      { label: 'Opus',   value: oTok, color: this._modelColor.opus }
    ];
    const chart = (sTok > 0 || oTok > 0)
      ? SvgCharts.bars(rows, { w: 520, h: 240, fmt: (v) => this._fmtTok(v), maxBars: 2 })
      : '<div class="u-empty"><div class="u-empty__title">데이터 없음</div></div>';

    // 비율 설명 (같은 애드온 $ 기준이므로 토큰 배수 = 단가 배수)
    let ratioTxt = '';
    if (sTok > 0 && oTok > 0) {
      const ratio = sTok / oTok;
      ratioTxt =
        '동일한 애드온 크레딧이라도 <b style="color:var(--chart-blue)">Sonnet</b> 가정이 ' +
        '<b style="color:var(--chart-purple)">Opus</b> 가정보다 약 ' +
        '<b style="color:var(--text)">' + ratio.toFixed(1) + '배</b> 많은 토큰으로 추정됩니다. ' +
        '단가가 낮을수록(tok/$ 높을수록) 같은 금액으로 더 많은 토큰을 환산합니다.';
    } else {
      ratioTxt = '한쪽 모델의 추정 데이터가 없어 배수를 계산할 수 없습니다.';
    }

    const rateLine = (r, name, key) =>
      '<div style="display:flex;justify-content:space-between;padding:6px 0;' +
        'border-bottom:1px solid var(--line);font-size:13px">' +
        '<span style="display:inline-flex;align-items:center;gap:7px;color:var(--text)">' +
          '<span style="width:9px;height:9px;border-radius:50%;background:' +
            this._modelColor[key] + ';display:inline-block"></span>' + name + '</span>' +
        '<span style="color:var(--text-secondary)">' +
          (r ? this._fmtRate(r.tokens_per_usd) + ' tok/$ · 누적 ' + this._fmtTok(r.lifetime_est_tokens)
             : '데이터 없음') +
        '</span>' +
      '</div>';

    el.innerHTML =
      '<div class="u-panel__header"><h2 class="u-panel__title">Sonnet vs Opus 시나리오 비교</h2></div>' +
      '<div class="u-panel__body">' +
        '<div style="display:flex;flex-wrap:wrap;gap:24px;align-items:center">' +
          '<div class="bill-chart-wrap" style="flex:0 0 auto">' + chart + '</div>' +
          '<div style="flex:1 1 260px;min-width:240px">' +
            rateLine(sonnet, 'Claude Sonnet (balanced)', 'sonnet') +
            rateLine(opus,   'Claude Opus (balanced)',   'opus') +
            '<p style="margin:14px 0 0;font-size:13px;line-height:1.65;color:var(--text-secondary)">' +
              ratioTxt + '</p>' +
          '</div>' +
        '</div>' +
      '</div>';
  },

  // ── 4. (선택) 실제 측정 token_usage 비교 ──────────────────
  async _renderReal(el) {
    if (!el) return;
    el.innerHTML = '';   // 기본 비표시 — 데이터 있을 때만 채움

    let real;
    try {
      real = await API.get('/api/usage/global');
    } catch (e) {
      return;  // 실패 시 섹션 생략
    }
    if (!real || real.ok === false) return;

    // 응답 구조가 환경마다 다를 수 있어 방어적으로 토큰 합산
    const totalTokens = Number(
      real.total_tokens != null ? real.total_tokens :
      (real.totals && real.totals.total_tokens) != null ? real.totals.total_tokens :
      ((Number(real.input_tokens) || 0) + (Number(real.output_tokens) || 0))
    ) || 0;

    if (totalTokens <= 0) return;  // 기록된 실측 토큰 없으면 생략

    const estTok = this._data ? (Number(this._data.lifetime_est_tokens) || 0) : 0;

    const rows = [
      { label: '실측(token_usage)', value: totalTokens, color: 'var(--chart-green)' },
      { label: '추정(' + (this._model === 'opus' ? 'Opus' : 'Sonnet') + ')',
        value: estTok, color: this._color(this._model) }
    ];
    const chart = SvgCharts.bars(rows, { w: 520, h: 240, fmt: (v) => this._fmtTok(v), maxBars: 2 });

    let note = '실제 기록된 token_usage 합계와 청구 기반 추정치를 나란히 비교합니다.';
    if (estTok > 0 && totalTokens > 0) {
      const diffPct = ((estTok - totalTokens) / totalTokens) * 100;
      const dir = diffPct >= 0 ? '많습니다' : '적습니다';
      note += ' 추정치가 실측 대비 약 <b style="color:var(--text)">' +
        Math.abs(diffPct).toFixed(0) + '%</b> ' + dir + '.';
    }

    el.innerHTML =
      '<div class="u-panel">' +
        '<div class="u-panel__header"><h2 class="u-panel__title">실측 vs 추정</h2></div>' +
        '<div class="u-panel__body">' +
          '<div style="display:flex;flex-wrap:wrap;gap:24px;align-items:center">' +
            '<div class="bill-chart-wrap" style="flex:0 0 auto">' + chart + '</div>' +
            '<div style="flex:1 1 260px;min-width:240px">' +
              '<div style="font-size:13px;color:var(--text-secondary);margin-bottom:8px">' +
                '실측 합계: <b style="color:var(--green)">' + this._fmtTok(totalTokens) + '</b> 토큰</div>' +
              '<div style="font-size:13px;color:var(--text-secondary);margin-bottom:12px">' +
                '추정 합계: <b style="color:' + this._color(this._model) + '">' +
                this._fmtTok(estTok) + '</b> 토큰</div>' +
              '<p style="margin:0;font-size:13px;line-height:1.65;color:var(--text-secondary)">' +
                note + '</p>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>';
  }
};

if (typeof App !== 'undefined') App.registerView('usage', UsageView);
