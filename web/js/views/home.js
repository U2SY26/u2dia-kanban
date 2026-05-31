/* U2DIA 재설계 — Home 뷰 (2026-04-17) */
const HomeView = {
  _feedItems: [],
  _sseBound: false,

  async renderList(listEl) {
    /* 홈 섹션에서는 좌측 목록을 접는다 (중복 제거 — 섹션 레일로 이미 이동 가능) */
    listEl.innerHTML =
      '<div class="shell-list__header"><span class="shell-list__title">\ub300\uc2dc\ubcf4\ub4dc</span></div>' +
      '<div class="shell-list__body">' +
      '<div class="u-list-item u-list-item--active"><span>\uc804\uccb4 \ud604\ud669</span></div>' +
      '</div>';
  },

  async render(mainEl) {
    mainEl.innerHTML =
      '<div class="shell-main__content home-row">' +
      '  <div id="homeWelcome" class="home-welcome"></div>' +
      '  <div id="homeYudiCard" class="u-panel"></div>' +              // 비용·사용량 — 전체폭
      '  <div id="homeTopRow" class="home-grid-half">' +
      '    <div id="homeTeamsCard" class="u-panel"></div>' +           // 진행 현황 (운영)
      '    <div id="homeYudiMetricsCard" class="u-panel home-yudi-metrics-panel"></div>' +  // 시스템·GPU
      '  </div>' +
      '  <div id="homeLowerRow" class="home-grid-bottom">' +
      '    <div id="homeFeedCard" class="u-panel"></div>' +
      '    <div id="homeHeatmapCard" class="u-panel"></div>' +
      '  </div>' +
      '  <div id="homeRecognitionCard" class="u-panel home-recognition-panel"></div>' +  // 스타트업 쇼케이스 (하단)
      '</div>';
    await this.refresh();
    this._bindSse();
    this._startMetricsPoll();
  },

  async refresh() {
    this._renderWelcome();
    await Promise.all([
      this._renderYudi(),
      this._renderYudiMetrics(),
      this._renderTeams(),
      this._renderHeatmap()
    ]);
    this._renderRecognition();
    this._renderFeed();
  },

  // 브랜드 인라인 SVG 로고 (외부 의존성 0 · 다크테마 대비 보장 · 벡터 선명)
  _partnerLogo(key) {
    const L = {
      nvidia:
        '<svg class="home-recognition__logo-svg" viewBox="0 0 220 48" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="NVIDIA">' +
        '<text x="110" y="33" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-size="28" font-weight="800" fill="#76B900" letter-spacing="1.5">NVIDIA</text></svg>',
      aws:
        '<svg class="home-recognition__logo-svg" viewBox="0 0 200 60" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="AWS">' +
        '<text x="100" y="30" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-size="30" font-weight="800" fill="#FF9900" letter-spacing="3">aws</text>' +
        '<path d="M66 42 C 84 53, 116 53, 134 42" fill="none" stroke="#FF9900" stroke-width="4" stroke-linecap="round"/>' +
        '<path d="M129 38 l7 4 -5 6" fill="none" stroke="#FF9900" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
      microsoft:
        '<svg class="home-recognition__logo-svg" viewBox="0 0 230 48" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Microsoft">' +
        '<rect x="42" y="13" width="11" height="11" fill="#F25022"/><rect x="55" y="13" width="11" height="11" fill="#7FBA00"/>' +
        '<rect x="42" y="26" width="11" height="11" fill="#00A4EF"/><rect x="55" y="26" width="11" height="11" fill="#FFB900"/>' +
        '<text x="74" y="33" font-family="Segoe UI,Arial,sans-serif" font-size="22" font-weight="600" fill="#E8EAED">Microsoft</text></svg>',
      google:
        '<svg class="home-recognition__logo-svg" viewBox="0 0 240 48" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Google Cloud">' +
        '<text x="18" y="33" font-family="Arial,Helvetica,sans-serif" font-size="24" font-weight="700">' +
        '<tspan fill="#4285F4">G</tspan><tspan fill="#EA4335">o</tspan><tspan fill="#FBBC05">o</tspan>' +
        '<tspan fill="#4285F4">g</tspan><tspan fill="#34A853">l</tspan><tspan fill="#EA4335">e</tspan>' +
        '<tspan fill="#9AA0A6" dx="7">Cloud</tspan></text></svg>',
      lambda:
        '<svg class="home-recognition__logo-svg" viewBox="0 0 200 48" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Lambda">' +
        '<text x="34" y="35" text-anchor="middle" font-family="Georgia,serif" font-size="32" font-weight="700" fill="#ffffff">λ</text>' +
        '<text x="58" y="33" font-family="Arial,Helvetica,sans-serif" font-size="22" font-weight="700" fill="#C9CDD6" letter-spacing="0.5">Lambda</text></svg>'
    };
    return L[key] || '';
  },

  _renderRecognition() {
    const el = document.getElementById('homeRecognitionCard');
    if (!el) return;
    // img: 실제 로고 파일을 /assets/partners/ 에 넣으면 그 이미지가 우선 사용됨 (없으면 SVG 폴백)
    //      chip: 'light' = 흰 칩(어두운 로고용) · 'dark' = 검은 칩(밝은/흰 로고용)
    const partners = [
      { logo: 'nvidia', img: '', chip: 'dark', name: 'NVIDIA Inception', brand: '#76B900', glow: 'rgba(118,185,0,0.30)',
        tag: 'AI Startup Program', status: '참여 중',
        desc: 'NVIDIA의 최신 기술과 생태계를 활용하여 더욱 강력한 제조 AI 솔루션을 개발',
        href: 'https://www.nvidia.com/en-us/startups/' },
      { logo: 'nvidia', img: 'nvidia-innovation-lab.jpeg', chip: 'dark', name: 'NVIDIA Innovation Lab', brand: '#76B900', glow: 'rgba(118,185,0,0.30)',
        tag: 'H100 8-GPU · Brev', status: '선정',
        desc: '60일간 H100 8-GPU 노드를 NVIDIA Brev 플랫폼으로 제공 — 제조 AI 파인튜닝·추론 벤치마킹',
        href: 'https://www.nvidia.com/en-us/data-center/innovation-lab/' },
      { logo: 'aws', img: 'aws.png', chip: 'light', name: 'AWS Startups', brand: '#FF9900', glow: 'rgba(255,153,0,0.30)',
        tag: 'Bedrock · SageMaker', status: '참여 중',
        desc: '클라우드 크레딧 + 기술 멘토링 + AI/ML 도구 — Amazon Bedrock·SageMaker·EKS 활용',
        href: 'https://aws.amazon.com/startups/programs?lang=ko' },
      { logo: 'lambda', img: '', chip: 'dark', name: 'Lambda Startup Program', brand: '#7C5CFC', glow: 'rgba(124,92,252,0.30)',
        tag: 'GPU Cloud', status: '참여 중',
        desc: '단일 GPU 부터 수십만 GPU 까지 — 제조 AI 모델 학습·서빙용 슈퍼인텔리전스 인프라',
        href: 'https://lambda.ai/service/gpu-cloud' },
      { logo: 'google', img: '', chip: 'light', name: 'Google Cloud for Startups', brand: '#4285F4', glow: 'rgba(66,133,244,0.30)',
        tag: 'Vertex AI · BigQuery', status: '참여 중',
        desc: 'Vertex AI · BigQuery · GKE 활용 — 제조 데이터 안전 저장·분석 + 글로벌 확장 가속',
        href: 'https://cloud.google.com/startup?hl=ko' },
      { logo: 'microsoft', img: 'microsoft.jpeg', chip: 'light', name: 'Microsoft for Startups', brand: '#00A4EF', glow: 'rgba(0,164,239,0.30)',
        tag: 'Azure · OpenAI', status: '참여 중',
        desc: 'Azure 크레딧 + OpenAI API 액세스 + GitHub Enterprise + 기술 멘토링',
        href: 'https://www.microsoft.com/ko-kr/startups' },
    ];
    const logoInner = (p) => p.img
      ? '<img class="home-recognition__logo" src="/assets/partners/' + p.img + '" alt="' + Utils.esc(p.name) + '" loading="lazy">'
      : this._partnerLogo(p.logo);
    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">스타트업 프로그램</h2>' +
      '  <span class="u-badge">6 Programs</span>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-recognition">' +
        partners.map(p =>
          '<a class="home-recognition__card" href="' + p.href + '" target="_blank" rel="noopener noreferrer"' +
            ' style="--bp:' + p.brand + ';--bpg:' + p.glow + '">' +
            '<span class="home-recognition__accent"></span>' +
            '<div class="home-recognition__logo-wrap home-recognition__logo-wrap--' + p.chip + '">' + logoInner(p) + '</div>' +
            '<div class="home-recognition__body">' +
              '<div class="home-recognition__tag">' + Utils.esc(p.tag) +
                (p.status ? ' <span class="home-recognition__status">' + Utils.esc(p.status) + '</span>' : '') + '</div>' +
              '<div class="home-recognition__name">' + Utils.esc(p.name) + '</div>' +
              '<div class="home-recognition__desc">' + Utils.esc(p.desc) + '</div>' +
            '</div>' +
            '<div class="home-recognition__visit">방문하기 <span class="home-recognition__arrow">↗</span></div>' +
          '</a>'
        ).join('') +
      '  </div>' +
      '</div>';
  },

  _renderWelcome() {
    const el = document.getElementById('homeWelcome');
    if (!el) return;
    const hour = new Date().getHours();
    const greet = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
    el.innerHTML =
      '<h1>' + Utils.esc(greet) + '</h1>' +
      '<span class="home-welcome__date">' + new Date().toISOString().slice(0,10) + '</span>';
  },

  // \ube44\uc6a9\u00b7\uc0ac\uc6a9\ub7c9 \u2014 \uc5d4\ud130\ud504\ub77c\uc774\uc988 BI: KPI \uc2a4\ud0dd + 13\uac1c\uc6d4 \ucd94\uc774(area) + \ube44\uc6a9\uad6c\uc131(donut)
  async _renderYudi() {
    const el = document.getElementById('homeYudiCard');
    if (!el) return;
    let billLife = {}, months = [], tok = {}, rate = 1507;
    try {
      const rb = await API.billingLifetime();
      if (rb && rb.ok) { billLife = rb.lifetime || {}; rate = rb.krw_rate || rate; }
    } catch(e) {}
    try {
      const rm = await API.billingMonthly();
      if (rm && rm.ok) months = rm.months || [];
    } catch(e) {}
    try {
      const rt = await API.billingTokens('sonnet');
      if (rt && rt.ok) tok = rt;
    } catch(e) {}

    const billMonth = months.length ? months[months.length-1] : null;
    const prevMonth = months.length>1 ? months[months.length-2] : null;

    const usd = (n) => '$' + Number(n||0).toLocaleString('en-US', { maximumFractionDigits: 0 });
    const wonShort = (n) => { const v=Math.round(Number(n||0)); return v>=1e8 ? (v/1e8).toFixed(2).replace(/\.?0+$/,'')+'\uc5b5' : v>=1e4 ? Math.round(v/1e4).toLocaleString('ko-KR')+'\ub9cc' : '\u20a9'+v.toLocaleString('ko-KR'); };
    const tk = (n) => { const v=Number(n||0); return v>=1e9 ? (v/1e9).toFixed(1)+'B' : v>=1e6 ? (v/1e6).toFixed(0)+'M' : v.toLocaleString('en-US'); };

    const mtd = billMonth ? Number(billMonth.total_paid_usd||0) : 0;
    const mtdKrw = billMonth && billMonth.total_paid_krw != null ? billMonth.total_paid_krw : mtd*rate;
    const life = Number(billLife.lifetime_paid_usd||0);
    const lifeKrw = billLife.lifetime_paid_krw != null ? billLife.lifetime_paid_krw : life*rate;
    const estTok = Number(tok.lifetime_est_tokens||0);
    const addonUsd = Number(billLife.lifetime_addon_usd||0);
    const subUsd = Number(billLife.lifetime_subscription_usd||0);
    const refundUsd = Number(billLife.lifetime_refunded_usd||0);

    // \uc804\uc6d4\ub300\ube44
    let delta = '';
    if (billMonth && prevMonth && Number(prevMonth.total_paid_usd)>0) {
      const pct = ((mtd - Number(prevMonth.total_paid_usd))/Number(prevMonth.total_paid_usd))*100;
      const up = pct>=0;
      delta = '<span style="color:'+(up?'var(--red-light)':'var(--green)')+';font-weight:700"> '+(up?'\u25b2':'\u25bc')+' '+Math.abs(pct).toFixed(0)+'%</span>';
    }

    // 13\uac1c\uc6d4 \uacb0\uc81c \ucd94\uc774 (area)
    const tsPts = months.map(m => ({ x: String(m.month).slice(2), y: Number(m.total_paid_usd||0) }));
    const trendSvg = (typeof SvgCharts!=='undefined' && tsPts.length>1)
      ? SvgCharts.timeseries(tsPts, { w: 580, h: 188, stroke:'var(--chart-blue)', fmt: SvgCharts.fmt.usd })
      : '<div class="u-empty"><div class="u-empty__desc">\ucd94\uc774 \ub370\uc774\ud130 \uc5c6\uc74c</div></div>';

    // \ube44\uc6a9 \uad6c\uc131 (donut) \u2014 \uc560\ub4dc\uc628 vs \uad6c\ub3c5
    const donutSvg = (typeof SvgCharts!=='undefined')
      ? SvgCharts.donut([
          { label:'\uc560\ub4dc\uc628 \ud06c\ub808\ub527', value: addonUsd, color:'var(--chart-green)' },
          { label:'\uad6c\ub3c5(MAX)', value: subUsd, color:'var(--chart-blue)' }
        ], { size: 158, hole: 0.64 })
      : '';
    const legend =
      '<div class="home-donut-legend">' +
      '  <div><i style="background:var(--chart-green)"></i>\uc560\ub4dc\uc628 \ud06c\ub808\ub527 <b>' + usd(addonUsd) + '</b></div>' +
      '  <div><i style="background:var(--chart-blue)"></i>\uad6c\ub3c5(MAX) <b>' + usd(subUsd) + '</b></div>' +
      (refundUsd>0 ? '  <div><i style="background:var(--muted)"></i>\ud658\ubd88 <b>-' + usd(refundUsd) + '</b></div>' : '') +
      '</div>';

    const kpi = (label, value, sub, accent) =>
      '<div class="home-cost' + (accent?' home-cost--accent':'') + '" onclick="Router.navigate(\'#/billing\')">' +
      '  <div class="home-cost__label">' + label + '</div>' +
      '  <div class="home-cost__value' + (accent?' home-cost__value--accent':'') + '">' + value + '</div>' +
      '  <div class="home-cost__sub">' + sub + '</div>' +
      '</div>';

    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\ube44\uc6a9 \u00b7 \uc0ac\uc6a9\ub7c9</h2>' +
      '  <button class="u-btn u-btn--sm u-btn--ghost" onclick="Router.navigate(\'#/billing\')">\uc790\uc138\ud788 \u203a</button>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-cost-layout">' +
      '    <div class="home-cost-kpis">' +
            kpi('\uc774\ubc88\ub2ec \ube44\uc6a9', wonShort(mtdKrw), usd(mtd) + delta) +
            kpi('\ub204\uc801 \uacb0\uc81c', wonShort(lifeKrw), usd(life) + ' \u00b7 ' + (billLife.active_months||0) + '\uac1c\uc6d4') +
            kpi('\ucd94\uc815 \ud1a0\ud070', tk(estTok), '\uc560\ub4dc\uc628 ' + usd(addonUsd) + ' \uae30\uc900', true) +
            kpi('\uc560\ub4dc\uc628 \ud06c\ub808\ub527', wonShort(addonUsd*rate), usd(addonUsd) + ' \ub204\uc801') +
      '    </div>' +
      '    <div class="home-cost-chart">' +
      '      <div class="home-chart__cap"><span>\uc6d4\ubcc4 \uacb0\uc81c \ucd94\uc774</span><span>USD \u00b7 ' + months.length + '\uac1c\uc6d4</span></div>' +
      '      <div class="home-chart-body">' + trendSvg + '</div>' +
      '    </div>' +
      '    <div class="home-cost-donut">' +
      '      <div class="home-chart__cap"><span>\ube44\uc6a9 \uad6c\uc131</span></div>' +
      '      <div class="home-donut-wrap">' + donutSvg + '</div>' +
            legend +
      '    </div>' +
      '  </div>' +
      '</div>';
  },

  async _renderYudiMetrics() {
    const el = document.getElementById('homeYudiMetricsCard');
    if (!el) return;
    let h = {}, m = {};
    try { h = await API.get('/api/agent/health') || {}; } catch(e) {}
    try { const r = await API.metrics(); m = (r && r.metrics) || {}; } catch(e) {}
    const sv = h.supervisor_stats || {};
    const ol = h.ollama || {};
    const hg = h.gpu || {};

    // GPU (Brev / RTX) \u2014 system/metrics \uc6b0\uc120, health \ud3f4\ubc31
    const gpuName = m.gpu_name || 'GPU';
    const gpuUtil = Math.round(m.gpu_util != null ? m.gpu_util : (hg.util_pct || 0));
    const gpuTemp = (m.gpu_temp != null ? m.gpu_temp : null);
    const vramUsed = (m.gpu_vram_used_mb != null ? m.gpu_vram_used_mb : (hg.vram_used_mb || 0));
    const vramTotal = (m.gpu_vram_total_mb != null ? m.gpu_vram_total_mb : (hg.vram_total_mb || 0));
    const vramPct = vramTotal > 0 ? Math.round(vramUsed / vramTotal * 100) : (hg.vram_pct || 0);
    const cpu = Math.round(m.cpu_percent != null ? m.cpu_percent : 0);
    const ramPct = Math.round(m.memory_percent != null ? m.memory_percent : 0);
    const ramUsed = m.memory_used_mb || 0, ramTotal = m.memory_total_mb || 0;
    const svModel = (h.supervisor_model || '').replace('ollama:', '');
    const sessions = h.active_sessions || 0;

    // \uc2e4\uc2dc\uac04 \ucd94\uc138 \ubc84\ud37c (5\ucd08 \ud3f4\ub9c1\ub9c8\ub2e4 \ub204\uc801, \ucd5c\uadfc 48\uc0d8\ud50c \u2248 4\ubd84)
    if (!this._gpuHist) this._gpuHist = [];
    this._gpuHist.push(gpuUtil);
    if (this._gpuHist.length > 48) this._gpuHist.shift();

    const now = new Date().toTimeString().slice(0,8);
    const gauge = (val, name, sub) =>
      '<div class="home-gauge">' +
        (typeof SvgCharts!=='undefined' ? SvgCharts.gauge(val, { size: 116, thresholds:[60,85] }) : (val+'%')) +
        '<div class="home-gauge__name">' + name + '</div>' +
        '<div class="home-gauge__sub">' + sub + '</div>' +
      '</div>';
    const sparkSvg = (this._gpuHist.length > 1 && typeof SvgCharts!=='undefined')
      ? SvgCharts.sparkline(this._gpuHist, { w: 560, h: 30, stroke:'var(--chart-cyan)' })
      : '';

    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\uc2dc\uc2a4\ud15c \u00b7 GPU \ud604\ud669</h2>' +
      '  <span class="u-badge u-badge--info">live \u00b7 ' + now + '</span>' +
      '</div>' +
      '<div class="u-panel__body">' +
      (sparkSvg ?
      '  <div class="home-gpu-spark">' +
      '    <div class="cap"><span>GPU \uc0ac\uc6a9\ub960 \ucd94\uc138</span><span>' + gpuUtil + '% \u00b7 \ucd5c\uadfc ' + this._gpuHist.length + '\uc0d8\ud50c</span></div>' +
            sparkSvg +
      '  </div>' : '') +
      '  <div class="home-gauge-grid">' +
          gauge(gpuUtil, Utils.esc(gpuName.replace('NVIDIA GeForce ','')), (gpuTemp!=null ? gpuTemp+'\u00b0 \u00b7 ' : '') + '\ucd94\ub860') +
          gauge(vramPct, 'VRAM', Math.round(vramUsed/1024) + '/' + Math.round(vramTotal/1024) + 'GB') +
          gauge(cpu, 'CPU', (m.cpu_cores ? m.cpu_cores+'\ucf54\uc5b4' : '\uc0ac\uc6a9\ub960')) +
          gauge(ramPct, 'RAM', Math.round(ramUsed/1024) + '/' + Math.round(ramTotal/1024) + 'GB') +
      '  </div>' +
      '  <div class="home-metrics-foot">' +
      '    <span>Supervisor <b>' + (sv.total || 0) + '</b> \u00b7 avg <b>' + (sv.avg_score || 0).toFixed(2) + '</b> \u00b7 today ' + (sv.today || 0) + ' \u00b7 pending ' + (sv.pending || 0) + '</span>' +
      '    <span>\ubaa8\ub378 <b>' + Utils.esc(svModel || '-') + '</b> \u00b7 \uc138\uc158 ' + sessions + ' \u00b7 \ub85c\ub4dc ' + (ol.model_count || 0) + '</span>' +
      '  </div>' +
      '</div>';
  },

  // 5\ucd08 \uac04\uaca9 GPU\u00b7\ub9ac\uc18c\uc2a4 \ud3f4\ub9c1 (render \uc2dc\uc791/\ubdf0 \uc774\ud0c8 \uc2dc \uc815\ub9ac)
  _startMetricsPoll() {
    this._stopMetricsPoll();
    this._metricsTimer = setInterval(() => {
      if (!document.getElementById('homeYudiMetricsCard')) { this._stopMetricsPoll(); return; }
      this._renderYudiMetrics();
    }, 5000);
  },
  _stopMetricsPoll() {
    if (this._metricsTimer) { clearInterval(this._metricsTimer); this._metricsTimer = null; }
  },

  async _renderKpi() {
    const el = document.getElementById('homeKpiCard');
    if (!el) return;
    let s = {}, agentKpi = {}, billLife = {}, billMonths = [];
    try {
      const res = await API.globalStats();
      s = (res && res.stats) || {};
    } catch(e) {}
    try {
      const r2 = await fetch('/api/agents/global/kpi').then(r => r.json());
      if (r2 && r2.ok) agentKpi = r2;
    } catch(e) {}
    try {
      const rb = await API.billingLifetime();
      if (rb && rb.ok) billLife = rb.lifetime || {};
      const rm = await API.billingMonthly();
      if (rm && rm.ok) billMonths = rm.months || [];
    } catch(e) {}
    const total = s.total_tickets || 0;
    const done = s.done_tickets || 0;
    const blocked = s.blocked_tickets || 0;
    const working = s.working_agents || 0;
    const remaining = Math.max(0, total - done - blocked);
    const dist = agentKpi.grade_distribution || {};
    const top = (agentKpi.top_agents || []).slice(0, 3);
    const gradeLine = ['S','A','B','C'].map(g => {
      const n = dist[g] || 0;
      const cls = g === 'S' ? 'home-grade--s' : g === 'A' ? 'home-grade--a' : g === 'B' ? 'home-grade--b' : 'home-grade--c';
      return '<span class="home-grade ' + cls + '">' + g + ' ' + n + '</span>';
    }).join('');
    const topLine = top.length
      ? top.map(t => {
          const done = t.completed_tickets || 0;
          const qa = Number(t.avg_qa_score || 0);
          const rework = t.rework_count || 0;
          const reworkRate = done > 0 ? rework / Math.max(done,1) : 0;
          const flags = [];
          if (qa > 0 && qa < 3.5)            flags.push('<span class="home-flag home-flag--qa" title="\uc800\ud488\uc9c8">QA</span>');
          if (reworkRate > 0.3)              flags.push('<span class="home-flag home-flag--rework" title="\uc7ac\uc791\uc5c5 \ub2e4\ubc1c">REWORK</span>');
          if ((t.progress_note_count || 0) === 0 && done > 0) flags.push('<span class="home-flag home-flag--noprogress" title="\ubcf4\uace0 \uc5c6\uc74c">NO-NOTE</span>');
          const cls = flags.length ? ' home-top-agent--danger' : '';
          return '<div class="home-top-agent' + cls + '">'
              + '<span class="home-top-agent__grade">' + (t.grade || '-') + '</span>'
              + '<span class="home-top-agent__name">' + Utils.esc(t.display_name || t.member_id) + '</span>'
              + '<span class="home-top-agent__meta">done ' + done + ' \u00b7 QA ' + qa.toFixed(1) + '</span>'
              + (flags.length ? '<span class="home-top-agent__flags">' + flags.join('') + '</span>' : '')
              + '</div>';
        }).join('')
      : '<div class="home-top-agent home-top-agent--empty">KPI \uc9d1\uacc4 \ub300\uae30 \uc911</div>';
    // \uacb0\uc81c KPI \u2014 \uc774\ubc88\ub2ec / \ub204\uc801 \ube44\uc6a9 (billing API \uae30\ubc18)
    const thisMonth = billMonths.length ? billMonths[billMonths.length - 1] : null;
    const mtdCost = thisMonth ? Number(thisMonth.total_paid_usd || 0) : 0;
    const lifeCost = Number(billLife.lifetime_paid_usd || 0);
    const fmtUsd = (n) => '$' + Number(n || 0).toLocaleString('en-US', { maximumFractionDigits: 0 });
    const costLine = (lifeCost > 0)
      ? '  <div class="home-kpi__meta home-kpi__meta--cost" style="cursor:pointer" onclick="Router.navigate(\'#/billing\')">' +
        '\ud83d\udcb3 \uc774\ubc88\ub2ec \ube44\uc6a9 <b style="color:var(--text)">' + fmtUsd(mtdCost) + '</b>' +
        ' \u00b7 \ub204\uc801 <b style="color:var(--text)">' + fmtUsd(lifeCost) + '</b>' +
        ' <span style="color:var(--brand-light)">\uacb0\uc81c \ub300\uc2dc\ubcf4\ub4dc \u203a</span></div>'
      : '';
    el.innerHTML =
      '<div class="u-panel__header"><h2 class="u-panel__title">\uc624\ub298\uc758 \uc694\uc57d</h2></div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-kpi-grid">' +
      '    <div class="home-kpi"><div class="home-kpi-label">\uc644\ub8cc \ud2f0\ucf13</div><div class="home-kpi-value">' + done + '</div></div>' +
      '    <div class="home-kpi"><div class="home-kpi-label">\uc9c4\ud589 \uc911</div><div class="home-kpi-value">' + remaining + '</div></div>' +
      '    <div class="home-kpi"><div class="home-kpi-label">\ud65c\uc131 \uc5d0\uc774\uc804\ud2b8</div><div class="home-kpi-value home-kpi-value--info">' + working + '</div></div>' +
      '    <div class="home-kpi"><div class="home-kpi-label">Blocked</div><div class="home-kpi-value home-kpi-value--danger">' + blocked + '</div></div>' +
      '  </div>' +
      '  <div class="home-kpi__meta">\uc804\uccb4 \uc9c4\ud589\ub960 ' + Number(s.global_progress || 0).toFixed(1) + '% \u00b7 \uc544\uce74\uc774\ube0c ' + (s.archived_teams || 0) + '</div>' +
      costLine +
      '  <div class="home-grade-row">\uc5d0\uc774\uc804\ud2b8 \ub4f1\uae09 ' + gradeLine + '</div>' +
      '  <div class="home-top-agents"><div class="home-top-agents__title">Top 3</div>' + topLine + '</div>' +
      '</div>';
  },

  async _renderTeams() {
    const el = document.getElementById('homeTeamsCard');
    if (!el) return;
    let teams = [], stats = {};
    try {
      const res = await API.overview();
      teams = res.teams || [];
    } catch(e) {}
    try {
      const r = await API.globalStats();
      stats = (r && r.stats) || {};
    } catch(e) {}
    // \uc9c4\ud589 \uc911\uc778 \ud300 \u2014 \uc22b\uc790 \uc694\uc57d\ub9cc (\uce74\ub4dc \ub9ac\uc2a4\ud2b8 \ub300\uc2e0)
    const active = teams.length;
    const totalTickets = teams.reduce((a,t)=>a+(t.total_tickets||(t.team&&t.team.total_tickets)||0),0);
    const doneTickets  = teams.reduce((a,t)=>a+(t.done_tickets||(t.team&&t.team.done_tickets)||0),0);
    const inProgress   = Math.max(0, totalTickets - doneTickets);
    const pct = totalTickets>0 ? Math.round(doneTickets/totalTickets*100) : 0;
    const blocked = stats.blocked_tickets || 0;
    // \uc804\uc5ed \ud1b5\uacc4 \ud3f4\ubc31 (overview teams \uac00 \ube44\uc5b4\ub3c4 supervisor/stats \ub85c \ucc44\uc6c0)
    const gTotal = stats.total_tickets || totalTickets;
    const gDone = stats.done_tickets || doneTickets;
    const gInProg = Math.max(0, gTotal - gDone - blocked);
    const gPct = gTotal>0 ? Math.round(gDone/gTotal*100) : pct;
    const activeTeams = stats.active_teams || active;
    const agents = stats.working_agents || 0;
    const num = (n) => Number(n||0).toLocaleString('ko-KR');

    const donutSvg = (typeof SvgCharts!=='undefined')
      ? SvgCharts.donut([
          { label:'\uc644\ub8cc', value: gDone, color:'var(--chart-green)' },
          { label:'\uc9c4\ud589', value: gInProg, color:'var(--chart-blue)' },
          { label:'Blocked', value: blocked, color:'var(--red)' }
        ], { size: 150, hole: 0.66 })
      : '';

    // \ube44\uc6a9 \ud328\ub110\uacfc \ub3d9\uc77c\ud55c .home-cost \uce74\ub4dc\ub85c \ud1b5\uc77c
    const card = (label, value, sub, mod) =>
      '<div class="home-cost" onclick="Router.navigate(\'#/teams\')">' +
      '  <div class="home-cost__label">' + label + '</div>' +
      '  <div class="home-cost__value' + (mod ? ' home-cost__value--' + mod : '') + '">' + value + '</div>' +
      (sub ? '  <div class="home-cost__sub">' + sub + '</div>' : '') +
      '</div>';

    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\uc9c4\ud589 \ud604\ud669</h2>' +
      '  <button class="u-btn u-btn--sm u-btn--ghost" onclick="Router.navigate(\'#/teams\')">\ud300 \ubcf4\uae30 \u203a</button>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-ops-layout">' +
      '    <div class="home-ops-donut">' + donutSvg +
      '      <div class="home-ops-donut__cap">\uc644\ub8cc\uc728 <b>' + gPct + '%</b></div>' +
      '    </div>' +
      '    <div class="home-cost-kpis">' +
            card('\uc644\ub8cc \ud2f0\ucf13', num(gDone), gPct + '% \uc644\ub8cc') +
            card('\uc9c4\ud589 \ud2f0\ucf13', num(gInProg), '') +
            card('\ud65c\uc131 \uc5d0\uc774\uc804\ud2b8', num(agents), '', 'accent') +
            card('Blocked', num(blocked), '', blocked > 0 ? 'danger' : '') +
      '    </div>' +
      '  </div>' +
      '  <div class="home-ops-foot">\uc9c4\ud589 \ud300 <b>' + num(activeTeams) + '</b> \u00b7 \uc544\uce74\uc774\ube0c ' + (stats.archived_teams||0) + ' \u00b7 \uc804\uccb4 \uc9c4\ud589\ub960 <b>' + gPct + '%</b></div>' +
      '</div>';
  },

  _renderFeed() {
    const el = document.getElementById('homeFeedCard');
    if (!el) return;
    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">Live Feed</h2>' +
      '  <span class="u-badge" id="homeFeedCount">' + this._feedItems.length + '</span>' +
      '</div>' +
      '<div class="u-panel__body home-feed__body" id="homeFeedBody"></div>';
    this._renderFeedBody();
  },

  _renderFeedBody() {
    const body = document.getElementById('homeFeedBody');
    const count = document.getElementById('homeFeedCount');
    if (!body) return;
    if (count) count.textContent = this._feedItems.length;
    if (!this._feedItems.length) {
      body.innerHTML = '<div class="u-empty"><div class="u-empty__desc">\uc774\ubca4\ud2b8 \ub300\uae30 \uc911\u2026</div></div>';
      return;
    }
    const iconMap = {
      ticket_created: 'plus', ticket_status_changed: 'activity', ticket_claimed: 'zap',
      member_spawned: 'bot', team_created: 'layers', team_archived: 'archives', feedback_created: 'check'
    };
    const colorMap = {
      ticket_created: 'var(--info-fg)', ticket_status_changed: 'var(--brand-light)',
      ticket_claimed: 'var(--warning-fg)', member_spawned: 'var(--text-secondary)',
      team_created: 'var(--success-fg)', team_archived: 'var(--text-muted-new)',
      feedback_created: 'var(--success-fg)'
    };
    body.innerHTML = this._feedItems.slice(0, 30).map(it => {
      const t = new Date(it.at).toTimeString().slice(0,5);
      const iconName = iconMap[it.type] || 'info';
      const color = colorMap[it.type] || 'var(--text-muted-new)';
      const title = it.payload.title || it.payload.ticket_title || it.payload.name || it.type;
      const team = it.team ? '<span class="home-feed__team">\u00b7 ' + Utils.esc(it.team) + '</span>' : '';
      return '<div class="home-feed__row">' +
        '<span class="home-feed__time">' + t + '</span>' +
        '<span class="home-feed__icon" style="color:' + color + '">' + Utils.icon(iconName, 14, 2) + '</span>' +
        '<span class="home-feed__title">' + Utils.esc(title) + '</span>' + team +
      '</div>';
    }).join('');
  },

  _bindSse() {
    if (this._sseBound) return;
    if (typeof SSE === 'undefined' || !SSE.connectGlobal) return;
    this._sseBound = true;
    SSE.connectGlobal((data) => {
      this._feedItems.unshift({
        type: data.event_type || data.type || 'event',
        team: data.team_name || '',
        payload: data.data || {},
        at: Date.now()
      });
      if (this._feedItems.length > 50) this._feedItems.pop();
      this._renderFeedBody();
      if (typeof Header !== 'undefined') Header.setSseStatus(true);
    });
  },

  // GitHub \ucee8\ud2b8\ub9ac\ubdf0\uc158 \uadf8\ub798\ud504 \uc2a4\ud0c0\uc77c \u2014 \uc77c\ubcc4 \uce74\uc6b4\ud2b8(weekly API), 7\ud589 \u00d7 \uc8fc \uceec\ub7fc
  async _renderHeatmap() {
    const el = document.getElementById('homeHeatmapCard');
    if (!el) return;
    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\ud65c\ub3d9 \uadf8\ub798\ud504</h2>' +
      '  <span class="u-badge" id="ghTotalBadge">\u2014</span>' +
      '</div>' +
      '<div class="u-panel__body" id="homeHeatmapBody"></div>';
    const body = document.getElementById('homeHeatmapBody');
    try {
      const res = await API.get('/api/supervisor/heatmap?mode=weekly');
      const data = (res && res.data) || {};

      const WEEKS = 27;                       // \uc57d 6\uac1c\uc6d4
      const pad = (n) => String(n).padStart(2,'0');
      const fmt = (d) => d.getFullYear() + '-' + pad(d.getMonth()+1) + '-' + pad(d.getDate());
      const today = new Date(); today.setHours(0,0,0,0);
      const end = new Date(today); end.setDate(end.getDate() + (6 - today.getDay()));  // \uc774\ubc88 \uc8fc \ud1a0\uc694\uc77c
      const start = new Date(end); start.setDate(start.getDate() - (WEEKS*7 - 1));     // \uc2dc\uc791 \uc77c\uc694\uc77c

      // \uc77c\uc790 \uc21c\ud68c (\uc2dc\uac04\uc21c = \uadf8\ub9ac\ub4dc column-major \ucc44\uc6c0 \uc21c\uc11c\uc640 \uc77c\uce58)
      const days = [];
      let total = 0, max = 0, activeDays = 0;
      for (let cur = new Date(start); cur <= end; cur.setDate(cur.getDate()+1)) {
        const key = fmt(cur);
        const count = Number(data[key] || 0);
        days.push({ key, count, month: cur.getMonth(), date: cur.getDate(), dow: cur.getDay(), future: cur > today });
        if (!('future' in days[days.length-1]) || cur <= today) { total += count; if (count > max) max = count; if (count>0) activeDays++; }
      }
      const level = (c) => { if (c <= 0) return 0; const r = c / (max||1); return r > 0.75 ? 4 : r > 0.5 ? 3 : r > 0.25 ? 2 : 1; };

      // \uc140 (\uc2dc\uac04\uc21c \u2192 grid-auto-flow:column 7\ud589\uc73c\ub85c \uc790\ub3d9 \uc8fc \uc815\ub82c)
      const cells = days.map(d => {
        if (d.future) return '<div class="gh-cell" style="visibility:hidden"></div>';
        const lv = level(d.count);
        return '<div class="gh-cell' + (lv ? ' gh-cell--l'+lv : '') + '" title="' + d.key + ' \u00b7 ' + d.count + '\uac74"></div>';
      }).join('');

      // \uc6d4 \ub77c\ubca8 (\uac01 \uc8fc\uc758 \uccab\ub0a0 \uae30\uc900, \uc6d4\uc774 \ubc14\ub00c\uba74 \ud45c\uae30)
      const weeks = Math.ceil(days.length / 7);
      let prevMonth = -1; const monthSpans = [];
      for (let w = 0; w < weeks; w++) {
        const first = days[w*7];
        if (first && first.month !== prevMonth) { monthSpans.push('<span class="gh-heatmap__month">' + (first.month+1) + '\uc6d4</span>'); prevMonth = first.month; }
        else monthSpans.push('<span class="gh-heatmap__month"></span>');
      }

      const weekdays = ['','\uc6d4','','\uc218','','\uae08',''].map(w => '<span>' + w + '</span>').join('');

      body.innerHTML =
        '<div class="gh-heatmap">' +
        '  <div class="gh-heatmap__weekday">' + weekdays + '</div>' +
        '  <div class="gh-heatmap__main">' +
        '    <div class="gh-heatmap__months" style="grid-template-columns:repeat(' + weeks + ',11px)">' + monthSpans.join('') + '</div>' +
        '    <div class="gh-heatmap__grid">' + cells + '</div>' +
        '    <div class="gh-heatmap__legend">Less <i class="gh-cell"></i><i class="gh-cell gh-cell--l1"></i><i class="gh-cell gh-cell--l2"></i><i class="gh-cell gh-cell--l3"></i><i class="gh-cell gh-cell--l4"></i> More</div>' +
        '  </div>' +
        '</div>' +
        '<div class="gh-heatmap__stat">' +
        '  <span>\ucd5c\uadfc ' + WEEKS + '\uc8fc \u00b7 <b>' + total.toLocaleString('ko-KR') + '</b>\uac74</span>' +
        '  <span>\ud65c\ub3d9\uc77c <b>' + activeDays + '</b>\uc77c \u00b7 \uc77c \ucd5c\ub300 <b>' + max.toLocaleString('ko-KR') + '</b>\uac74</span>' +
        '</div>';
      const badge = document.getElementById('ghTotalBadge');
      if (badge) badge.textContent = total.toLocaleString('ko-KR') + '\uac74';
    } catch(e) {
      body.innerHTML = '<div class="u-empty"><div class="u-empty__desc">\ub85c\ub529 \uc2e4\ud328</div></div>';
    }
  },

  async _askYudi() {
    const q = prompt('\uc720\ub514\uc5d0\uac8c \uc9c8\ubb38:');
    if (!q) return;
    // \uc9c4\ud589 \uc778\ub514\ucf00\uc774\ud130 \ud1a0\uc2a4\ud2b8
    const toast = document.createElement('div');
    toast.style.cssText = 'position:fixed;right:16px;bottom:16px;background:#0e2435;color:#79b8ff;padding:10px 14px;border-radius:8px;border:1px solid rgba(56,139,253,0.35);font-size:12px;z-index:9999;box-shadow:0 4px 12px rgba(0,0,0,0.4)';
    toast.textContent = '\ud83e\udd16 \uc720\ub514\uac00 \ub2f5\ud558\ub294 \uc911...';
    document.body.appendChild(toast);
    try {
      const res = await API.post('/api/agent/chat', { message: q });
      toast.remove();
      const answer = res.response || res.answer || res.message || (res.error ? ('\uc624\ub958: ' + res.error) : '\uc751\ub2f5 \uc5c6\uc74c');
      this._showYudiAnswer(q, answer);
    } catch(e) {
      toast.remove();
      this._showYudiAnswer(q, '\uc694\uccad \uc2e4\ud328: ' + e.message);
    }
  },

  _showYudiAnswer(question, answer) {
    const ov = document.createElement('div');
    ov.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.7);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px';
    ov.onclick = (e) => { if (e.target === ov) ov.remove(); };
    const box = document.createElement('div');
    box.style.cssText = 'background:#16181D;color:#ECEDEE;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:20px;max-width:640px;width:100%;max-height:80vh;overflow-y:auto;font-family:Inter,sans-serif';
    box.innerHTML =
      '<div style="font-size:11px;color:#5E6C84;margin-bottom:6px;letter-spacing:0.05em">\uc9c8\ubb38</div>' +
      '<div style="font-size:14px;color:#79b8ff;margin-bottom:14px;padding-bottom:14px;border-bottom:1px solid rgba(255,255,255,0.06)">' + Utils.esc(question) + '</div>' +
      '<div style="font-size:11px;color:#5E6C84;margin-bottom:6px;letter-spacing:0.05em">\uc720\ub514</div>' +
      '<div style="font-size:13px;line-height:1.6;white-space:pre-wrap">' + Utils.esc(answer) + '</div>' +
      '<div style="text-align:right;margin-top:16px"><button style="background:#1B96FF;color:#fff;border:none;padding:8px 16px;border-radius:6px;cursor:pointer;font-weight:600" onclick="this.closest(\'div[style*=fixed]\').remove()">\ub2eb\uae30</button></div>';
    ov.appendChild(box);
    document.body.appendChild(ov);
  },

  async _yudiLog() {
    try {
      const res = await API.residentHistory(50, 'all');
      const items = (res && res.history) || [];
      // popup blocker \ud68c\ud53c \u2014 \ud398\uc774\uc9c0 \ub0b4 \ubaa8\ub2ec\ub85c \ud45c\uc2dc
      const ov = document.createElement('div');
      ov.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.7);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px';
      ov.onclick = (e) => { if (e.target === ov) ov.remove(); };
      const rows = items.length
        ? items.map(h =>
            '<div style="display:grid;grid-template-columns:140px 1fr;gap:10px;align-items:flex-start;padding:8px 0;border-bottom:1px solid rgba(255,255,255,0.05);font-size:12px">' +
              '<span style="color:#5E6C84;font-family:monospace;font-size:11px">' + Utils.esc(Utils.dateFmt(h.created_at || h.timestamp)) + '</span>' +
              '<span style="color:#ECEDEE;line-height:1.5">' + Utils.esc((h.message || h.content || h.type || '').slice(0, 200)) + '</span>' +
            '</div>'
          ).join('')
        : '<div style="text-align:center;padding:40px;color:#5E6C84">\uc720\ub514 \ub85c\uadf8 \uc5c6\uc74c</div>';
      const box = document.createElement('div');
      box.style.cssText = 'background:#16181D;color:#ECEDEE;border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:20px;max-width:720px;width:100%;max-height:80vh;display:flex;flex-direction:column;font-family:Inter,sans-serif';
      box.innerHTML =
        '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">' +
          '<div style="font-size:14px;font-weight:700">\ud83d\udcdc \uc720\ub514 \ub85c\uadf8 <span style="color:#5E6C84;font-size:11px;font-weight:400">\u00b7 \ucd5c\uadfc ' + items.length + '\uac74</span></div>' +
          '<button style="background:none;border:none;color:#5E6C84;font-size:20px;cursor:pointer;padding:4px 8px" onclick="this.closest(\'div[style*=fixed]\').remove()">\u00d7</button>' +
        '</div>' +
        '<div style="overflow-y:auto;flex:1">' + rows + '</div>';
      ov.appendChild(box);
      document.body.appendChild(ov);
    } catch(e) {
      alert('\ub85c\uadf8 \ub85c\ub529 \uc2e4\ud328: ' + (e.message || e));
    }
  },

  async _stopYudi() {
    if (!confirm('\uc720\ub514\ub97c \uc911\ub2e8\ud558\uc2dc\uaca0\uc2b5\ub2c8\uae4c?')) return;
    try {
      // body \ube48 \uac1d\uccb4 \uba85\uc2dc (undefined \u2192 "undefined" \ubb38\uc790\uc5f4 \ud30c\uc2f1 \uc2e4\ud328 \ubc29\uc9c0)
      const res = await API.post('/api/agent/stop', {});
      if (res.ok === false) alert('\uc911\ub2e8 \uc2e4\ud328: ' + (res.error || res.message || ''));
      this.refresh();
    } catch(e) { alert('\uc2e4\ud328: ' + (e.message || e)); }
  }
};

if (typeof App !== 'undefined') App.registerView('home', HomeView);
