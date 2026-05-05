/* U2DIA Remote CLI Mirror — /cli 라우트 뷰 (2026-04-26, NATIVE-1 vendoring)
 * 기본: iframe (ttyd HTML). ?native=1 또는 토글 시: 자체 xterm.js + WS 핸드코드. */
const CliView = {
  _writable: true,
  _iframe: null,
  _native: false,
  _term: null,
  _ws: null,
  _xtermLoaded: false,

  _loadXterm() {
    if (this._xtermLoaded) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const css = document.createElement('link');
      css.rel = 'stylesheet';
      css.href = '/vendor/xterm/xterm.css';
      document.head.appendChild(css);
      const load = (src) => new Promise((res, rej) => {
        const s = document.createElement('script');
        s.src = src; s.onload = res; s.onerror = rej;
        document.head.appendChild(s);
      });
      load('/vendor/xterm/xterm.js')
        .then(() => Promise.all([
          load('/vendor/xterm/xterm-addon-fit.js'),
          load('/vendor/xterm/xterm-addon-web-links.js')
        ]))
        .then(() => { this._xtermLoaded = true; resolve(); })
        .catch(reject);
    });
  },

  render(main, _item) {
    const url = new URL(window.location.href);
    if (url.hash.indexOf('native=1') >= 0) this._native = true;
    main.innerHTML = `
      <section class="cli-mirror">
        <header class="cli-mirror__bar">
          <span class="cli-mirror__title">Remote CLI Mirror — tmux "claude" ${this._native ? '· native' : '· iframe'}</span>
          <span class="cli-mirror__sep"></span>
          <button class="cli-mirror__btn" id="cliReload" type="button">재연결</button>
          <button class="cli-mirror__btn" id="cliToggleNative" type="button">${this._native ? 'iframe 모드' : 'native 모드'}</button>
          <button class="cli-mirror__btn" id="cliToggleWritable" type="button">${this._writable ? '읽기전용 전환' : '쓰기 전환'}</button>
          <button class="cli-mirror__btn" id="cliFullscreen" type="button">전체화면</button>
        </header>
        <div class="cli-mirror__frame-wrap">
          ${this._native
            ? '<div id="cliNativeTerm" class="cli-mirror__native"></div>'
            : `<iframe id="cliFrame" class="cli-mirror__frame" src="/cli/?writable=${this._writable?1:0}" allow="clipboard-read; clipboard-write"></iframe>`
          }
        </div>
      </section>
    `;
    document.getElementById('cliReload').onclick = () => {
      if (this._native) { this._teardownNative(); this._setupNative(); }
      else if (this._iframe) this._iframe.src = this._iframe.src;
    };
    document.getElementById('cliToggleNative').onclick = () => {
      this._native = !this._native; this._teardownNative(); this.render(main);
    };
    document.getElementById('cliToggleWritable').onclick = () => {
      this._writable = !this._writable; this.render(main);
    };
    document.getElementById('cliFullscreen').onclick = () => {
      const wrap = document.querySelector('.cli-mirror');
      if (!document.fullscreenElement) wrap.requestFullscreen?.();
      else document.exitFullscreen?.();
    };
    if (this._native) this._setupNative();
    else this._iframe = document.getElementById('cliFrame');
  },

  _teardownNative() {
    try { this._ws && this._ws.close(); } catch(e){}
    try { this._term && this._term.dispose(); } catch(e){}
    this._ws = null; this._term = null;
  },

  async _setupNative() {
    await this._loadXterm();
    const host = document.getElementById('cliNativeTerm');
    if (!host) return;
    const term = new window.Terminal({
      fontSize: 14, theme: { background: '#000000' }, cursorBlink: true,
      convertEol: true,
    });
    const fit = new window.FitAddon.FitAddon();
    term.loadAddon(fit);
    term.loadAddon(new window.WebLinksAddon.WebLinksAddon());
    term.open(host);
    fit.fit();
    window.addEventListener('resize', () => { try { fit.fit(); } catch(e){} });
    this._term = term;

    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(`${proto}//${location.host}/cli/ws`, ['tty']);
    ws.binaryType = 'arraybuffer';
    this._ws = ws;
    const enc = new TextEncoder(), dec = new TextDecoder();

    ws.onopen = () => {
      // ttyd 핸드쉐이크: AuthToken JSON 문자열
      ws.send(JSON.stringify({AuthToken: ''}));
      // 리사이즈 통보
      const dims = { columns: term.cols, rows: term.rows };
      ws.send('1' + JSON.stringify(dims));
    };
    ws.onmessage = (ev) => {
      const data = ev.data instanceof ArrayBuffer ? new Uint8Array(ev.data) : ev.data;
      if (typeof data === 'string') return;
      const cmd = data[0];
      if (cmd === 0x30) term.write(dec.decode(data.subarray(1)));   // '0' OUTPUT
    };
    ws.onclose = () => term.write('\r\n[연결 종료]');
    ws.onerror = () => term.write('\r\n[연결 오류 — /cli/ws]');
    if (this._writable) {
      term.onData((d) => {
        if (ws.readyState === 1) {
          const buf = enc.encode(d);
          const out = new Uint8Array(buf.length + 1);
          out[0] = 0x30; out.set(buf, 1);  // '0' INPUT
          ws.send(out);
        }
      });
      term.onResize(({cols, rows}) => {
        if (ws.readyState === 1) ws.send('1' + JSON.stringify({columns: cols, rows: rows}));
      });
    }
  }
};
if (typeof App !== 'undefined') App.registerView('cli', CliView);
