/* U2DIA 재설계 — App 부트스트랩 & 라우팅 (2026-04-17) */
const App = {
  _currentSection: null,
  _currentItem: null,
  _views: {},

  registerView(name, module) { this._views[name] = module; },

  init() {
    Router.on('/',              () => this.goto('home'));
    Router.on('/teams',         () => this.goto('teams'));
    Router.on('/board/:teamId', (p) => this.goto('teams', p.teamId));
    Router.on('/history',       () => this.goto('history'));
    Router.on('/history/:teamId', (p) => this.goto('history', p.teamId));
    Router.on('/competitions',  () => this.goto('competitions'));
    Router.on('/competitions/:name', (p) => this.goto('competitions', decodeURIComponent(p.name)));
    Router.on('/cli',           () => this.goto('cli'));
    Router.on('/billing',       () => this.goto('billing'));
    Router.on('/usage',         () => Router.navigate('#/billing'));  // 사용량은 결제로 병합
    Router.on('/settings',      () => this.goto('settings'));
    Router.on('/settings/:tab', (p) => this.goto('settings', p.tab));

    Router.beforeChange(() => { if (typeof SSE !== 'undefined' && SSE.disconnectAll) SSE.disconnectAll(); });

    /* 공통 컴포넌트 초기화 — Router.start() 이전에 반드시 (Sidebar._list 등 null race 방지) */
    if (typeof Header  !== 'undefined') Header.init();
    if (typeof Sidebar !== 'undefined') Sidebar.init();
    if (typeof CliPanel !== 'undefined') CliPanel.init();

    Router.start();
  },

  goto(section, item) {
    this._currentSection = section;
    this._currentItem = item || null;
    if (typeof Sidebar !== 'undefined' && Sidebar.setActive) {
      Sidebar.setActive(section, item);
    }
    if (typeof Header !== 'undefined' && Header.setBreadcrumb) {
      Header.setBreadcrumb(section, item);
    }
    this._renderMain();
  },

  _renderMain() {
    const main = document.getElementById('shellMain');
    if (!main) return;
    const view = this._views[this._currentSection];
    if (!view || typeof view.render !== 'function') {
      main.innerHTML = '<div class="u-empty"><div class="u-empty__icon">\u25c7</div><div class="u-empty__title">\ubdf0\ub97c \ucc3e\uc744 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4</div><div class="u-empty__desc">section: ' + (this._currentSection || '-') + '</div></div>';
      return;
    }
    try { view.render(main, this._currentItem); }
    catch (e) {
      main.innerHTML = '<div class="u-empty"><div class="u-empty__title">\ub80c\ub354 \uc624\ub958</div><div class="u-empty__desc">' + (typeof Utils !== 'undefined' ? Utils.esc(e.message || String(e)) : (e.message || String(e))) + '</div></div>';
    }
  },

  refresh() {
    const view = this._views[this._currentSection];
    if (view && typeof view.refresh === 'function') view.refresh();
  }
};
