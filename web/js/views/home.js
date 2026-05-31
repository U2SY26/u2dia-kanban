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
      '    <div id="homeKpiCard" class="u-panel"></div>' +              // 오늘의 요약
      '    <div id="homeYudiMetricsCard" class="u-panel home-yudi-metrics-panel"></div>' +  // 시스템·GPU
      '  </div>' +
      '  <div id="homeRecognitionCard" class="u-panel home-recognition-panel"></div>' +
      '  <div id="homeTeamsCard" class="u-panel"></div>' +
      '  <div id="homeLowerRow" class="home-grid-bottom">' +
      '    <div id="homeFeedCard" class="u-panel"></div>' +
      '    <div id="homeHeatmapCard" class="u-panel"></div>' +
      '  </div>' +
      '</div>';
    await this.refresh();
    this._bindSse();
    this._startMetricsPoll();
  },

  async refresh() {
    this._renderWelcome();
    await Promise.all([
      this._renderYudi(),
      this._renderKpi(),
      this._renderYudiMetrics(),
      this._renderTeams(),
      this._renderHeatmap()
    ]);
    this._renderRecognition();
    this._renderFeed();
  },

  _renderRecognition() {
    const el = document.getElementById('homeRecognitionCard');
    if (!el) return;
    const partners = [
      { logo: 'NVIDIA', name: 'NVIDIA Inception',
        tag: 'AI Startup Program', status: '참여 중',
        desc: 'NVIDIA의 최신 기술과 생태계를 활용하여 더욱 강력한 제조 AI 솔루션을 개발',
        href: 'https://www.nvidia.com/en-us/startups/' },
      { img: 'nvidia-innovation-lab.png', name: 'NVIDIA Innovation Lab',
        tag: 'H100 8-GPU · Brev', status: '선정',
        desc: '60일간 H100 8-GPU 노드를 NVIDIA Brev 플랫폼으로 제공 — 제조 AI 파인튜닝·추론 벤치마킹',
        href: 'https://www.nvidia.com/en-us/data-center/innovation-lab/' },
      { logo: 'aws', name: 'AWS Startups',
        tag: 'Bedrock · SageMaker', status: '참여 중',
        desc: '클라우드 크레딧 + 기술 멘토링 + AI/ML 도구 — Amazon Bedrock·SageMaker·EKS 활용',
        href: 'https://aws.amazon.com/startups/' },
      { img: 'lambda.png', name: 'Lambda Startup Program',
        tag: 'GPU Cloud', status: '참여 중',
        desc: '단일 GPU 부터 수십만 GPU 까지 — 제조 AI 모델 학습·서빙용 슈퍼인텔리전스 인프라',
        href: 'https://lambda.ai/service/gpu-cloud' },
      { img: 'google-cloud-startups.png', name: 'Google Cloud for Startups',
        tag: 'Vertex AI · BigQuery', status: '참여 중',
        desc: 'Vertex AI · BigQuery · GKE 활용 — 제조 데이터 안전 저장·분석 + 글로벌 확장 가속',
        href: 'https://cloud.google.com/startup' },
      { img: 'microsoft-for-startups.png', name: 'Microsoft for Startups',
        tag: 'Azure · OpenAI', status: '참여 중',
        desc: 'Azure 크레딧 + OpenAI API 액세스 + GitHub Enterprise + 기술 멘토링',
        href: 'https://www.microsoft.com/en-us/startups' },
    ];
    const logoHtml = (p) => p.img
      ? '<img class="home-recognition__logo" src="/assets/partners/' + p.img + '" alt="' + Utils.esc(p.name) + '" loading="lazy">'
      : '<span class="home-recognition__logo-text">' + Utils.esc(p.logo || p.name) + '</span>';
    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">스타트업 프로그램</h2>' +
      '  <span class="u-badge">6 Programs</span>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-recognition">' +
        partners.map(p =>
          '<a class="home-recognition__card" href="' + p.href + '" target="_blank" rel="noopener noreferrer">' +
            '<div class="home-recognition__logo-wrap">' + logoHtml(p) + '</div>' +
            '<div class="home-recognition__body">' +
              '<div class="home-recognition__tag">' + Utils.esc(p.tag) +
                (p.status ? ' <span class="home-recognition__status">' + Utils.esc(p.status) + '</span>' : '') + '</div>' +
              '<div class="home-recognition__name">' + Utils.esc(p.name) + '</div>' +
              '<div class="home-recognition__desc">' + Utils.esc(p.desc) + '</div>' +
            '</div>' +
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

  // \ube44\uc6a9\u00b7\uc0ac\uc6a9\ub7c9 \uc694\uc57d \uce74\ub4dc (\uae30\uc874 \uc720\ub514 \uc9c8\ubb38/\ub85c\uadf8/\uc911\ub2e8 \ubc84\ud2bc \u2192 \uc758\ubbf8\uc788\ub294 \uc9c0\ud45c\ub85c \uad50\uccb4)
  async _renderYudi() {
    const el = document.getElementById('homeYudiCard');
    if (!el) return;
    let billLife = {}, billMonth = null, prevMonth = null, tok = {}, rate = 1507;
    try {
      const rb = await API.billingLifetime();
      if (rb && rb.ok) { billLife = rb.lifetime || {}; rate = rb.krw_rate || rate; }
    } catch(e) {}
    try {
      const rm = await API.billingMonthly();
      if (rm && rm.ok) { const ms = rm.months || []; billMonth = ms[ms.length-1]; prevMonth = ms[ms.length-2]; }
    } catch(e) {}
    try {
      const rt = await API.billingTokens('sonnet');
      if (rt && rt.ok) tok = rt;
    } catch(e) {}

    const usd = (n) => '$' + Number(n||0).toLocaleString('en-US', { maximumFractionDigits: 0 });
    const won = (n) => '\u20a9' + Math.round(Number(n||0)).toLocaleString('ko-KR');
    const wonShort = (n) => { const v=Math.round(Number(n||0)); return v>=1e8 ? (v/1e8).toFixed(2).replace(/\.?0+$/,'')+'\uc5b5' : v>=1e4 ? Math.round(v/1e4).toLocaleString('ko-KR')+'\ub9cc' : '\u20a9'+v.toLocaleString('ko-KR'); };
    const tk = (n) => { const v=Number(n||0); return v>=1e9 ? (v/1e9).toFixed(1)+'B' : v>=1e6 ? (v/1e6).toFixed(0)+'M' : v.toLocaleString('en-US'); };

    const mtd = billMonth ? Number(billMonth.total_paid_usd||0) : 0;
    const mtdKrw = billMonth && billMonth.total_paid_krw != null ? billMonth.total_paid_krw : mtd*rate;
    const life = Number(billLife.lifetime_paid_usd||0);
    const lifeKrw = billLife.lifetime_paid_krw != null ? billLife.lifetime_paid_krw : life*rate;
    const estTok = Number(tok.lifetime_est_tokens||0);
    const addonUsd = Number(billLife.lifetime_addon_usd||0);

    // \uc804\uc6d4\ub300\ube44
    let delta = '';
    if (billMonth && prevMonth && Number(prevMonth.total_paid_usd)>0) {
      const pct = ((mtd - Number(prevMonth.total_paid_usd))/Number(prevMonth.total_paid_usd))*100;
      const up = pct>=0;
      delta = '<span style="color:'+(up?'var(--red-light)':'var(--green)')+';font-weight:600">'+(up?'\u25b2':'\u25bc')+' '+Math.abs(pct).toFixed(0)+'%</span>';
    }

    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\ube44\uc6a9 \u00b7 \uc0ac\uc6a9\ub7c9</h2>' +
      '  <button class="u-btn u-btn--sm u-btn--ghost" onclick="Router.navigate(\'#/billing\')">\uc790\uc138\ud788 \u203a</button>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-cost-grid">' +
      '    <div class="home-cost" onclick="Router.navigate(\'#/billing\')">' +
      '      <div class="home-cost__label">\uc774\ubc88\ub2ec \ube44\uc6a9</div>' +
      '      <div class="home-cost__value">' + wonShort(mtdKrw) + '</div>' +
      '      <div class="home-cost__sub">' + usd(mtd) + ' ' + delta + '</div>' +
      '    </div>' +
      '    <div class="home-cost" onclick="Router.navigate(\'#/billing\')">' +
      '      <div class="home-cost__label">\ub204\uc801 \uacb0\uc81c</div>' +
      '      <div class="home-cost__value">' + wonShort(lifeKrw) + '</div>' +
      '      <div class="home-cost__sub">' + usd(life) + ' \u00b7 ' + (billLife.active_months||0) + '\uac1c\uc6d4</div>' +
      '    </div>' +
      '    <div class="home-cost" onclick="Router.navigate(\'#/billing\')">' +
      '      <div class="home-cost__label">\ucd94\uc815 \ud1a0\ud070</div>' +
      '      <div class="home-cost__value home-cost__value--accent">' + tk(estTok) + '</div>' +
      '      <div class="home-cost__sub">\uc560\ub4dc\uc628 ' + usd(addonUsd) + ' \uae30\uc900</div>' +
      '    </div>' +
      '    <div class="home-cost" onclick="Router.navigate(\'#/billing\')">' +
      '      <div class="home-cost__label">\uc560\ub4dc\uc628 \ud06c\ub808\ub527</div>' +
      '      <div class="home-cost__value">' + wonShort(addonUsd * rate) + '</div>' +
      '      <div class="home-cost__sub">' + usd(addonUsd) + ' \ub204\uc801 \ucda9\uc804</div>' +
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
    const gpuUtil = (m.gpu_util != null ? m.gpu_util : (hg.util_pct || 0));
    const gpuTemp = (m.gpu_temp != null ? m.gpu_temp : null);
    const vramUsed = (m.gpu_vram_used_mb != null ? m.gpu_vram_used_mb : (hg.vram_used_mb || 0));
    const vramTotal = (m.gpu_vram_total_mb != null ? m.gpu_vram_total_mb : (hg.vram_total_mb || 0));
    const vramPct = vramTotal > 0 ? Math.round(vramUsed / vramTotal * 100) : (hg.vram_pct || 0);
    const cpu = m.cpu_percent != null ? m.cpu_percent : 0;
    const ramPct = m.memory_percent != null ? m.memory_percent : 0;
    const ramUsed = m.memory_used_mb || 0, ramTotal = m.memory_total_mb || 0;
    const svModel = (h.supervisor_model || '').replace('ollama:', '');
    const sessions = h.active_sessions || 0;

    const barCls = (p) => p >= 90 ? 'home-metric__bar--danger' : p >= 75 ? 'home-metric__bar--warn' : 'home-metric__bar--ok';
    const bar = (p) => '<div class="home-metric__bar"><span class="' + barCls(p) + '" style="width:' + Math.min(100,Math.max(0,p)) + '%"></span></div>';
    const now = new Date().toTimeString().slice(0,8);

    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\uc2dc\uc2a4\ud15c \u00b7 GPU \ud604\ud669</h2>' +
      '  <span class="u-badge u-badge--info">live \u00b7 ' + now + '</span>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-yudi-metrics">' +
      '    <div class="home-metric">' +
      '      <div class="home-metric__label">GPU \u00b7 ' + Utils.esc(gpuName.replace('NVIDIA GeForce ','')) + '</div>' +
      '      <div class="home-metric__value">' + gpuUtil + '<small>%</small>' + (gpuTemp!=null ? ' <small style="color:var(--muted)">'+gpuTemp+'\u00b0</small>' : '') + '</div>' +
             bar(gpuUtil) +
      '      <div class="home-metric__sub">VRAM ' + (Math.round(vramUsed/1024)) + '/' + (Math.round(vramTotal/1024)) + 'GB \u00b7 ' + vramPct + '%</div>' +
      '    </div>' +
      '    <div class="home-metric">' +
      '      <div class="home-metric__label">CPU \u00b7 RAM</div>' +
      '      <div class="home-metric__value">' + cpu + '<small>%</small></div>' +
             bar(cpu) +
      '      <div class="home-metric__sub">RAM ' + Math.round(ramUsed/1024) + '/' + Math.round(ramTotal/1024) + 'GB \u00b7 ' + ramPct + '%</div>' +
      '    </div>' +
      '    <div class="home-metric">' +
      '      <div class="home-metric__label">Supervisor</div>' +
      '      <div class="home-metric__value">' + (sv.total || 0) + '</div>' +
      '      <div class="home-metric__sub">avg ' + (sv.avg_score || 0).toFixed(2) + ' \u00b7 today ' + (sv.today || 0) + ' \u00b7 pending ' + (sv.pending || 0) + '</div>' +
      '    </div>' +
      '    <div class="home-metric">' +
      '      <div class="home-metric__label">\ubaa8\ub378 \u00b7 \uc138\uc158</div>' +
      '      <div class="home-metric__value home-metric__value--sm">' + Utils.esc(svModel || '-') + '</div>' +
      '      <div class="home-metric__sub">\ud65c\uc131 \uc138\uc158 ' + sessions + ' \u00b7 \uba54\ubaa8\ub9ac ' + (ol.model_count || 0) + '</div>' +
      '    </div>' +
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
    const num = (n) => Number(n||0).toLocaleString('ko-KR');
    el.innerHTML =
      '<div class="u-panel__header">' +
      '  <h2 class="u-panel__title">\uc9c4\ud589 \ud604\ud669</h2>' +
      '  <button class="u-btn u-btn--sm u-btn--ghost" onclick="Router.navigate(\'#/teams\')">\ud300 \ubcf4\uae30 \u203a</button>' +
      '</div>' +
      '<div class="u-panel__body">' +
      '  <div class="home-stat-grid">' +
      '    <div class="home-stat" onclick="Router.navigate(\'#/teams\')"><div class="home-stat__value">' + num(active) + '</div><div class="home-stat__label">\uc9c4\ud589 \uc911\uc778 \ud300</div></div>' +
      '    <div class="home-stat"><div class="home-stat__value">' + num(inProgress) + '</div><div class="home-stat__label">\uc9c4\ud589 \ud2f0\ucf13</div></div>' +
      '    <div class="home-stat"><div class="home-stat__value home-stat__value--ok">' + pct + '<small>%</small></div><div class="home-stat__label">\uc644\ub8cc\uc728</div></div>' +
      '    <div class="home-stat"><div class="home-stat__value' + (blocked>0?' home-stat__value--danger':'') + '">' + num(blocked) + '</div><div class="home-stat__label">Blocked</div></div>' +
      '  </div>' +
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

  async _renderHeatmap() {
    const el = document.getElementById('homeHeatmapCard');
    if (!el) return;
    el.innerHTML =
      '<div class="u-panel__header"><h2 class="u-panel__title">Activity 48h</h2></div>' +
      '<div class="u-panel__body home-heatmap__body" id="homeHeatmapBody"></div>';
    const body = document.getElementById('homeHeatmapBody');
    try {
      const res = await API.heatmap10min();
      const buckets = (res && res.data) || [];
      if (!buckets.length) {
        body.innerHTML = '<div class="u-empty"><div class="u-empty__desc">\ub370\uc774\ud130 \uc5c6\uc74c</div></div>';
        return;
      }
      const max = Math.max(1, ...buckets.map(b => (typeof b === 'number' ? b : (b.count || b.value || 0))));
      const html = buckets.slice(-288).map(b => {
        const count = typeof b === 'number' ? b : (b.count || b.value || 0);
        const ts = typeof b === 'object' ? (b.ts || b.time || '') : '';
        const intensity = Math.min(1, count / max);
        return '<div class="home-heatmap__cell" style="--heat:' + intensity.toFixed(2) + '" title="' + Utils.esc(String(ts)) + ' \u00b7 ' + count + '"></div>';
      }).join('');
      body.innerHTML = '<div class="home-heatmap__grid">' + html + '</div>';
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
