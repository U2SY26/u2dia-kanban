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
    { key: 'sprints',      icon: 'zap',          label: '\uc2a4\ud504\ub9b0\ud2b8', route: '#/sprints' },
    { key: 'archives',     icon: 'archives',     label: '\uc544\uce74\uc774\ube0c', route: '#/archives' },
    { key: 'history',      icon: 'history',      label: '\ud788\uc2a4\ud1a0\ub9ac', route: '#/history' },
    { key: 'competitions', icon: 'competitions', label: '\uacbd\uc7c1',         route: '#/competitions' },
    { key: 'cli',          icon: 'history',      label: 'CLI',                  route: '#/cli' },
    { key: 'settings',     icon: 'settings',     label: '\uc124\uc815',         route: '#/settings' }
  ],

  init() {
    this._rail = document.getElementById('shellRail');
    this._list = document.getElementById('shellList');
    if (!this._rail || !this._list) return;
    this._renderRail();
  },

  setActive(section, item) {
    this._activeSection = section;
    this._activeItem = item;
    this._renderRail();
    this._renderList();
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
    this._rail.innerHTML = html;
  },

  clickRail(key) {
    const item = this.RAIL_ITEMS.find(x => x.key === key);
    if (!item || !item.route) return;
    Router.navigate(item.route);
  },

  async _renderList() {
    if (!this._list) return;
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
