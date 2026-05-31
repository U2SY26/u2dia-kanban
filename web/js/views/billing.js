/* U2DIA — Billing 뷰 (결제/청구 대시보드)
   정적 데이터 (SSE 없음). API.get + Charts(inline SVG) + billing.css 사용. */
const BillingView = {

  // ── 카테고리 → chart 색 매핑 ──────────────────────────────
  _catColor: {
    'auto-recharge':          'var(--chart-blue)',
    'credit-topup':           'var(--chart-purple)',
    'max-plan-subscription':  'var(--chart-green)',
    'max-plan-monthly':       'var(--chart-cyan)',
    'pro-plan':               'var(--chart-gray)',
    'promo':                  'var(--chart-yellow)'
  },

  // 클라이언트 필터 상태 (테이블)
  _filter: { status: 'all', category: 'all' },

  // 원본 데이터 캐시 (테이블 필터 재렌더용)
  _invoices: [],

  // 환율 (refresh 시 백엔드 응답으로 갱신)
  _krwRate: 1507,

  // ── 숫자 포맷 ─────────────────────────────────────────────
  _fmtUSD(n) {
    return '$' + (Number(n) || 0).toLocaleString('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  },

  // 원화 — 백엔드가 준 _krw 값 우선, 없으면 rate로 환산
  _fmtKRW(krw) {
    return '₩' + Math.round(Number(krw) || 0).toLocaleString('ko-KR');
  },
  _usdToKRW(usd) {
    return this._fmtKRW((Number(usd) || 0) * this._krwRate);
  },
  // 큰 금액 한글 축약 (억/만원)
  _fmtKRWShort(krw) {
    const v = Math.round(Number(krw) || 0);
    if (v >= 1e8) return (v / 1e8).toFixed(2).replace(/\.?0+$/, '') + '억원';
    if (v >= 1e4) return Math.round(v / 1e4).toLocaleString('ko-KR') + '만원';
    return '₩' + v.toLocaleString('ko-KR');
  },
  _fmtTok(n) {
    const v = Number(n) || 0;
    if (v >= 1e9) return (v / 1e9).toFixed(2) + 'B';
    if (v >= 1e6) return (v / 1e6).toFixed(1) + 'M';
    return v.toLocaleString('en-US');
  },

  _color(cat) {
    return this._catColor[cat] || 'var(--chart-gray)';
  },

  // ── 셸 ────────────────────────────────────────────────────
  async render(mainEl) {
    mainEl.innerHTML =
      '<div class="shell-main__content">' +
      '  <div class="bill-toolbar">' +
      '    <h1 class="u-panel__title" style="font-size:18px;margin:0">결제 대시보드</h1>' +
      '    <div class="bill-toolbar__spacer"></div>' +
      '    <button class="u-btn u-btn--sm u-btn--ghost" id="billRefreshBtn">' +
             Utils.icon('refresh', 14) + ' 새로고침</button>' +
      '  </div>' +
      '  <div id="billSubValue"></div>' +
      '  <div id="billKpiRow" class="bill-kpi-row"></div>' +
      '  <div id="billGrid" class="bill-grid"></div>' +
      '  <div id="billTrend" class="u-panel" style="margin-bottom:20px"></div>' +
      '  <div id="billAcctTokens" class="u-panel" style="margin-bottom:20px"></div>' +
      '  <div id="billTable" class="u-panel"></div>' +
      '</div>';

    const btn = mainEl.querySelector('#billRefreshBtn');
    if (btn) btn.addEventListener('click', () => this.refresh());

    await this.refresh();
  },

  // ── 데이터 로드 + 전체 렌더 ───────────────────────────────
  async refresh() {
    const kpiEl   = document.getElementById('billKpiRow');
    const gridEl  = document.getElementById('billGrid');
    const trendEl = document.getElementById('billTrend');
    const tableEl = document.getElementById('billTable');
    if (!kpiEl) return;

    const subEl = document.getElementById('billSubValue');

    let lifetime, months, categories, invoices, subval, acctTok;
    try {
      const [rl, rm, rc, ri, rs, ra] = await Promise.all([
        API.get('/api/billing/lifetime'),
        API.get('/api/billing/monthly'),
        API.get('/api/billing/categories'),
        API.get('/api/billing/invoices?limit=200'),
        API.get('/api/billing/subscription-value'),
        API.get('/api/billing/tokens-by-account?model=' + this._acctModel)
      ]);
      lifetime   = (rl && rl.lifetime) || {};
      months     = (rm && rm.months) || [];
      categories = (rc && rc.categories) || [];
      invoices   = (ri && ri.invoices) || [];
      subval     = rs || {};
      acctTok    = ra || {};
      if (rl && rl.krw_rate) this._krwRate = rl.krw_rate;
    } catch (e) {
      const err = '<div class="u-panel__body"><div class="u-empty">' +
        '<div class="u-empty__title">결제 데이터를 불러오지 못했습니다</div>' +
        '<div class="u-empty__desc">' + Utils.esc(e && e.message ? e.message : 'API 오류') + '</div>' +
        '</div></div>';
      kpiEl.innerHTML = '';
      gridEl.innerHTML = '';
      trendEl.innerHTML = err;
      tableEl.innerHTML = '';
      return;
    }

    this._invoices = invoices;

    if (subEl) this._renderSubValue(subEl, subval);
    this._renderKpi(kpiEl, lifetime, months);
    this._renderGrid(gridEl, months, categories);
    this._renderTrend(trendEl, months);
    this._renderAcctTokens(document.getElementById('billAcctTokens'), acctTok);
    this._renderTable(tableEl);
  },

  // ── 계정별(1/2/3) 토큰 소급 꺾은선 + 합계 (가로 스크롤) ────
  _acctModel: 'sonnet',
  _renderAcctTokens(el, data) {
    if (!el) return;
    if (!data || !data.months || !data.months.length) { el.innerHTML = ''; return; }

    const months = data.months;
    const accounts = data.accounts || {};
    const total = data.total || [];
    const acctKeys = Object.keys(accounts).sort();

    // 계정별 색
    const palette = {
      '1': 'var(--chart-blue)', '2': 'var(--chart-green)',
      '3': 'var(--chart-orange)', '4': 'var(--chart-purple)'
    };
    const series = acctKeys.map(a => ({
      label: '계정 ' + a,
      color: palette[a] || 'var(--chart-cyan)',
      points: accounts[a].map(p => p.tokens)
    }));
    // 합계 라인 (강조 + 점선)
    series.push({
      label: '합계',
      color: 'var(--text)',
      emphasis: true, dash: true,
      points: total.map(p => p.tokens)
    });

    // 가로 스크롤: 월당 80px 확보
    const chartW = Math.max(640, months.length * 80);
    const chart = SvgCharts.multiLine(series, {
      w: chartW, h: 320, xLabels: months.map(m => m.slice(2)),
      fmt: (v) => this._fmtTok(v)
    });

    // 범례 + 모델 토글
    const legend = series.map(s =>
      '<span class="bill-legend__item">' +
        '<span class="bill-legend__dot" style="background:' + s.color +
          (s.dash ? ';outline:1px dashed var(--muted)' : '') + '"></span>' +
        Utils.esc(s.label) + '</span>'
    ).join('');

    const seg = ['sonnet', 'opus'].map(m =>
      '<button class="bill-seg__btn' + (this._acctModel === m ? ' bill-seg__btn--active' : '') +
        '" data-acct-model="' + m + '">' + (m === 'opus' ? 'Opus' : 'Sonnet') + '</button>'
    ).join('');

    const totalTok = total.reduce((a, p) => a + p.tokens, 0);

    el.innerHTML =
      '<div class="u-panel__header">' +
        '<h2 class="u-panel__title">계정별 토큰 소급 추이</h2>' +
        '<div class="bill-seg">' + seg + '</div>' +
      '</div>' +
      '<div class="u-panel__body">' +
        '<div class="bill-acct-meta">' +
          '결제량을 토큰으로 소급 환산 (' + Utils.esc(data.model) + ' ' +
          (data.tokens_per_usd / 1e6) + 'M/$, MAX 구독은 풀사용 보정) · ' +
          '전체 합계 <b style="color:var(--text)">' + this._fmtTok(totalTok) + '</b> · ' +
          months.length + '개월 · 가로 스크롤 →' +
        '</div>' +
        '<div class="bill-scroll">' +
          '<div class="bill-chart-wrap" style="justify-content:flex-start">' + chart + '</div>' +
        '</div>' +
        '<div class="bill-legend">' + legend + '</div>' +
      '</div>';

    // 모델 토글 바인딩
    el.querySelectorAll('[data-acct-model]').forEach(btn => {
      btn.addEventListener('click', async () => {
        this._acctModel = btn.getAttribute('data-acct-model');
        const ra = await API.get('/api/billing/tokens-by-account?model=' + this._acctModel);
        this._renderAcctTokens(el, ra);
      });
    });
  },

  // ── 0. MAX 구독 소급 역산 (hero) ──────────────────────────
  _renderSubValue(el, sv) {
    if (!sv || !sv.subscription) { el.innerHTML = ''; return; }
    const s = sv.subscription, t = sv.total, a = sv.addon, asm = sv.assumptions || {};
    el.innerHTML =
      '<div class="bill-hero">' +
        '<div class="bill-hero__head">' +
          '<span class="bill-hero__badge">MAX 구독 소급 역산</span>' +
          '<span class="bill-hero__assume">' +
            Utils.esc(asm.accounts + '계정 × Max 20x × ' + asm.months + '개월 풀사용 · 환율 ₩' +
              Number(sv.krw_rate).toLocaleString('ko-KR')) +
          '</span>' +
        '</div>' +
        '<div class="bill-hero__grid">' +
          this._heroCard('MAX 구독 API 환산 가치', this._fmtKRWShort(s.api_value_krw),
            this._fmtUSD(s.api_value_usd) + ' · 정액 구독으로 뽑아낸 값', 'accent') +
          this._heroCard('실제 구독 지출', this._fmtKRWShort(s.sub_paid_krw),
            this._fmtUSD(s.sub_paid_usd) + ' (₩' + Math.round(asm.sub_paid_per_acct_month * sv.krw_rate).toLocaleString('ko-KR') + '/월·계정)', '') +
          this._heroCard('레버리지', s.leverage_x + '배',
            this._fmtKRWShort(s.saved_krw) + ' 절감', 'success') +
          this._heroCard('확보 총가치', this._fmtKRWShort(t.value_krw),
            '구독 + 애드온 크레딧 합산', 'accent') +
        '</div>' +
        '<div class="bill-hero__foot">' +
          '<div class="bill-hero__tok">' +
            '<span class="bill-hero__tok-label">MAX 추정 토큰(소급)</span>' +
            '<b>' + this._fmtTok(s.eff_tokens) + '</b> <span class="bill-hero__tok-sub">유효(캐시포함)</span>' +
            ' · <b>' + this._fmtTok(s.net_tokens) + '</b> <span class="bill-hero__tok-sub">순(입출력)</span>' +
          '</div>' +
          '<div class="bill-hero__tok">' +
            '<span class="bill-hero__tok-label">애드온 토큰</span>' +
            '<b>' + this._fmtTok(a.addon_tokens_sonnet) + '</b> <span class="bill-hero__tok-sub">Sonnet 환산</span>' +
            ' · 합계 <b>' + this._fmtTok(t.est_tokens_eff) + '</b>' +
          '</div>' +
        '</div>' +
        '<div class="bill-hero__note">※ API 환산 가치 = Max 20x 풀사용 시 동일 사용량을 API로 결제했을 때 비용($' +
          Number(asm.full_api_usd_per_acct_month).toLocaleString('en-US') +
          '/월·계정, 업계 실측 기준). 토큰은 blended 단가 역산 추정치.</div>' +
      '</div>';
  },

  _heroCard(label, big, sub, mod) {
    return '<div class="bill-hero__card' + (mod ? ' bill-hero__card--' + mod : '') + '">' +
      '<div class="bill-hero__card-label">' + Utils.esc(label) + '</div>' +
      '<div class="bill-hero__card-value">' + Utils.esc(big) + '</div>' +
      '<div class="bill-hero__card-sub">' + Utils.esc(sub) + '</div>' +
    '</div>';
  },

  // ── 1. KPI Row ────────────────────────────────────────────
  _renderKpi(el, lt, months) {
    const last = months.length ? months[months.length - 1] : null;
    const prev = months.length > 1 ? months[months.length - 2] : null;

    // 최근 6개월 total_paid 배열 (sparkline)
    const spark6 = months.slice(-6).map(m => Number(m.total_paid_usd) || 0);

    // 전월대비 증감 %
    let deltaSub = '<span style="color:var(--muted)">전월 데이터 없음</span>';
    if (last && prev && Number(prev.total_paid_usd) > 0) {
      const cur = Number(last.total_paid_usd) || 0;
      const pre = Number(prev.total_paid_usd) || 0;
      const pct = ((cur - pre) / pre) * 100;
      const up = pct >= 0;
      // 양수 = 비용 증가 = 빨강, 음수 = 초록
      const color = up ? 'var(--red-light)' : 'var(--green)';
      const arrow = up ? '▲' : '▼';
      deltaSub = '<span style="color:' + color + ';font-weight:600">' + arrow + ' ' +
        Math.abs(pct).toFixed(1) + '%</span> <span style="color:var(--muted)">전월대비</span>';
    }

    const krwTag = (usd, krwField) => {
      const krw = (krwField != null) ? krwField : (Number(usd) || 0) * this._krwRate;
      return '<span style="color:var(--brand-light);font-weight:600">' + this._fmtKRW(krw) + '</span>';
    };
    const lastKrw = last ? (last.total_paid_krw != null ? last.total_paid_krw : Number(last.total_paid_usd) * this._krwRate) : 0;

    const cards = [
      {
        label: '누적 결제액',
        value: this._fmtUSD(lt.lifetime_paid_usd),
        sub: krwTag(lt.lifetime_paid_usd, lt.lifetime_paid_krw) +
             ' <span style="color:var(--muted)">· ' + (lt.active_months || 0) + '개월 ' + (lt.total_payments || 0) + '건</span>',
        mod: ''
      },
      {
        label: '이번 달',
        value: this._fmtUSD(last ? last.total_paid_usd : 0),
        sub: krwTag(last ? last.total_paid_usd : 0, lastKrw) + ' · ' + deltaSub,
        mod: ' bill-kpi--accent'
      },
      {
        label: '애드온 크레딧 누적',
        value: this._fmtUSD(lt.lifetime_addon_usd),
        sub: krwTag(lt.lifetime_addon_usd, lt.lifetime_addon_krw) +
             ' <span style="color:var(--muted)">· 토큰 추정 근거</span>',
        mod: ''
      },
      {
        label: '환불 누적',
        value: this._fmtUSD(lt.lifetime_refunded_usd),
        sub: krwTag(lt.lifetime_refunded_usd, lt.lifetime_refunded_krw) +
             ' <span style="color:var(--muted)">· 환불 합계</span>',
        mod: ' bill-kpi--danger'
      },
      {
        label: '월평균',
        value: this._fmtUSD(lt.avg_per_active_month),
        sub: krwTag(lt.avg_per_active_month, lt.avg_per_active_month_krw) +
             ' <span style="color:var(--muted)">· 활성 월 평균</span>',
        mod: ''
      }
    ];

    const sparkSvg = spark6.length > 1
      ? '<div class="bill-kpi__spark">' +
          SvgCharts.sparkline(spark6, { w: 160, h: 30, stroke: 'var(--brand)' }) +
        '</div>'
      : '';

    el.innerHTML = cards.map(c =>
      '<div class="bill-kpi' + c.mod + '">' +
        '<div class="bill-kpi__label">' + Utils.esc(c.label) + '</div>' +
        '<div class="bill-kpi__value">' + Utils.esc(c.value) + '</div>' +
        '<div class="bill-kpi__sub">' + c.sub + '</div>' +
        sparkSvg +
      '</div>'
    ).join('');
  },

  // ── 2. 2컬럼 그리드 (월별 추세 + 카테고리 분해) ───────────
  _renderGrid(el, months, categories) {
    // 좌: 월별 누적 막대 (구독 + 애드온) — 최근 12개월
    const rows = months.slice(-12).map(m => ({
      label: String(m.month || '').slice(2),  // YYYY-MM → YY-MM
      subscription_usd: Number(m.subscription_usd) || 0,
      addon_credit_usd: Number(m.addon_credit_usd) || 0
    }));

    const stacked = rows.length
      ? SvgCharts.stackedBars(rows, [
          { key: 'subscription_usd', label: '구독',   color: 'var(--chart-purple)' },
          { key: 'addon_credit_usd', label: '애드온', color: 'var(--chart-blue)' }
        ], { w: 560, h: 280, fmt: SvgCharts.fmt.usd })
      : '<div class="u-empty"><div class="u-empty__title">데이터 없음</div></div>';

    // 우: 카테고리 도넛
    const segs = (categories || [])
      .filter(c => Number(c.total) > 0)
      .map(c => ({
        label: c.category,
        value: Number(c.total) || 0,
        color: this._color(c.category)
      }));

    const donut = segs.length
      ? SvgCharts.donut(segs, { size: 200 })
      : '<div class="u-empty"><div class="u-empty__title">데이터 없음</div></div>';

    const legend = segs.length
      ? '<div class="bill-legend">' + segs.map(s =>
          '<span class="bill-legend__item">' +
            '<span class="bill-legend__dot" style="background:' + s.color + '"></span>' +
            Utils.esc(s.label) + ' · ' + this._fmtUSD(s.value) +
          '</span>'
        ).join('') + '</div>'
      : '';

    el.innerHTML =
      '<div class="u-panel bill-chart-panel">' +
        '<div class="u-panel__header"><h2 class="u-panel__title">월별 결제 추세</h2></div>' +
        '<div class="u-panel__body">' +
          '<div class="bill-chart-wrap">' + stacked + '</div>' +
        '</div>' +
      '</div>' +
      '<div class="u-panel bill-chart-panel">' +
        '<div class="u-panel__header"><h2 class="u-panel__title">카테고리 분해</h2></div>' +
        '<div class="u-panel__body">' +
          '<div class="bill-chart-wrap">' + donut + '</div>' +
          legend +
        '</div>' +
      '</div>';
  },

  // ── 3. 월별 추세 timeseries (full width) ──────────────────
  _renderTrend(el, months) {
    const points = (months || []).map(m => ({
      x: String(m.month || '').slice(2),
      y: Number(m.total_paid_usd) || 0
    }));

    const chart = points.length > 1
      ? SvgCharts.timeseries(points, { w: 1100, h: 260, stroke: 'var(--chart-blue)', area: true, fmt: SvgCharts.fmt.usd })
      : '<div class="u-empty"><div class="u-empty__title">데이터 없음</div></div>';

    el.innerHTML =
      '<div class="u-panel__header"><h2 class="u-panel__title">월별 결제 추이</h2></div>' +
      '<div class="u-panel__body">' +
        '<div class="bill-chart-wrap">' + chart + '</div>' +
      '</div>';
  },

  // ── 4. 청구 내역 테이블 (클라이언트 필터링) ───────────────
  _renderTable(el) {
    // 필터 옵션 — 카테고리 목록 추출
    const cats = Array.from(new Set(this._invoices.map(i => i.category).filter(Boolean))).sort();

    const statusBtns = [
      { key: 'all',      label: '전체' },
      { key: 'Paid',     label: 'Paid' },
      { key: 'Refunded', label: 'Refunded' }
    ];

    const segHtml =
      '<div class="bill-seg">' + statusBtns.map(b =>
        '<button class="bill-seg__btn' +
          (this._filter.status === b.key ? ' bill-seg__btn--active' : '') +
          '" data-status="' + b.key + '">' + Utils.esc(b.label) + '</button>'
      ).join('') + '</div>';

    const catSelect =
      '<select id="billCatFilter">' +
        '<option value="all"' + (this._filter.category === 'all' ? ' selected' : '') + '>모든 카테고리</option>' +
        cats.map(c =>
          '<option value="' + Utils.esc(c) + '"' +
            (this._filter.category === c ? ' selected' : '') + '>' + Utils.esc(c) + '</option>'
        ).join('') +
      '</select>';

    el.innerHTML =
      '<div class="u-panel__header"><h2 class="u-panel__title">청구 내역</h2></div>' +
      '<div class="u-panel__body">' +
        '<div class="bill-toolbar">' +
          segHtml +
          '<div class="bill-toolbar__spacer"></div>' +
          catSelect +
        '</div>' +
        '<div id="billTableBody"></div>' +
      '</div>';

    // 이벤트 바인딩
    el.querySelectorAll('.bill-seg__btn').forEach(btn => {
      btn.addEventListener('click', () => {
        this._filter.status = btn.getAttribute('data-status');
        el.querySelectorAll('.bill-seg__btn').forEach(b =>
          b.classList.toggle('bill-seg__btn--active', b === btn));
        this._renderTableBody();
      });
    });
    const sel = el.querySelector('#billCatFilter');
    if (sel) sel.addEventListener('change', () => {
      this._filter.category = sel.value;
      this._renderTableBody();
    });

    this._renderTableBody();
  },

  _renderTableBody() {
    const body = document.getElementById('billTableBody');
    if (!body) return;

    const f = this._filter;
    let rows = this._invoices.filter(inv => {
      if (f.status !== 'all' && inv.status !== f.status) return false;
      if (f.category !== 'all' && inv.category !== f.category) return false;
      return true;
    });

    // 최신순 정렬
    rows = rows.slice().sort((a, b) =>
      String(b.invoice_date || '').localeCompare(String(a.invoice_date || '')));

    if (!rows.length) {
      body.innerHTML = '<div class="u-empty"><div class="u-empty__title">해당 조건의 내역 없음</div></div>';
      return;
    }

    const badge = (status) => {
      const s = String(status || '').toLowerCase();
      let cls = 'bill-badge';
      if (s === 'paid') cls += ' bill-badge--paid';
      else if (s === 'refunded') cls += ' bill-badge--refunded';
      else if (s === 'partial' || s.indexOf('partial') >= 0) cls += ' bill-badge--partial';
      return '<span class="' + cls + '">' + Utils.esc(status || '-') + '</span>';
    };

    const catTag = (cat) =>
      '<span class="bill-cat-tag" style="--dot:' + this._color(cat) + '">' +
        Utils.esc(cat || '-') +
      '</span>';

    const trs = rows.map(inv =>
      '<tr>' +
        '<td>' + Utils.esc(inv.invoice_date || '-') + '</td>' +
        '<td class="bill-num">' + this._fmtUSD(inv.amount_usd) + '</td>' +
        '<td>' + badge(inv.status) + '</td>' +
        '<td>' + catTag(inv.category) + '</td>' +
      '</tr>'
    ).join('');

    body.innerHTML =
      '<table class="bill-table">' +
        '<thead><tr>' +
          '<th>날짜</th>' +
          '<th style="text-align:right">금액</th>' +
          '<th>상태</th>' +
          '<th>카테고리</th>' +
        '</tr></thead>' +
        '<tbody>' + trs + '</tbody>' +
      '</table>' +
      '<div style="padding:10px 12px;font-size:12px;color:var(--muted)">' +
        rows.length + '건 표시' +
      '</div>';
  }
};

if (typeof App !== 'undefined') App.registerView('billing', BillingView);
