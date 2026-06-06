/* U2DIA 재설계 — Sidebar (섹션 레일 + 섹션 목록) v2.1 (2026-04-18) */
const Sidebar = {
  _rail: null,
  _list: null,
  _activeSection: null,
  _activeItem: null,
  _renderToken: 0,

  RAIL_ITEMS: [
    { key: 'home',         icon: 'home',         label: '\ud648',         route: '#/' },
    { key: 'teams',        icon: 'kanban',       label: '\ud300',         route: '#/teams' },
    { key: 'history',      icon: 'history',      label: '\uc6b4\uc601\uae30\ub85d', route: '#/history' },
    { key: 'competitions', icon: 'competitions', label: '\ub300\ud68c',         route: '#/competitions' },
    { key: 'billing',      icon: 'billing',      label: '\uacb0\uc81c\u00b7\uc0ac\uc6a9\ub7c9',  route: '#/billing' },
    { key: 'cli',          icon: 'history',      label: 'CLI',                  route: '#/cli' },
    { key: 'settings',     icon: 'settings',     label: '\uc124\uc815',         route: '#/settings' }
  ],

  init() {
    this._rail = document.getElementById('shellRail');
    this._list = document.getElementById('shellList');
    if (!this._rail || !this._list) return;
    this._restoreLayout();
    this._installResizer();
    this._renderRail();
    // 모바일: 팀/항목(leaf) 선택 시 좌측 목록 자동 닫기 (그룹 헤더 토글은 제외)
    document.addEventListener('click', (e) => {
      if (!this._isMobile()) return;
      if (e.target.closest('.shell-team, .shell-list .u-list-item')) {
        setTimeout(() => Sidebar.closeMobileList(), 60);
      }
    });
  },

  _railPx() {
    return parseInt(getComputedStyle(document.documentElement).getPropertyValue('--shell-rail-w')) || 56;
  },
  _listPx() {
    const shell = document.getElementById('shell');
    return parseInt(getComputedStyle(shell || document.documentElement).getPropertyValue('--shell-list-w')) || 240;
  },
  _syncResizer() {
    const handle = document.getElementById('shellListResizer');
    const shell = document.getElementById('shell');
    if (!handle || !shell) return;
    if (shell.classList.contains('shell--list-collapsed')) {
      handle.style.display = 'none';
      return;
    }
    handle.style.display = '';
    handle.style.left = (this._railPx() + this._listPx()) + 'px';
  },

  _restoreLayout() {
    const shell = document.getElementById('shell');
    if (!shell) return;
    if (localStorage.getItem('u2dia.sidebarCollapsed') === '1') {
      shell.classList.add('shell--list-collapsed');
    }
    const w = parseInt(localStorage.getItem('u2dia.sidebarWidth') || '0', 10);
    if (w >= 180 && w <= 600) {
      shell.style.setProperty('--shell-list-w', w + 'px');
    }
    setTimeout(() => this._syncResizer(), 0);
    window.addEventListener('resize', () => this._syncResizer());
  },

  toggleCollapse() {
    const shell = document.getElementById('shell');
    if (!shell) return;
    const next = !shell.classList.contains('shell--list-collapsed');
    shell.classList.toggle('shell--list-collapsed', next);
    localStorage.setItem('u2dia.sidebarCollapsed', next ? '1' : '0');
    this._syncResizer();
  },

  _installResizer() {
    const shell = document.getElementById('shell');
    if (!shell) return;
    if (document.getElementById('shellListResizer')) return;
    const handle = document.createElement('div');
    handle.id = 'shellListResizer';
    handle.className = 'shell-list-resizer';
    handle.setAttribute('role', 'separator');
    handle.setAttribute('aria-label', '사이드 너비 조절');
    handle.setAttribute('aria-orientation', 'vertical');
    handle.tabIndex = 0;
    document.body.appendChild(handle);
    let dragging = false;
    let startX = 0, startW = 240;
    const railPx = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--shell-rail-w')) || 56;
    const min = 180, max = 600;
    const onMove = (e) => {
      if (!dragging) return;
      const x = (e.touches ? e.touches[0].clientX : e.clientX) || 0;
      const target = Math.max(min, Math.min(max, startW + (x - startX)));
      shell.style.setProperty('--shell-list-w', target + 'px');
      handle.style.left = (railPx + target) + 'px';
    };
    const stop = () => {
      if (!dragging) return;
      dragging = false;
      handle.classList.remove('shell-list-resizer--dragging');
      document.body.style.cursor = '';
      const w = parseInt(getComputedStyle(shell).getPropertyValue('--shell-list-w')) || 240;
      localStorage.setItem('u2dia.sidebarWidth', String(w));
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', stop);
      window.removeEventListener('touchmove', onMove);
      window.removeEventListener('touchend', stop);
    };
    const start = (e) => {
      if (shell.classList.contains('shell--list-collapsed')) return;
      dragging = true;
      startX = (e.touches ? e.touches[0].clientX : e.clientX) || 0;
      startW = parseInt(getComputedStyle(shell).getPropertyValue('--shell-list-w')) || 240;
      handle.classList.add('shell-list-resizer--dragging');
      document.body.style.cursor = 'ew-resize';
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', stop);
      window.addEventListener('touchmove', onMove, { passive: true });
      window.addEventListener('touchend', stop);
      e.preventDefault();
    };
    handle.addEventListener('mousedown', start);
    handle.addEventListener('touchstart', start, { passive: true });
    handle.addEventListener('keydown', (e) => {
      if (shell.classList.contains('shell--list-collapsed')) return;
      const cur = parseInt(getComputedStyle(shell).getPropertyValue('--shell-list-w')) || 240;
      let next = cur;
      if (e.key === 'ArrowLeft') next = Math.max(min, cur - 16);
      else if (e.key === 'ArrowRight') next = Math.min(max, cur + 16);
      else return;
      shell.style.setProperty('--shell-list-w', next + 'px');
      localStorage.setItem('u2dia.sidebarWidth', String(next));
      e.preventDefault();
    });
    handle.addEventListener('dblclick', () => {
      shell.style.setProperty('--shell-list-w', '240px');
      localStorage.setItem('u2dia.sidebarWidth', '240');
    });
  },

  // 좌측 목록이 필요 없는 뷰 — 목록 영역을 완전히 숨기고 메인이 전체폭 사용
  NO_LIST: ['home', 'billing', 'cli', 'competitions'],

  setActive(section, item) {
    this._activeSection = section;
    this._activeItem = item;
    this._applyListVisibility(section);
    this._renderRail();
    this._renderList();
  },

  _applyListVisibility(section) {
    const shell = document.getElementById('shell');
    if (!shell) return;
    shell.classList.toggle('shell--list-hidden', this.NO_LIST.indexOf(section) !== -1);
  },

  _renderRail() {
    if (!this._rail) return;
    const html = this.RAIL_ITEMS.map(it => {
      const isActive = it.key === this._activeSection;
      return '<button class="shell-rail__btn' + (isActive ? ' shell-rail__btn--active' : '') +
        '" data-tooltip="' + Utils.esc(it.label) + '"' +
        ' aria-label="' + Utils.esc(it.label) + '"' +
        ' aria-current="' + (isActive ? 'page' : 'false') + '"' +
        ' onclick="Sidebar.clickRail(\'' + it.key + '\')">' +
        Utils.icon(it.icon, 20) + '</button>';
    }).join('');
    const collapseBtn =
      '<button class="shell-rail__btn shell-rail__btn--collapse" data-tooltip="사이드 접기/펼치기"' +
      ' aria-label="사이드 접기/펼치기" onclick="Sidebar.toggleCollapse()">' +
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M9 18l-6-6 6-6M21 18l-6-6 6-6"/></svg></button>';
    this._rail.innerHTML = html + '<div class="shell-rail__spacer"></div>' + collapseBtn;
  },

  clickRail(key) {
    const item = this.RAIL_ITEMS.find(x => x.key === key);
    if (!item || !item.route) return;
    Router.navigate(item.route);
    // 모바일: 목록 있는 섹션이면 좌측 리스트(팀 메뉴 등)를 자동으로 슬라이드 인
    if (this._isMobile()) {
      if (this.NO_LIST.indexOf(key) === -1) this.openMobileList();
      else this.closeMobileList();
    }
  },

  _isMobile() { return window.innerWidth <= 900; },

  openMobileList() {
    const shell = document.getElementById('shell');
    if (!shell) return;
    shell.classList.add('shell--list-open');
    this._ensureBackdrop();
  },

  closeMobileList() {
    const shell = document.getElementById('shell');
    if (shell) shell.classList.remove('shell--list-open');
  },

  _ensureBackdrop() {
    if (document.getElementById('shellListBackdrop')) return;
    const shell = document.getElementById('shell');
    if (!shell) return;
    const bd = document.createElement('div');
    bd.id = 'shellListBackdrop';
    bd.className = 'shell-list__backdrop';
    bd.addEventListener('click', () => Sidebar.closeMobileList());
    shell.appendChild(bd);
  },

  async _renderList() {
    if (!this._list) return;
    // 목록 불필요 뷰는 렌더 자체를 생략 (영역은 _applyListVisibility 가 숨김)
    if (this.NO_LIST.indexOf(this._activeSection) !== -1) { this._list.innerHTML = ''; return; }
    const token = ++this._renderToken;
    const sectionAtStart = this._activeSection;
    const itemAtStart = this._activeItem;
    const view = App._views[sectionAtStart];
    /* 즉시 스켈레톤 세팅으로 잔상 제거 */
    this._list.innerHTML =
      '<div class="shell-list__header"><span class="shell-list__title">' + Utils.esc(this._sectionLabel(sectionAtStart)) + '</span></div>' +
      '<div class="shell-list__body"><div class="u-skeleton u-skeleton--block"></div></div>';
    if (view && typeof view.renderList === 'function') {
      /* 격리된 버퍼에 렌더 후, 최신 토큰일 때만 커밋 (race 방지) */
      const buffer = document.createElement('div');
      try {
        await view.renderList(buffer, itemAtStart);
        if (token === this._renderToken && sectionAtStart === this._activeSection) {
          this._list.innerHTML = buffer.innerHTML;
        }
      } catch (e) {
        if (token === this._renderToken) {
          this._list.innerHTML = '<div class="shell-list__header"><span class="shell-list__title">' + Utils.esc(this._sectionLabel(sectionAtStart)) + '</span></div><div class="shell-list__body"><div class="u-empty"><div class="u-empty__desc">\ubaa9\ub85d \ub85c\ub529 \uc2e4\ud328</div></div></div>';
        }
      }
    } else {
      this._list.innerHTML =
        '<div class="shell-list__header"><span class="shell-list__title">' + Utils.esc(this._sectionLabel(sectionAtStart)) + '</span></div>' +
        '<div class="shell-list__body"><div class="u-empty"><div class="u-empty__title">\ubaa9\ub85d \uc5c6\uc74c</div></div></div>';
    }
  },

  _sectionLabel(key) {
    const it = this.RAIL_ITEMS.find(x => x.key === key);
    return it ? it.label : (key || '');
  },

  refreshList() { this._renderList(); }
};
