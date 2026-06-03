/* U2DIA — Settings 뷰 (ShipOS-tier, 2026-04-18) */

const SettingsView = {
  TABS: [
    { key: 'general', label: '일반',          icon: 'settings' },
    { key: 'tokens',  label: '토큰',          icon: 'key' },
    { key: 'clients', label: '클라이언트',    icon: 'users' },
    { key: 'metrics', label: '시스템 메트릭', icon: 'activity' },
    { key: 'hooks',   label: 'Hooks',          icon: 'zap' },
    { key: 'notif',   label: '알림',          icon: 'bell' },
    { key: 'danger',  label: '위험 작업',     icon: 'trash' }
  ],

  /* ─────────────────────────────────
     Sidebar 리스트 (탭 네비게이터)
  ───────────────────────────────── */
  async renderList(listEl, activeTab) {
    const active = activeTab || 'general';
    const items = this.TABS.map(t => {
      const cls = 'u-list-item' + (t.key === active ? ' u-list-item--active' : '');
      return (
        '<div class="' + cls + '" onclick="Router.navigate(\'#/settings/' + t.key + '\')">' +
          '<span style="display:inline-flex;align-items:center;gap:10px;flex:1;min-width:0">' +
            '<span style="color:var(--text-muted-new);display:flex">' + Utils.icon(t.icon, 14, 1.75) + '</span>' +
            '<span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">' + Utils.esc(t.label) + '</span>' +
          '</span>' +
        '</div>'
      );
    }).join('');
    listEl.innerHTML =
      '<div class="shell-list__header"><span class="shell-list__title">설정</span><span class="u-badge">' + this.TABS.length + '</span></div>' +
      '<div class="shell-list__body">' + items + '</div>';
  },

  /* ─────────────────────────────────
     본문 라우터
  ───────────────────────────────── */
  render(mainEl, tab) {
    tab = tab || 'general';
    const map = {
      general: () => this._renderGeneral(mainEl),
      tokens:  () => this._renderTokens(mainEl),
      clients: () => this._renderClients(mainEl),
      metrics: () => this._renderMetrics(mainEl),
      hooks:   () => this._renderHooks(mainEl),
      notif:   () => this._renderNotif(mainEl),
      danger:  () => this._renderDanger(mainEl)
    };
    (map[tab] || map.general)();
  },

  /* ─────────────────────────────────
     공통 헬퍼
  ───────────────────────────────── */
  _pageShell(title, subtitle, actions, body) {
    return (
      '<div class="settings-page">' +
        '<div class="settings-page__header">' +
          '<div>' +
            '<h1 class="settings-page__title">' + Utils.esc(title) + '</h1>' +
            (subtitle ? '<div class="settings-page__subtitle">' + Utils.esc(subtitle) + '</div>' : '') +
          '</div>' +
          '<div class="settings-page__actions">' + (actions || '') + '</div>' +
        '</div>' +
        body +
      '</div>'
    );
  },

  _section(title, desc, iconName, bodyHTML, footerHTML, extraClass) {
    const iconHTML = iconName ? Utils.icon(iconName, 16, 1.75) : '';
    return (
      '<section class="sec-card ' + (extraClass || '') + '">' +
        '<div class="sec-card__header">' +
          '<div class="sec-card__title">' + iconHTML + '<span>' + Utils.esc(title) + '</span></div>' +
          (desc ? '<div class="sec-card__desc">' + Utils.esc(desc) + '</div>' : '') +
        '</div>' +
        '<div class="sec-card__body sec-card__body--tight">' + bodyHTML + '</div>' +
        (footerHTML ? '<div class="sec-card__footer">' + footerHTML + '</div>' : '') +
      '</section>'
    );
  },

  _field(label, hint, controlHTML) {
    return (
      '<div class="field-row">' +
        '<div class="field-row__text">' +
          '<div class="field-row__label">' + Utils.esc(label) + '</div>' +
          (hint ? '<div class="field-row__hint">' + Utils.esc(hint) + '</div>' : '') +
        '</div>' +
        '<div class="field-row__control">' + controlHTML + '</div>' +
      '</div>'
    );
  },

  _switch(id, checked, onchange) {
    return (
      '<label class="switch">' +
        '<input type="checkbox" id="' + id + '" class="switch__input"' + (checked ? ' checked' : '') +
          (onchange ? ' onchange="' + onchange + '"' : '') + '>' +
        '<span class="switch__track"></span>' +
        '<span class="switch__knob"></span>' +
      '</label>'
    );
  },

  _segmented(name, options, activeKey, onSelect) {
    return (
      '<div class="segmented" role="tablist" aria-label="' + Utils.esc(name) + '">' +
        options.map(o =>
          '<button class="segmented__btn' + (o.key === activeKey ? ' segmented__btn--active' : '') + '"' +
            ' role="tab" aria-selected="' + (o.key === activeKey ? 'true' : 'false') + '"' +
            ' onclick="' + onSelect + '(\'' + o.key + '\')">' + Utils.esc(o.label) + '</button>'
        ).join('') +
      '</div>'
    );
  },

  /* ═════════════════════════════════
     1. 일반
  ═════════════════════════════════ */
  _renderGeneral(el) {
    const theme = localStorage.getItem('u2dia.theme') || 'dark';
    const lang = localStorage.getItem('u2dia.lang') || 'ko';
    const backend = localStorage.getItem('u2dia.yudiBackend') || 'anthropic';
    const compactMode = localStorage.getItem('u2dia.compact') === 'true';
    const soundOn = localStorage.getItem('u2dia.sound') !== 'false';
    const version = (window.APP_VERSION || '8.0.0');

    const appearanceBody =
      this._field('테마', '현재는 다크만 지원합니다. 라이트 테마는 준비 중입니다.',
        this._segmented('theme',
          [{ key:'dark', label:'다크' }, { key:'light', label:'라이트' }, { key:'auto', label:'시스템' }],
          theme, 'SettingsView._setTheme'
        )
      ) +
      this._field('컴팩트 모드', '여백과 행 높이를 줄여 화면 정보 밀도를 높입니다.',
        this._switch('swCompact', compactMode, 'SettingsView._setCompact(this.checked)')
      ) +
      this._field('언어', '인터페이스 언어를 선택합니다. 일부 영역은 재시작이 필요합니다.',
        '<select class="settings-select" onchange="SettingsView._setLang(this.value)">' +
          ['ko','en','ja','zh'].map(v =>
            '<option value="' + v + '"' + (v===lang?' selected':'') + '>' + ({ko:'한국어',en:'English',ja:'日本語',zh:'中文'}[v]) + '</option>'
          ).join('') +
        '</select>'
      );

    const yudiBody =
      this._field('기본 백엔드', '유디가 우선으로 사용할 LLM 백엔드입니다.',
        this._segmented('backend',
          [{ key:'anthropic', label:'Claude' }, { key:'ollama', label:'Ollama' }, { key:'nim', label:'NIM' }],
          backend, 'SettingsView._setBackend'
        )
      ) +
      this._field('Supervisor 모델',
        '검수 자동화에 사용되는 LLM 모델입니다. 부하가 크면 가벼운 모델로 전환하세요.',
        '<div id="supervisorModelSlot" style="display:flex;gap:8px;flex-wrap:wrap;align-items:center">' +
        '  <span style="font-size:11px;color:var(--text-muted-new)">로딩...</span>' +
        '</div>'
      ) +
      this._field('시스템 사운드', '알림 도착 시 짧은 소리를 재생합니다.',
        this._switch('swSound', soundOn, 'SettingsView._setSound(this.checked)')
      );
    setTimeout(() => SettingsView._loadSupervisorModel(), 100);

    const infoBody =
      this._field('앱 버전', '현재 실행 중인 서버/프론트 버전입니다.',
        '<code style="font-family:var(--mono);font-size:var(--text-sm);color:var(--text-muted-new)">v' + Utils.esc(version) + '</code>'
      ) +
      this._field('DB 위치', 'SQLite 데이터베이스 파일 경로',
        '<code style="font-family:var(--mono);font-size:var(--text-xs);color:var(--text-muted-new)">data/agents_team.db</code>'
      ) +
      this._field('서버 포트', 'HTTP 및 MCP 엔드포인트 포트',
        '<code style="font-family:var(--mono);font-size:var(--text-sm);color:var(--brand-light)">' + location.port + '</code>'
      );

    el.innerHTML = this._pageShell(
      '일반', '테마·언어·유디 백엔드 같은 기본 동작을 설정합니다.', '',
      this._section('모양', '사용자 인터페이스의 외형을 조정합니다.', 'settings', appearanceBody) +
      this._section('유디 AI', '유디 에이전트의 동작 환경을 설정합니다.', 'cpu', yudiBody) +
      this._section('시스템 정보', '현재 실행 환경에 대한 정보입니다.', 'info', infoBody)
    );
  },

  _setTheme(v) { localStorage.setItem('u2dia.theme', v); SettingsView._renderGeneral(document.getElementById('shellMain')); },
  _setCompact(v) { localStorage.setItem('u2dia.compact', v ? 'true' : 'false'); document.documentElement.classList.toggle('u2dia-compact', v); },
  _setLang(v) { localStorage.setItem('u2dia.lang', v); },
  _setBackend(v) { localStorage.setItem('u2dia.yudiBackend', v); SettingsView._renderGeneral(document.getElementById('shellMain')); },
  _setSound(v) { localStorage.setItem('u2dia.sound', v ? 'true' : 'false'); },

  async _loadSupervisorModel() {
    const slot = document.getElementById('supervisorModelSlot');
    if (!slot) return;
    try {
      const res = await fetch('/api/settings/supervisor_model').then(r => r.json());
      if (!res.ok) {
        slot.innerHTML = '<span style="color:var(--red,#ef4444);font-size:11px">로딩 실패</span>';
        return;
      }
      const opts = (res.models || []).map(m =>
        '<option value="' + Utils.esc(m.id) + '"' + (m.id === res.current ? ' selected' : '') + '>' +
          Utils.esc(m.name) + ' (' + Utils.esc(m.provider) + ')' +
        '</option>'
      ).join('');
      slot.innerHTML =
        '<select class="settings-select" id="supervisorModelSel" style="min-width:240px" onchange="SettingsView._setSupervisorModel(this.value)">' +
          opts +
        '</select>' +
        '<button class="u-btn u-btn--sm" id="supervisorHealthBtn" onclick="SettingsView._healthSupervisor()">상태 확인</button>' +
        '<span id="supervisorHealthHint" style="font-size:11px;color:var(--text-muted-new);margin-left:8px"></span>';
      const cur = (res.models || []).find(m => m.id === res.current);
      if (cur && cur.description) {
        const hint = document.getElementById('supervisorHealthHint');
        if (hint) hint.textContent = cur.description;
      }
    } catch (e) {
      slot.innerHTML = '<span style="color:var(--red);font-size:11px">' + Utils.esc(e.message || e) + '</span>';
    }
  },

  async _setSupervisorModel(model) {
    const hint = document.getElementById('supervisorHealthHint');
    if (hint) hint.textContent = '저장 중...';
    try {
      const res = await fetch('/api/settings/supervisor_model', {
        method: 'PUT', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({model: model})
      }).then(r => r.json());
      if (res.ok) {
        if (hint) hint.textContent = '✅ 저장됨 — 다음 검수부터 적용';
        setTimeout(() => SettingsView._loadSupervisorModel(), 1500);
      } else {
        if (hint) hint.textContent = '❌ ' + (res.error || '실패');
      }
    } catch(e) {
      if (hint) hint.textContent = '❌ ' + (e.message || e);
    }
  },

  async _healthSupervisor() {
    const sel = document.getElementById('supervisorModelSel');
    const btn = document.getElementById('supervisorHealthBtn');
    const hint = document.getElementById('supervisorHealthHint');
    if (!sel) return;
    if (btn) { btn.disabled = true; btn.textContent = '확인 중...'; }
    if (hint) hint.textContent = '...';
    try {
      const res = await fetch('/api/settings/supervisor_model/health', {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({model: sel.value})
      }).then(r => r.json());
      if (res.ok && res.healthy) {
        if (hint) hint.textContent = '🟢 OK (' + (res.latency_ms || '-') + 'ms) — ' + (res.response_preview || '').slice(0, 40);
      } else {
        if (hint) hint.textContent = '🔴 실패: ' + (res.error || res.message || '응답 없음');
      }
    } catch (e) {
      if (hint) hint.textContent = '🔴 ' + (e.message || e);
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = '상태 확인'; }
    }
  },

  /* ═════════════════════════════════
     2. 토큰
  ═════════════════════════════════ */
  async _renderTokens(el) {
    const createForm =
      '<div style="display:flex;gap:var(--space-2);align-items:center;padding:var(--space-4) var(--section-card-pad-x);border-bottom:1px solid var(--divider);flex-wrap:wrap">' +
        '<input class="settings-input" id="tokNewLabel" placeholder="라벨 (예: my-project)" style="flex:1;min-width:220px">' +
        '<select class="settings-select" id="tokNewPerms" style="min-width:140px">' +
          '<option value="agent">agent</option>' +
          '<option value="admin">admin</option>' +
          '<option value="readonly">readonly</option>' +
        '</select>' +
        '<button class="u-btn u-btn--primary" onclick="SettingsView._createToken()">' +
          Utils.icon('plus', 14, 2) + '<span style="margin-left:4px">토큰 발급</span>' +
        '</button>' +
      '</div>';
    const tokensHTML =
      '<div id="tokList"><div class="settings-empty">' + Utils.icon('loader', 18, 2) + ' 불러오는 중…</div></div>';

    const actions =
      '<button class="u-btn u-btn--sm u-btn--ghost" onclick="SettingsView._refreshTokens()">' +
        Utils.icon('refresh', 13, 2) + '<span style="margin-left:4px">새로고침</span>' +
      '</button>';

    el.innerHTML = this._pageShell(
      '토큰', '외부 프로젝트가 이 서버에 접속할 때 사용할 인증 토큰을 관리합니다.',
      actions,
      this._section('신규 토큰 발급', '라벨과 권한 수준을 지정하면 발급 직후 1회 전체 값이 노출됩니다.',
        'key', createForm
      ) +
      this._section('발급된 토큰', '저장된 토큰 목록입니다. 토큰 값은 발급 직후 1회만 전체 노출됩니다.',
        'shield', tokensHTML
      )
    );
    await this._refreshTokens();
  },

  async _refreshTokens() {
    const list = document.getElementById('tokList');
    if (!list) return;
    try {
      const res = await API.get('/api/tokens');
      const tokens = (res && res.tokens) || [];
      if (!tokens.length) {
        list.innerHTML = '<div class="settings-empty">아직 발급된 토큰이 없습니다.</div>';
        return;
      }
      list.innerHTML = tokens.map(t => {
        const display = t.token_display || (t.token || '').slice(0,4) + '-****-****-' + (t.token || '').slice(-4);
        const perms = (t.permissions || 'agent');
        const created = t.created_at ? Utils.dateFmt(t.created_at) : '';
        return (
          '<div class="data-row">' +
            '<div class="data-row__primary">' +
              '<div class="data-row__title">' + Utils.esc(t.name || t.label || t.token_id) +
                ' <span class="u-badge" style="margin-left:8px">' + Utils.esc(perms) + '</span>' +
              '</div>' +
              '<div class="data-row__sub">' + Utils.esc(display) + '</div>' +
            '</div>' +
            '<div class="data-row__meta">' + Utils.esc(created) + '</div>' +
            '<div style="display:flex;gap:6px">' +
              '<button class="token-copy-btn" onclick="SettingsView._copyToken(\'' + Utils.esc(t.token || '') + '\', this)">복사</button>' +
              '<button class="u-btn u-btn--sm u-btn--danger u-btn--ghost" onclick="SettingsView._deleteToken(\'' + Utils.esc(t.token_id) + '\')">' +
                Utils.icon('trash', 12, 2) +
              '</button>' +
            '</div>' +
          '</div>'
        );
      }).join('');
    } catch(e) {
      list.innerHTML = '<div class="settings-empty">토큰 목록을 불러올 수 없습니다. 서버 연결을 확인하세요.</div>';
    }
  },

  async _createToken() {
    const labelEl = document.getElementById('tokNewLabel');
    const permsEl = document.getElementById('tokNewPerms');
    if (!labelEl) return;
    const label = labelEl.value.trim();
    if (!label) { labelEl.focus(); labelEl.style.borderColor = 'var(--red)'; return; }
    const permissions = (permsEl && permsEl.value) || 'agent';
    try {
      const res = await API.post('/api/tokens', { name: label, label, permissions });
      labelEl.value = '';
      if (res && res.token && res.token.token) {
        alert('새 토큰 (이번에만 전체 값이 노출됩니다):\n\n' + res.token.token);
      }
      await this._refreshTokens();
    } catch(e) { alert('생성 실패: ' + e.message); }
  },

  async _deleteToken(id) {
    if (!confirm('이 토큰을 삭제하시겠습니까? 연결된 프로젝트는 즉시 인증이 끊깁니다.')) return;
    try {
      await fetch('/api/tokens/' + encodeURIComponent(id), { method: 'DELETE' });
      await this._refreshTokens();
    } catch(e) { alert('삭제 실패: ' + e.message); }
  },

  _copyToken(token, btn) {
    if (!token) return;
    try {
      navigator.clipboard.writeText(token);
      btn.classList.add('token-copy-btn--copied');
      btn.textContent = '복사됨';
      setTimeout(() => { btn.classList.remove('token-copy-btn--copied'); btn.textContent = '복사'; }, 1500);
    } catch(e) {}
  },

  /* ═════════════════════════════════
     3. 클라이언트
  ═════════════════════════════════ */
  async _renderClients(el) {
    el.innerHTML = this._pageShell(
      '연결된 클라이언트',
      '이 서버에 HTTP/MCP/SSE 로 접속 중인 클라이언트 목록입니다.',
      '<button class="u-btn u-btn--sm u-btn--ghost" onclick="SettingsView._renderClients(document.getElementById(\'shellMain\'))">' +
        Utils.icon('refresh', 13, 2) + '<span style="margin-left:4px">새로고침</span>' +
      '</button>',
      this._section('활성 세션', '최근 5분 이내 요청이 있었던 클라이언트입니다.', 'users',
        '<div id="cliList"><div class="settings-empty">' + Utils.icon('loader', 18, 2) + ' 불러오는 중…</div></div>'
      )
    );
    try {
      const res = await API.get('/api/system/clients');
      const list = (res && res.clients) || [];
      const wrap = document.getElementById('cliList');
      if (!list.length) {
        wrap.innerHTML = '<div class="settings-empty">연결된 클라이언트가 없습니다.</div>';
        return;
      }
      wrap.innerHTML = list.map(c => {
        const ua = c.user_agent || '';
        const short = ua.length > 80 ? ua.slice(0,80) + '…' : ua;
        return (
          '<div class="data-row">' +
            '<div class="data-row__primary">' +
              '<div class="data-row__title"><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--green);margin-right:8px"></span>' +
                Utils.esc(c.ip || c.client_id || '-') +
              '</div>' +
              '<div class="data-row__sub">' + Utils.esc(short) + '</div>' +
            '</div>' +
            '<div class="data-row__meta">' + (c.last_seen ? Utils.dateFmt(c.last_seen) : '-') + '</div>' +
            '<div></div>' +
          '</div>'
        );
      }).join('');
    } catch(e) {
      const wrap = document.getElementById('cliList');
      if (wrap) wrap.innerHTML = '<div class="settings-empty">로딩 실패.</div>';
    }
  },

  /* ═════════════════════════════════
     4. 시스템 메트릭
  ═════════════════════════════════ */
  async _renderMetrics(el) {
    el.innerHTML = this._pageShell(
      '시스템 메트릭',
      '서버 호스트의 실시간 리소스 · GPU · 온도 vital 입니다. 10초마다 갱신됩니다.',
      '<span class="u-badge u-badge--info" id="metRefresh" style="font-variant-numeric:tabular-nums">live · -- s</span>',
      this._section('Vital', '호스트 OS · GPU · 온도 센서 · 노드 현황.', 'activity',
        '<div id="metBody" style="padding:var(--space-4) var(--section-card-pad-x)"><div class="u-skeleton u-skeleton--block"></div></div>'
      )
    );
    if (this._metricsTimer) clearInterval(this._metricsTimer);

    const tick = async () => {
      try {
        const r = await API.get('/api/system/metrics');
        const m = (r && r.metrics) || r || {};
        const target = document.getElementById('metBody');
        if (!target) { clearInterval(this._metricsTimer); return; }

        const round = (n) => Math.round(Number(n) || 0);
        const fmtN = (n) => (Math.round(Number(n) || 0)).toLocaleString('ko-KR');
        const gb = (mb) => (Number(mb || 0) / 1024).toFixed(1);
        const tempColor = (t) => t >= 80 ? 'var(--red)' : t >= 65 ? 'var(--orange)' : t >= 50 ? 'var(--yellow)' : 'var(--green)';
        const G = (typeof SvgCharts !== 'undefined');

        const gauge = (label, val, sub) =>
          '<div class="met-gauge">' +
            (G ? SvgCharts.gauge(val, { size: 120, thresholds: [70, 90] }) : '<div style="font-size:24px;font-weight:800">' + round(val) + '%</div>') +
            '<div class="met-gauge__label">' + label + '</div>' +
            '<div class="met-gauge__sub">' + sub + '</div>' +
          '</div>';
        const stat = (k, v, sub) =>
          '<div class="met-stat"><div class="met-stat__k">' + k + '</div>' +
          '<div class="met-stat__v">' + v + (sub ? ' <small>' + sub + '</small>' : '') + '</div></div>';

        // 리소스 게이지 (CPU · RAM · 디스크 · GPU)
        const memPct = round(m.memory_percent);
        const diskPct = round(m.disk_percent);
        const gpuUtil = round(m.gpu_util);
        const gauges =
          '<div class="met-gauges">' +
            gauge('CPU', round(m.cpu_percent), (m.load_avg ? 'load ' + (m.load_avg[0] != null ? m.load_avg[0] : '-') : '사용률')) +
            gauge('메모리', memPct, gb(m.memory_used_mb) + ' / ' + gb(m.memory_total_mb) + ' GB') +
            gauge('디스크', diskPct, round(m.disk_used_gb) + ' / ' + round(m.disk_total_gb) + ' GB') +
            gauge('GPU', gpuUtil, Utils.esc((m.gpu_name || 'GPU').replace('NVIDIA GeForce ', ''))) +
          '</div>';

        // GPU 상세
        const vramPct = round(m.gpu_vram_percent != null ? m.gpu_vram_percent : (m.gpu_vram_total_mb ? m.gpu_vram_used_mb / m.gpu_vram_total_mb * 100 : 0));
        const powPct = m.gpu_power_max_w ? round(m.gpu_power_w / m.gpu_power_max_w * 100) : 0;
        const gpuBlock =
          '<div class="met-sub-title">GPU · ' + Utils.esc((m.gpu_name || '-').replace('NVIDIA GeForce ', '')) + '</div>' +
          '<div class="met-stats">' +
            stat('사용률', gpuUtil + '%') +
            stat('온도', '<span style="color:' + tempColor(round(m.gpu_temp)) + '">' + round(m.gpu_temp) + '°</span>') +
            stat('VRAM', gb(m.gpu_vram_used_mb) + ' / ' + gb(m.gpu_vram_total_mb), 'GB · ' + vramPct + '%') +
            stat('전력', round(m.gpu_power_w) + ' / ' + round(m.gpu_power_max_w), 'W · ' + powPct + '%') +
            stat('팬', round(m.gpu_fan_percent) + '%') +
          '</div>';

        // 온도 센서
        const temps = Array.isArray(m.temps) ? m.temps : [];
        const tempBlock = temps.length ?
          '<div class="met-sub-title">온도 센서 · ' + temps.length + '</div>' +
          '<div class="met-temps">' +
            temps.map(t => {
              const tv = Number(t.temp) || 0;
              return '<div class="met-temp"><div class="met-temp__n">' + Utils.esc(t.name) + '</div>' +
                '<div class="met-temp__v" style="color:' + tempColor(tv) + '">' + tv.toFixed(1) + '°</div>' +
                '<div class="met-temp__bar"><span style="width:' + Math.min(100, tv) + '%;background:' + tempColor(tv) + '"></span></div></div>';
            }).join('') +
          '</div>' : '';

        // 호스트 · 네트워크 · 노드
        const la = Array.isArray(m.load_avg) ? m.load_avg : [];
        const hostBlock =
          '<div class="met-sub-title">호스트 · 노드</div>' +
          '<div class="met-stats">' +
            stat('호스트', Utils.esc(m.hostname || '-'), Utils.esc(m.platform || '')) +
            stat('Python', Utils.esc(m.python_version || '-')) +
            stat('Load Avg', la.length ? la.map(x => Number(x).toFixed(1)).join(' · ') : '-', '1·5·15m') +
            stat('DB 크기', (m.db_size_mb != null ? m.db_size_mb : 0) + '', 'MB') +
            stat('활성 팀', fmtN(m.active_teams), '팀') +
            stat('활성 티켓', fmtN(m.active_tickets), '티켓') +
            stat('SSE 클라이언트', fmtN(m.sse_clients)) +
            stat('노드', fmtN(m.node_count), gb(m.node_memory_mb) + 'GB') +
            stat('네트워크', '↑' + fmtN(m.net_sent_kb) + ' ↓' + fmtN(m.net_recv_kb), 'KB/s') +
          '</div>';

        target.innerHTML = gauges + gpuBlock + tempBlock + hostBlock;
      } catch (e) {
        const target = document.getElementById('metBody');
        if (target) target.innerHTML = '<div class="settings-empty">메트릭을 불러올 수 없습니다.</div>';
      }
    };

    await tick();
    let n = 10;
    this._metricsTimer = setInterval(() => {
      n -= 1;
      const b = document.getElementById('metRefresh');
      if (b) b.textContent = 'live · ' + n + ' s';
      if (n <= 0) { n = 10; tick(); }
    }, 1000);
  },

  /* ═════════════════════════════════
     5. Hooks
  ═════════════════════════════════ */
  async _renderHooks(el) {
    el.innerHTML = this._pageShell(
      'Hooks 모니터',
      'Claude Code 훅 이벤트를 실시간으로 수집/집계합니다.',
      '<button class="u-btn u-btn--sm u-btn--ghost" onclick="SettingsView._renderHooks(document.getElementById(\'shellMain\'))">' +
        Utils.icon('refresh', 13, 2) + '<span style="margin-left:4px">새로고침</span>' +
      '</button>',
      this._section('요약', '전체 이벤트 수와 종류별 분포입니다.', 'activity',
        '<div id="hooksStats" style="padding:var(--space-4) var(--section-card-pad-x)"><div class="u-skeleton u-skeleton--block"></div></div>'
      ) +
      this._section('최근 이벤트', '최근 20개 훅 이벤트입니다.', 'zap',
        '<div id="hooksEvents"><div class="settings-empty">' + Utils.icon('loader', 18, 2) + ' 불러오는 중…</div></div>'
      )
    );
    try {
      const [statsRes, eventsRes] = await Promise.all([
        API.get('/api/hooks/stats').catch(() => null),
        API.get('/api/hooks/events?limit=20').catch(() => null)
      ]);
      const statsEl = document.getElementById('hooksStats');
      if (statsRes) {
        const total = statsRes.total || 0;
        const byKind = statsRes.by_kind || {};
        const kindKeys = Object.keys(byKind);
        statsEl.innerHTML =
          '<div class="kpi-grid" style="margin-bottom:var(--space-3)">' +
            '<div class="kpi-tile kpi-tile--accent"><div class="kpi-tile__label">전체</div><div class="kpi-tile__value">' + total.toLocaleString() + '</div></div>' +
            '<div class="kpi-tile"><div class="kpi-tile__label">종류</div><div class="kpi-tile__value">' + kindKeys.length + '</div></div>' +
            (statsRes.last_24h ? '<div class="kpi-tile"><div class="kpi-tile__label">24h</div><div class="kpi-tile__value">' + statsRes.last_24h + '</div></div>' : '') +
          '</div>' +
          (kindKeys.length ?
            '<div style="display:grid;grid-template-columns:1fr 1fr;gap:var(--space-2)">' +
              kindKeys.map(k =>
                '<div style="display:flex;justify-content:space-between;align-items:center;padding:8px 12px;background:var(--surface-2);border:1px solid var(--line);border-radius:var(--radius-md);font-size:var(--text-sm)">' +
                  '<span>' + Utils.esc(k) + '</span>' +
                  '<span class="u-badge" style="font-variant-numeric:tabular-nums">' + byKind[k] + '</span>' +
                '</div>'
              ).join('') +
            '</div>' : '');
      } else {
        statsEl.innerHTML = '<div class="settings-empty">통계 로딩 실패.</div>';
      }
      const eventsEl = document.getElementById('hooksEvents');
      const events = (eventsRes && eventsRes.events) || [];
      if (!events.length) {
        eventsEl.innerHTML = '<div class="settings-empty">수신된 이벤트가 없습니다.</div>';
      } else {
        eventsEl.innerHTML = '<div class="event-feed">' + events.map(ev =>
          '<div class="event-row">' +
            '<span class="event-row__time">' + Utils.esc(Utils.dateFmt(ev.received_at || ev.timestamp || '')) + '</span>' +
            '<span class="event-row__icon">' + Utils.icon('zap', 14, 2) + '</span>' +
            '<span class="event-row__kind">' + Utils.esc(ev.kind || ev.event || '-') + '</span>' +
            '<span class="event-row__project">' + Utils.esc(ev.project || 'local') + '</span>' +
          '</div>'
        ).join('') + '</div>';
      }
    } catch(e) {}
  },

  /* ═════════════════════════════════
     6. 알림
  ═════════════════════════════════ */
  _renderNotif(el) {
    const perm = ('Notification' in window) ? Notification.permission : 'unsupported';
    const permLabel = { granted:'허용됨', denied:'거부됨', default:'미설정', unsupported:'지원 안 함' }[perm] || perm;
    const permColor = perm === 'granted' ? 'var(--green)' : perm === 'denied' ? 'var(--red-light)' : 'var(--orange)';
    const tgToken = localStorage.getItem('u2dia.tgToken') || '';
    const tgChat = localStorage.getItem('u2dia.tgChat') || '';
    const emailOn = localStorage.getItem('u2dia.emailNotif') === 'true';

    const browserBody =
      this._field('브라우저 알림 권한',
        '시스템 알림으로 티켓 변경·에러를 받아볼 수 있습니다.',
        '<div style="display:flex;align-items:center;gap:var(--space-2)">' +
          '<span style="display:inline-flex;align-items:center;gap:6px;font-size:var(--text-sm);color:' + permColor + '">' +
            '<span style="width:8px;height:8px;border-radius:50%;background:currentColor"></span>' + Utils.esc(permLabel) +
          '</span>' +
          (perm !== 'granted' && perm !== 'unsupported' ?
            '<button class="u-btn u-btn--sm u-btn--primary" onclick="SettingsView._requestNotif()">권한 요청</button>' : '') +
        '</div>'
      ) +
      this._field('테스트 알림', '설정이 제대로 작동하는지 확인합니다.',
        '<button class="u-btn u-btn--sm" onclick="SettingsView._testNotif()">' +
          Utils.icon('bell', 13, 2) + '<span style="margin-left:4px">테스트 발송</span>' +
        '</button>'
      );

    const tgBody =
      '<div style="padding:var(--space-4) var(--section-card-pad-x);display:flex;flex-direction:column;gap:var(--space-3)">' +
        '<label style="display:block">' +
          '<div class="field-row__label" style="margin-bottom:6px">봇 토큰</div>' +
          '<input class="settings-input" id="tgTokenInput" type="password" placeholder="1234567890:AAA…" value="' + Utils.esc(tgToken) + '" style="width:100%;max-width:none">' +
        '</label>' +
        '<label style="display:block">' +
          '<div class="field-row__label" style="margin-bottom:6px">Chat ID</div>' +
          '<input class="settings-input" id="tgChatInput" placeholder="대상 채팅 ID" value="' + Utils.esc(tgChat) + '" style="width:100%;max-width:none">' +
        '</label>' +
        '<div style="display:flex;gap:var(--space-2);margin-top:4px">' +
          '<button class="u-btn u-btn--primary u-btn--sm" onclick="SettingsView._saveTelegram()">저장</button>' +
          '<button class="u-btn u-btn--sm" onclick="SettingsView._testTelegram()">연결 테스트</button>' +
        '</div>' +
      '</div>';

    const emailBody =
      this._field('이메일 요약', '하루 1회 티켓 변경 요약을 이메일로 발송합니다.',
        this._switch('swEmail', emailOn, 'SettingsView._setEmail(this.checked)')
      );

    el.innerHTML = this._pageShell(
      '알림', '브라우저·텔레그램·이메일 알림 채널을 관리합니다.', '',
      this._section('브라우저', '시스템 데스크톱 알림입니다.', 'bell', browserBody) +
      this._section('텔레그램', '유디 봇과 연동하여 채팅으로 알림을 받습니다.', 'send', tgBody) +
      this._section('이메일', '정기 요약을 받는 채널입니다.', 'mail', emailBody)
    );
  },

  _requestNotif() {
    if (!('Notification' in window)) return;
    Notification.requestPermission().then(() => SettingsView._renderNotif(document.getElementById('shellMain')));
  },
  _testNotif() {
    if (typeof BrowserNotify !== 'undefined' && BrowserNotify.show) {
      BrowserNotify.show('유디AI 테스트 알림', '알림 채널이 정상 작동합니다.');
    } else if ('Notification' in window && Notification.permission === 'granted') {
      new Notification('유디AI 테스트 알림', { body: '알림 채널이 정상 작동합니다.' });
    }
  },
  _saveTelegram() {
    const tk = document.getElementById('tgTokenInput').value.trim();
    const ch = document.getElementById('tgChatInput').value.trim();
    localStorage.setItem('u2dia.tgToken', tk);
    localStorage.setItem('u2dia.tgChat', ch);
    alert('저장되었습니다.');
  },
  async _testTelegram() {
    try {
      const res = await API.post('/api/telegram/test', {});
      alert(res && res.ok ? '텔레그램 테스트 메시지 발송 완료' : '발송 실패');
    } catch(e) { alert('연동 실패: ' + e.message); }
  },
  _setEmail(v) { localStorage.setItem('u2dia.emailNotif', v ? 'true' : 'false'); },

  /* ═════════════════════════════════
     7. 위험 작업
  ═════════════════════════════════ */
  _renderDanger(el) {
    const zombieBody =
      this._field('좀비 MCP/Node 프로세스 종료',
        '응답하지 않는 MCP/Node 프로세스를 일괄 종료합니다. 진행 중 작업이 끊길 수 있습니다.',
        '<button class="u-btn u-btn--danger u-btn--sm" onclick="SettingsView._killZombies()">' +
          Utils.icon('trash', 13, 2) + '<span style="margin-left:4px">종료</span>' +
        '</button>'
      );
    const archiveBody =
      this._field('완료 팀 일괄 아카이브',
        '모든 티켓이 Done 인 팀을 아카이브로 이동합니다.',
        '<button class="u-btn u-btn--danger u-btn--ghost u-btn--sm" onclick="SettingsView._bulkArchive()">' +
          Utils.icon('archives', 13, 2) + '<span style="margin-left:4px">아카이브</span>' +
        '</button>'
      );
    const backupBody =
      this._field('DB 백업 다운로드',
        'SQLite 데이터베이스 스냅샷을 다운로드합니다.',
        '<a class="u-btn u-btn--sm" href="/api/system/backup" download>' +
          Utils.icon('download', 13, 2) + '<span style="margin-left:4px">다운로드</span>' +
        '</a>'
      );

    el.innerHTML = this._pageShell(
      '위험 작업',
      '아래 작업은 되돌릴 수 없거나 실행 중인 에이전트에 영향을 줄 수 있습니다.',
      '',
      this._section('프로세스 정리', '서버 성능이 저하되면 오래된 MCP/Node 프로세스를 정리합니다.', 'alert', zombieBody, '', 'danger-zone') +
      this._section('팀 정리', '완료된 팀을 대시보드에서 정리합니다.', 'archives', archiveBody) +
      this._section('백업', '정기적으로 백업해두면 안전합니다.', 'shield', backupBody)
    );
  },

  async _killZombies() {
    if (!confirm('좀비 MCP/Node 프로세스를 모두 종료합니다. 계속할까요?')) return;
    try {
      const res = await (API.killZombieMcp ? API.killZombieMcp() : API.post('/api/system/kill-zombie-mcp', {}));
      const killed = res.killed || res.terminated || 0;
      alert('종료된 프로세스: ' + killed + '개');
    } catch(e) { alert('실패: ' + e.message); }
  },
  async _bulkArchive() {
    if (!confirm('모든 Done 팀을 아카이브로 이동합니다. 계속할까요?')) return;
    try {
      const res = await API.post('/api/teams/archive-all-done', {});
      alert('아카이브됨: ' + (res.archived || 0) + '개');
    } catch(e) { alert('실패: ' + e.message); }
  }
};

if (typeof App !== 'undefined') App.registerView('settings', SettingsView);
