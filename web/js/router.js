/* U2DIA AI SERVER AGENT — Hash Router */
const Router = {
  _routes: {},
  _current: null,
  _beforeChange: null,

  /** 라우트 등록 */
  on(pattern, handler) {
    this._routes[pattern] = handler;
  },

  /** 라우트 변경 전 콜백 */
  beforeChange(fn) {
    this._beforeChange = fn;
  },

  /** 해시 기반 네비게이션 */
  navigate(hash) {
    location.hash = hash;
  },

  /** 현재 라우트 정보 */
  current() {
    return this._current;
  },

  /** 라우터 초기화 및 시작 */
  start() {
    window.addEventListener('hashchange', () => this._resolve());
    this._resolve();
  },

  _resolve() {
    const hash = location.hash.slice(1) || '/';
    if (this._beforeChange) this._beforeChange(hash);

    for (const [pattern, handler] of Object.entries(this._routes)) {
      const params = this._match(pattern, hash);
      if (params !== null) {
        this._current = { pattern, hash, params };
        handler(params);
        return;
      }
    }
    // 매치 없음 → 대시보드로 리다이렉트
    if (this._routes['/']) {
      this._current = { pattern: '/', hash: '/', params: {} };
      this._routes['/']({});
    }
  },

  _match(pattern, hash) {
    // /board/:teamId → regex
    const paramNames = [];
    const re = pattern.replace(/:([^/]+)/g, (_, name) => {
      paramNames.push(name);
      return '([^/]+)';
    });
    const m = hash.match(new RegExp('^' + re + '$'));
    if (!m) return null;
    const params = {};
    paramNames.forEach((name, i) => { params[name] = m[i + 1]; });
    return params;
  }
};
