/* U2DIA 재설계 — Header (2026-04-17) */
const Header = {
  _breadcrumbEl: null,
  _sseDotEl: null,
  _searchOverlay: null,
  _dropdown: null,
  _closeDropdownHandler: null,

  init() {
    this._breadcrumbEl = document.getElementById('shellBreadcrumb');
    this._sseDotEl = document.getElementById('shellSseDot');
    this._bindShortcuts();
  },

  setBreadcrumb(section, item) {
    if (!this._breadcrumbEl) return;
    const labels = {
      home: '\ud648', teams: '\ud300', sprints: '\uc2a4\ud504\ub9b0\ud2b8',
      archives: '\uc544\uce74\uc774\ube0c', history: '\ud788\uc2a4\ud1a0\ub9ac',
      competitions: '\uacbd\uc7c1', settings: '\uc124\uc815'
    };
    const secLabel = labels[section] || section;
    let html = '<span class="shell-header__breadcrumb-sep">\u203a</span> ' + Utils.esc(secLabel);
    if (item) html += ' <span class="shell-header__breadcrumb-sep">\u203a</span> <span style="color:var(--text-primary)">' + Utils.esc(item) + '</span>';
    this._breadcrumbEl.innerHTML = html;
  },

  setSseStatus(ok) {
    if (!this._sseDotEl) return;
    this._sseDotEl.style.background = ok ? 'var(--success-fg)' : 'var(--danger-fg)';
    this._sseDotEl.title = ok ? 'SSE \uc5f0\uacb0\ub428' : 'SSE \ub04a\uae40';
  },

  _cmdSelectedIdx: 0,
  _cmdResults: [],

  openSearch() {
    if (this._searchOverlay) { this.closeSearch(); return; }
    const overlay = document.createElement('div');
    overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:2000;display:flex;align-items:flex-start;justify-content:center;padding-top:80px;backdrop-filter:blur(4px)';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', '\uba85\ub839 \ud314\ub808\ud2b8');
    overlay.onclick = (e) => { if (e.target === overlay) this.closeSearch(); };
    overlay.innerHTML = `
      <div style="width:560px;max-width:90vw;background:var(--surface-3);border:1px solid var(--line-light);border-radius:10px;box-shadow:var(--shadow-xl);overflow:hidden">
        <input class="u-input" id="cmdInput" placeholder="\ud300/\ud2f0\ucf13 \uac80\uc0c9, \uba85\ub839 \uc785\ub825..." style="border:none;border-radius:0;padding:var(--space-4);font-size:var(--text-lg)" aria-label="\uac80\uc0c9">
        <div id="cmdResults" role="listbox" style="max-height:360px;overflow-y:auto;border-top:1px solid var(--line)"></div>
        <div style="padding:8px 12px;font-size:11px;color:var(--text-muted-new);border-top:1px solid var(--line);display:flex;justify-content:space-between;font-family:var(--mono)">
          <span>\u2191\u2193 \uc774\ub3d9 \u00b7 Enter \uc120\ud0dd \u00b7 Esc \ub2eb\uae30</span>
          <span>U2DIA Command Palette</span>
        </div>
      </div>`;
    document.body.appendChild(overlay);
    this._searchOverlay = overlay;
    this._cmdSelectedIdx = 0;
    const input = document.getElementById('cmdInput');
    setTimeout(() => input && input.focus(), 0);
    input.addEventListener('input', (e) => { this._cmdSelectedIdx = 0; this._runSearch(e.target.value); });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') this.closeSearch();
      else if (e.key === 'ArrowDown') { e.preventDefault(); this._cmdSelectedIdx = Math.min(this._cmdResults.length - 1, this._cmdSelectedIdx + 1); this._highlightCmd(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); this._cmdSelectedIdx = Math.max(0, this._cmdSelectedIdx - 1); this._highlightCmd(); }
      else if (e.key === 'Enter') { e.preventDefault(); this._activateCmd(); }
    });
    this._runSearch('');
  },

  _highlightCmd() {
    const results = document.getElementById('cmdResults');
    if (!results) return;
    Array.from(results.querySelectorAll('[data-cmd-idx]')).forEach((el, i) => {
      if (i === this._cmdSelectedIdx) {
        el.classList.add('u-list-item--active');
        el.scrollIntoView({ block: 'nearest' });
      } else {
        el.classList.remove('u-list-item--active');
      }
    });
  },

  _activateCmd() {
    const item = this._cmdResults[this._cmdSelectedIdx];
    if (!item) return;
    if (item.route) Router.navigate(item.route);
    this.closeSearch();
  },

  closeSearch() {
    if (this._searchOverlay) { this._searchOverlay.remove(); this._searchOverlay = null; }
  },

  async _runSearch(q) {
    const results = document.getElementById('cmdResults');
    if (!results) return;
    const commands = [
      { label: '\ud648\uc73c\ub85c', route: '#/' },
      { label: '\uacb0\uc81c\u00b7\uc0ac\uc6a9\ub7c9', route: '#/billing' },
      { label: '\ud788\uc2a4\ud1a0\ub9ac', route: '#/history' },
      { label: '\ub300\ud68c', route: '#/competitions' },
      { label: '\uc124\uc815', route: '#/settings' },
      { label: '\uc124\uc815 > \ud1a0\ud070', route: '#/settings/tokens' },
      { label: '\uc124\uc815 > \uc2dc\uc2a4\ud15c \uba54\ud2b8\ub9ad', route: '#/settings/metrics' },
      { label: '\uc124\uc815 > \uc704\ud5d8 \uc791\uc5c5 (Zombie \ud0ac)', route: '#/settings/danger' }
    ];
    const qLow = (q || '').toLowerCase();
    const cmdMatches = commands.filter(c => c.label.toLowerCase().includes(qLow));
    let teamMatches = [];
    if (q && q.length >= 2) {
      try {
        const ov = await API.overview();
        teamMatches = (ov.teams || []).filter(t => {
          const name = (t.team && t.team.name) || t.name || '';
          return name.toLowerCase().includes(qLow);
        }).slice(0, 5);
      } catch(e) {}
    }
    this._cmdResults = [];
    cmdMatches.forEach(c => this._cmdResults.push({ type: 'cmd', label: c.label, route: c.route }));
    teamMatches.forEach(t => {
      const team = t.team || t;
      this._cmdResults.push({ type: 'team', label: team.name || team.team_id, route: '#/board/' + team.team_id });
    });
    if (!this._cmdResults.length) {
      results.innerHTML = '<div class="u-empty" style="padding:40px 20px"><div class="u-empty__desc">\uacb0\uacfc \uc5c6\uc74c</div></div>';
      return;
    }
    results.innerHTML = this._cmdResults.map((r, i) => {
      const iconSvg = r.type === 'team' ? Utils.icon('kanban', 14, 2) : Utils.icon('chevronRight', 14, 2);
      const active = i === this._cmdSelectedIdx ? ' u-list-item--active' : '';
      return '<div class="u-list-item' + active + '" data-cmd-idx="' + i + '" onclick="Header._cmdSelectedIdx=' + i + ';Header._activateCmd()"><span style="color:var(--text-muted-new)">' + iconSvg + '</span>' + Utils.esc(r.label) + '</div>';
    }).join('');
  },

  openNotifications(anchorBtn) {
    this._closeDropdown();
    const items = (typeof HomeView !== 'undefined' && HomeView._feedItems) ? HomeView._feedItems.slice(0, 20) : [];
    const html = items.length
      ? items.map(it => {
          const t = new Date(it.at).toTimeString().slice(0,5);
          const title = it.payload.title || it.payload.name || it.type;
          return '<div class="u-list-item" style="font-size:var(--text-sm)"><span style="color:var(--text-muted-new);margin-right:var(--space-2);font-family:var(--mono)">' + t + '</span>' + Utils.esc(title) + '</div>';
        }).join('')
      : '<div class="u-empty"><div class="u-empty__desc">\uc54c\ub9bc \uc5c6\uc74c</div></div>';
    this._showDropdown(html, anchorBtn);
  },

  openSettingsMenu(anchorBtn) {
    this._closeDropdown();
    /* 중복 제거: "설정" 링크는 좌측 레일 ⚙ 아이콘으로 대체되므로 여기서는 빠른 액션만 */
    const html =
      '<div class="u-list-item" onclick="App.refresh();Header._closeDropdown()">' + Utils.icon('refresh', 14, 2) + '<span>\uc0c8\ub85c\uace0\uce68</span></div>' +
      '<div class="u-list-item" onclick="Header._toggleTheme();Header._closeDropdown()">' + Utils.icon('flame', 14, 2) + '<span>\ud14c\ub9c8 \uc804\ud658</span></div>' +
      '<div class="u-list-item" onclick="Router.navigate(\'#/settings/danger\');Header._closeDropdown()" style="color:var(--danger-fg)">' + Utils.icon('trash', 14, 2) + '<span>Zombie \ud504\ub85c\uc138\uc2a4 \uc885\ub8cc</span></div>' +
      '<div class="u-list-item" onclick="location.href=\'/login\'">' + Utils.icon('user', 14, 2) + '<span>\ub85c\uadf8\uc544\uc6c3</span></div>';
    this._showDropdown(html, anchorBtn);
  },

  _toggleTheme() {
    /* 현재 다크 고정. 향후 라이트 모드 추가 시 여기서 전환 */
    alert('\ud14c\ub9c8\ub294 \ud604\uc7ac \ub2e4\ud06c \uace0\uc815\uc785\ub2c8\ub2e4');
  },

  _showDropdown(innerHtml, anchor) {
    const rect = anchor ? anchor.getBoundingClientRect() : { right: window.innerWidth, bottom: 50 };
    const dd = document.createElement('div');
    dd.style.cssText = 'position:fixed;top:' + (rect.bottom + 4) + 'px;right:' + (window.innerWidth - rect.right) + 'px;width:260px;background:var(--surface-3);border:1px solid var(--line-light);border-radius:var(--radius-md);box-shadow:var(--shadow-lg);z-index:1500;padding:var(--space-2);max-height:400px;overflow-y:auto';
    dd.innerHTML = innerHtml;
    document.body.appendChild(dd);
    this._dropdown = dd;
    setTimeout(() => {
      this._closeDropdownHandler = (e) => { if (!dd.contains(e.target) && e.target !== anchor) this._closeDropdown(); };
      document.addEventListener('click', this._closeDropdownHandler);
    }, 0);
  },

  _closeDropdown() {
    if (this._dropdown) { this._dropdown.remove(); this._dropdown = null; }
    if (this._closeDropdownHandler) { document.removeEventListener('click', this._closeDropdownHandler); this._closeDropdownHandler = null; }
  },

  toggleYudi() {
    if (typeof Dashboard !== 'undefined' && Dashboard.toggleAgent) {
      Dashboard.toggleAgent();
    } else {
      alert('\uc720\ub514 \ud1a0\uae00 \u2014 \ucd94\ud6c4 \uad6c\ud604 \uc608\uc815');
    }
  },

  _bindShortcuts() {
    document.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        this.openSearch();
      }
    });
  }
};
