/* U2DIA Remote CLI Mirror — /cli 라우트 뷰
 * native(xterm.js + 직접 WS) default. iframe 모드는 폴백.
 * 모바일 친화 단축키 패널 — Esc/Tab/Ctrl/화살표/0-9/Prev/Next/Reset/Exit/Detach/Clear */
const CliView = {
  _writable: true,
  _iframe: null,
  _native: true,
  _term: null,
  _ws: null,
  _xtermLoaded: false,
  _ctrlSticky: false,

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
    if (url.hash.indexOf('native=0') >= 0 || url.hash.indexOf('iframe=1') >= 0) this._native = false;
    if (url.hash.indexOf('native=1') >= 0) this._native = true;
    const numKeys = ['0','1','2','3','4','5','6','7','8','9'].map(n =>
      `<button class="cli-key cli-key--num" data-keyseq="\\x02${n}" type="button">${n}</button>`
    ).join('');
    main.innerHTML = `
      <section class="cli-mirror">
        <header class="cli-mirror__bar">
          <span class="cli-mirror__title">Remote CLI Mirror — tmux "claude" ${this._native ? '· native' : '· iframe'}</span>
          <span class="cli-mirror__sep"></span>
          <button class="cli-mirror__btn" id="cliReload" type="button">재연결</button>
          <button class="cli-mirror__btn" id="cliToggleNative" type="button">${this._native ? 'iframe 모드' : 'native 모드'}</button>
          <button class="cli-mirror__btn" id="cliToggleWritable" type="button">${this._writable ? '읽기전용 전환' : '쓰기 전환'}</button>
          <button class="cli-mirror__btn" id="cliFullscreen" type="button">전체화면</button>
          <button class="cli-mirror__btn cli-mirror__btn--danger" id="cliResetTmux" type="button" title="tmux 세션 강제 종료 + 새 세션">TMUX 리셋</button>
        </header>
        <div class="cli-keypad" id="cliKeypad" role="toolbar" aria-label="단축키 패널">
          <div class="cli-keypad__row">
            <button class="cli-key" data-keyseq="\\x1b" type="button" title="Escape">Esc</button>
            <button class="cli-key" data-keyseq="\\t" type="button" title="Tab">Tab</button>
            <button class="cli-key cli-key--toggle" id="cliKeyCtrl" type="button" title="Ctrl 한정자 (sticky)" aria-pressed="false">Ctrl</button>
            <span class="cli-keypad__sep"></span>
            <button class="cli-key" data-keyseq="\\x1b[A" type="button" title="↑">↑</button>
            <button class="cli-key" data-keyseq="\\x1b[B" type="button" title="↓">↓</button>
            <button class="cli-key" data-keyseq="\\x1b[D" type="button" title="←">←</button>
            <button class="cli-key" data-keyseq="\\x1b[C" type="button" title="→">→</button>
          </div>
          <div class="cli-keypad__row">
            <button class="cli-key cli-key--prev" data-keyseq="\\x02p" type="button" title="이전 윈도우 (C-b p)">◀ Prev</button>
            ${numKeys}
            <button class="cli-key cli-key--next" data-keyseq="\\x02n" type="button" title="다음 윈도우 (C-b n)">Next ▶</button>
            <span class="cli-keypad__sep"></span>
            <button class="cli-key cli-key--add" data-keyseq="\\x02c" type="button" title="새 윈도우 (C-b c)">+ New</button>
            <button class="cli-key" data-keyseq="\\x02," type="button" title="이름 변경 (C-b ,)">✎ Rename</button>
            <button class="cli-key cli-key--danger" id="cliKeyKillWin" type="button" title="현재 윈도우 닫기 (C-b &amp;)">✕ Kill</button>
          </div>
          <div class="cli-keypad__row">
            <button class="cli-key cli-key--danger" data-keyseq="\\x03" type="button" title="Reset · Ctrl-c">Reset</button>
            <button class="cli-key cli-key--danger" data-keyseq="\\x04" type="button" title="Exit · Ctrl-d">Exit</button>
            <button class="cli-key" data-keyseq="\\x02d" type="button" title="Detach · C-b d">Detach</button>
            <button class="cli-key" data-keyseq="\\x0c" type="button" title="화면 지우기 · Ctrl-l">Clear</button>
            <button class="cli-key" data-keyseq="\\r" type="button" title="Enter">Enter</button>
            <button class="cli-key" data-keyseq=" " type="button" title="Space">Space</button>
            <button class="cli-key" data-keyseq="\\x7f" type="button" title="Backspace">⌫</button>
          </div>
        </div>
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
    document.getElementById('cliResetTmux').onclick = async () => {
      if (!confirm('tmux "claude" 세션을 강제 종료하고 새 세션을 생성합니다.\n진행 중인 작업은 모두 사라집니다. 계속할까요?')) return;
      const btn = document.getElementById('cliResetTmux');
      btn.disabled = true; btn.textContent = '리셋 중...';
      try {
        const res = await fetch('/api/cli/mirror/reset', {
          method: 'POST', headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({})
        }).then(r => r.json());
        if (res.ok) {
          this._teardownNative();
          if (this._iframe) this._iframe.src = this._iframe.src;
          else this.render(main);
          btn.textContent = 'TMUX 리셋'; btn.disabled = false;
        } else {
          alert('리셋 실패: ' + (res.message || res.error || '알 수 없는 오류'));
          btn.textContent = 'TMUX 리셋'; btn.disabled = false;
        }
      } catch (e) {
        alert('요청 실패: ' + (e.message || e));
        btn.textContent = 'TMUX 리셋'; btn.disabled = false;
      }
    };
    const ctrlBtn = document.getElementById('cliKeyCtrl');
    ctrlBtn.onclick = () => {
      this._ctrlSticky = !this._ctrlSticky;
      ctrlBtn.classList.toggle('cli-key--active', this._ctrlSticky);
      ctrlBtn.setAttribute('aria-pressed', this._ctrlSticky ? 'true' : 'false');
    };
    const killBtn = document.getElementById('cliKeyKillWin');
    if (killBtn) {
      killBtn.addEventListener('click', () => {
        if (!confirm('현재 tmux 윈도우를 닫습니다. 진행 중인 작업은 잃을 수 있어요. 계속할까요?')) return;
        this._sendKey('\x02&y');
      });
    }
    document.querySelectorAll('#cliKeypad .cli-key[data-keyseq]').forEach(btn => {
      btn.addEventListener('click', () => {
        let seq = this._unescape(btn.dataset.keyseq);
        if (this._ctrlSticky && seq.length === 1) {
          const c = seq.charCodeAt(0);
          if (c >= 0x40 && c <= 0x7e) seq = String.fromCharCode(c & 0x1f);
          this._ctrlSticky = false;
          ctrlBtn.classList.remove('cli-key--active');
          ctrlBtn.setAttribute('aria-pressed', 'false');
        }
        this._sendKey(seq);
      });
    });
    if (this._native) this._setupNative();
    else this._iframe = document.getElementById('cliFrame');
  },

  _unescape(s) {
    return (s || '').replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
                    .replace(/\\t/g, '\t').replace(/\\r/g, '\r').replace(/\\n/g, '\n');
  },

  _sendKey(seq) {
    if (!seq) return;
    if (this._native && this._ws && this._ws.readyState === 1) {
      const enc = new TextEncoder();
      const buf = enc.encode(seq);
      const out = new Uint8Array(buf.length + 1);
      out[0] = 0x30;
      out.set(buf, 1);
      this._ws.send(out);
      try { this._term && this._term.focus(); } catch(e){}
      return;
    }
    if (this._iframe && this._iframe.contentWindow) {
      try {
        this._iframe.contentWindow.postMessage({ type: 'cli-key', seq: seq }, '*');
      } catch(e){}
      const hint = document.createElement('div');
      hint.className = 'cli-keypad__hint';
      hint.textContent = 'iframe 모드 — 단축키는 native 모드에서만 안정 작동';
      document.getElementById('cliKeypad')?.appendChild(hint);
      setTimeout(() => hint.remove(), 2200);
    }
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
      ws.send(JSON.stringify({AuthToken: ''}));
      const dims = { columns: term.cols, rows: term.rows };
      ws.send('1' + JSON.stringify(dims));
    };
    ws.onmessage = (ev) => {
      const data = ev.data instanceof ArrayBuffer ? new Uint8Array(ev.data) : ev.data;
      if (typeof data === 'string') return;
      const cmd = data[0];
      if (cmd === 0x30) term.write(dec.decode(data.subarray(1)));
    };
    ws.onclose = () => term.write('\r\n[연결 종료]');
    ws.onerror = () => term.write('\r\n[연결 오류 — /cli/ws]');
    if (this._writable) {
      term.onData((d) => {
        if (ws.readyState === 1) {
          const buf = enc.encode(d);
          const out = new Uint8Array(buf.length + 1);
          out[0] = 0x30; out.set(buf, 1);
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
