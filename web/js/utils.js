/* U2DIA AI SERVER AGENT — Utilities (Salesforce Lightning)
 * SECURITY: All user-facing HTML rendering uses Utils.esc() to sanitize
 * input before innerHTML assignment, preventing XSS attacks.
 * Utils.esc() uses textContent-based escaping (DOM-native safe method).
 */
const Utils = {
  /** Number format — 한국 단위 (만/억) */
  fmtNum(n) {
    n = n || 0;
    if (n >= 100000000) return (n / 100000000).toFixed(1) + '억';
    if (n >= 10000) return (n / 10000).toFixed(1) + '만';
    if (n >= 1000) return (n / 1000).toFixed(1) + '천';
    return n.toString();
  },

  /** USD → 원화 (환율 1380) */
  fmtKrw(usd) {
    var krw = (usd || 0) * 1380;
    if (krw >= 10000) return (krw / 10000).toFixed(1) + '만원';
    return Math.round(krw) + '원';
  },

  /** HTML escape — XSS-safe via textContent */
  esc(s) {
    const d = document.createElement('div');
    d.textContent = String(s || '');
    return d.innerHTML;
  },

  /** Time format (HH:MM) */
  timeFmt(t) {
    if (!t) return '-';
    const d = new Date(t.includes('Z') ? t : t + 'Z');
    return isNaN(d) ? t : d.toLocaleTimeString('ko', { hour: '2-digit', minute: '2-digit' });
  },

  /** Date format (MM.DD HH:MM) */
  dateFmt(t) {
    if (!t) return '-';
    const d = new Date(t.includes('Z') ? t : t + 'Z');
    if (isNaN(d)) return t;
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const hh = String(d.getHours()).padStart(2, '0');
    const mi = String(d.getMinutes()).padStart(2, '0');
    return `${mm}.${dd} ${hh}:${mi}`;
  },

  /** Relative time */
  relTime(t) {
    if (!t) return '-';
    const d = new Date(t.includes('Z') ? t : t + 'Z');
    const diff = (Date.now() - d.getTime()) / 1000;
    if (diff < 60) return '방금 전';
    if (diff < 3600) return Math.floor(diff / 60) + '분 전';
    if (diff < 86400) return Math.floor(diff / 3600) + '시간 전';
    return Math.floor(diff / 86400) + '일 전';
  },

  /** Alias for relTime */
  timeAgo(t) { return this.relTime(t); },

  /** Safe attribute escape — Utils.esc + quote */
  attr(s) {
    if (s === null || s === undefined) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  },

  /** Number format (1234 -> 1,234 / 1234567 -> 1.2M) */
  numFmt(n) {
    if (n === null || n === undefined) return '-';
    n = Number(n);
    if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
    if (n >= 1000) return (n / 1000).toFixed(1) + 'K';
    return n.toLocaleString();
  },

  /** Cost format */
  costFmt(n) {
    if (!n && n !== 0) return '-';
    return '$' + Number(n).toFixed(3);
  },

  /** Progress color */
  progressColor(pct) {
    if (pct >= 80) return 'var(--green-light)';
    if (pct >= 50) return 'var(--brand-light)';
    if (pct >= 20) return 'var(--yellow-light)';
    if (pct > 0) return 'var(--orange-light)';
    return 'var(--muted)';
  },

  /** Status color */
  statusColor(status) {
    const map = {
      Backlog: 'var(--col-backlog)', Todo: 'var(--col-todo)',
      InProgress: 'var(--col-inprogress)', Review: 'var(--col-review)',
      Done: 'var(--col-done)', Blocked: 'var(--col-blocked)'
    };
    return map[status] || 'var(--muted)';
  },

  /** Status label (abbreviated) */
  statusLabel(status) {
    const map = { Backlog:'BL', Todo:'TD', InProgress:'IP', Review:'RV', Done:'DN', Blocked:'BK' };
    return map[status] || status;
  },

  /** Element by ID */
  $(id) { return document.getElementById(id); },

  /** Create element — safe DOM builder */
  el(tag, attrs = {}, children = []) {
    const e = document.createElement(tag);
    Object.entries(attrs).forEach(([k, v]) => {
      if (k === 'class') e.className = v;
      /* innerHTML only used with pre-sanitized (Utils.esc'd) content */
      else if (k === 'html') e.innerHTML = v;
      else if (k === 'text') e.textContent = v;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, v);
    });
    children.forEach(c => {
      if (typeof c === 'string') e.appendChild(document.createTextNode(c));
      else if (c) e.appendChild(c);
    });
    return e;
  },

  /** Clear container */
  clear(el) {
    if (typeof el === 'string') el = document.getElementById(el);
    if (el) el.textContent = '';
    return el;
  },

  /** Kanban column order */
  COLUMNS: ['Backlog', 'Todo', 'InProgress', 'Review', 'Done', 'Blocked'],

  /** Column Korean name */
  colName(col) {
    const map = { Backlog:'백로그', Todo:'할일', InProgress:'진행중', Review:'리뷰', Done:'완료', Blocked:'차단됨' };
    return map[col] || col;
  },

  /** Agent avatar initials */
  agentInitial(name) {
    if (!name || name === '미배정') return '?';
    const parts = name.split(/[\s\-_]+/).filter(Boolean);
    return parts.length >= 2
      ? (parts[0][0] + parts[1][0]).toUpperCase()
      : name.substring(0, 2).toUpperCase();
  },

  /** Priority sort value */
  priorityOrder(pri) {
    return { Critical: 0, High: 1, Medium: 2, Low: 3 }[pri] ?? 2;
  },

  /** CSS variable to computed value (for Canvas) */
  cssVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }
};

/* ── roundRect polyfill (Safari < 16) ── */
if (!CanvasRenderingContext2D.prototype.roundRect) {
  CanvasRenderingContext2D.prototype.roundRect = function(x, y, w, h, radii) {
    const r = typeof radii === 'number' ? radii : (radii && radii[0]) || 0;
    this.moveTo(x + r, y);
    this.arcTo(x + w, y, x + w, y + h, r);
    this.arcTo(x + w, y + h, x, y + h, r);
    this.arcTo(x, y + h, x, y, r);
    this.arcTo(x, y, x + w, y, r);
    this.closePath();
  };
}

/* ═══════════════════════════════════════════════════════════
   Icon — Lucide-style 1.75px stroke SVG (2026-04-17 재설계)
   Utils.icon(name, size=18) → <svg ...>
   외부 라이브러리 없음. path 데이터는 Lucide(ISC) 기반 커스텀.
   ═══════════════════════════════════════════════════════════ */
const Icons = {
  /* 섹션 레일 */
  home:        'M3 10.5L12 3l9 7.5V21a1 1 0 0 1-1 1h-5v-7h-6v7H4a1 1 0 0 1-1-1V10.5z',
  teams:       'M12 2.5 2.5 7 12 11.5 21.5 7 12 2.5zM2.5 17 12 21.5 21.5 17M2.5 12 12 16.5 21.5 12',
  sprints:     'M13 3L4 14h7l-1 7 9-11h-7l1-7z',
  archives:    'M3 7h18v4H3zM5 11v9a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-9M10 15h4',
  history:     'M12 3a9 9 0 1 0 9 9M12 3V1M12 3a9 9 0 0 1 9 9M12 7v5l3 2',
  competitions:'M6 3h12v4a6 6 0 0 1-12 0V3zM5 7H2a3 3 0 0 0 3 3M19 7h3a3 3 0 0 1-3 3M10 18h4v3h-4zM8 21h8',
  settings:    'M12 8a4 4 0 1 1 0 8 4 4 0 0 1 0-8zM19.4 15a7.96 7.96 0 0 0 0-6l2-1.5-2-3.5-2.4 1a8 8 0 0 0-5-3L11.5 0h-4L7 2a8 8 0 0 0-5 3L-0.4 4l-2 3.5 2 1.5a7.96 7.96 0 0 0 0 6l-2 1.5 2 3.5 2.4-1a8 8 0 0 0 5 3L7.5 24h4L12.5 22a8 8 0 0 0 5-3l2.4 1 2-3.5-2-1.5z',

  /* 헤더 */
  search:      'M11 4a7 7 0 1 1 0 14 7 7 0 0 1 0-14zM21 21l-4.35-4.35',
  bell:        'M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9zM10 21a2 2 0 0 0 4 0',
  bot:         'M12 2v2M5 10h14a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 15h.01M16 15h.01',
  menu:        'M4 6h16M4 12h16M4 18h16',
  dots:        'M12 6.5a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 13a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 19.5a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5z',
  close:       'M6 6l12 12M18 6L6 18',
  chevronRight:'M9 6l6 6-6 6',
  chevronDown: 'M6 9l6 6 6-6',
  plus:        'M12 5v14M5 12h14',
  minus:       'M5 12h14',
  refresh:     'M21 12a9 9 0 1 1-3-6.7L21 8M21 3v5h-5',
  terminal:    'M4 17l6-6-6-6M12 19h8',
  billing:     'M3 6a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6zM3 10h18M7 15h4',
  coins:       'M9 8.5a6 3 0 1 0 0-0.01zM3 5.5v6c0 1.66 2.69 3 6 3M3 8.5c0 1.66 2.69 3 6 3M15 11.5a6 3 0 1 0 0-0.01zM9 14.5v3c0 1.66 2.69 3 6 3s6-1.34 6-3v-6',
  chart:       'M3 3v18h18M7 14l4-4 3 3 5-6',

  /* 상태 */
  check:       'M20 6L9 17l-5-5',
  alert:       'M12 9v4M12 17h.01M10.3 3.86L1.82 18a2 2 0 0 0 1.72 3h16.92a2 2 0 0 0 1.72-3L13.71 3.86a2 2 0 0 0-3.42 0z',
  info:        'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM12 16v-4M12 8h.01',
  flame:       'M8.5 14.5A2.5 2.5 0 0 0 11 17a7 7 0 0 0 7-7c0-1.9-1.5-4.3-3.5-5.5-.4 2-2.2 4-4 4.5-1.8.5-3 2-3 4 0 .5.1 1 .3 1.5z',

  /* 활동/성능 */
  zap:         'M13 2L3 14h9l-1 8 10-12h-9l1-8z',
  trendUp:     'M23 6l-9.5 9.5-5-5L1 18M17 6h6v6',
  activity:    'M22 12h-4l-3 9L9 3l-3 9H2',
  pulse:       'M22 12h-4l-3 9L9 3l-3 9H2',
  kanban:      'M6 3v18M12 3v12M18 3v6M3 3h18v18H3z',

  /* 사람/에이전트 */
  user:        'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 1 0-8 4 4 0 0 1 0 8zM22 21v-2a4 4 0 0 0-3-3.87M15 3.13a4 4 0 0 1 0 7.75',
  cpu:         'M4 6h16v12H4zM8 2v2M16 2v2M8 20v2M16 20v2M2 8h2M2 16h2M20 8h2M20 16h2M10 10h4v4h-4z',
  trash:       'M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M10 11v6M14 11v6',

  /* 카드/워크 */
  folder:      'M3 7a2 2 0 0 1 2-2h4l2 3h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z',
  layers:      'M12 2 2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5',
  filter:      'M3 4h18l-7 9v7l-4-2v-5L3 4z',

  /* Settings 추가 */
  key:         'M15 2a5 5 0 1 1-4.9 6H2l2 2 2-2 2 2v3h3v3h3v-4h3v-3a5 5 0 0 1-.1-7z',
  users:       'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
  send:        'M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z',
  mail:        'M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM22 6l-10 7L2 6',
  loader:      'M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83',
  download:    'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3',
  shield:      'M12 2L4 6v6c0 5 3.5 9 8 10 4.5-1 8-5 8-10V6l-8-4z'
};

Utils.icon = function(name, size, strokeWidth) {
  var path = Icons[name];
  if (!path) return '<span>?</span>';
  var s = size || 18;
  var sw = strokeWidth || 1.75;
  return '<svg width="' + s + '" height="' + s +
    '" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="' + sw + '" stroke-linecap="round" stroke-linejoin="round" ' +
    'aria-hidden="true" focusable="false"><path d="' + path + '"/></svg>';
};

/* ═══════════════════════════════════════════════════════════
   Charts — Canvas 2D (Glassmorphism + Semi-circle Gauge)
   Bold lines, L→R gradient, glassmorphism-ready
   ═══════════════════════════════════════════════════════════ */
const Charts = {
  _history: {},
  _pulseFrames: {},
  _mono: null,
  /* Secondary color for each primary (for gradient) */
  _gradPairs: {
    '#1B96FF': '#06B6D4', '#4BCA81': '#34D399', '#FF5D2D': '#FE9339',
    '#FE9339': '#FCC003', '#8B5CF6': '#EC4899', '#1FC9E8': '#818CF8',
    '#E4A201': '#FE9339', '#EA001E': '#FF5D2D', '#5E6C84': '#8E9BAE',
    '#4BCA81': '#1FC9E8'
  },

  _font() { return this._mono || (this._mono = Utils.cssVar('--mono') || 'monospace'); },
  _track() { return 'rgba(255,255,255,0.06)'; },

  pushHistory(key, value) {
    if (!this._history[key]) this._history[key] = [];
    this._history[key].push(value);
    if (this._history[key].length > 30) this._history[key].shift();
  },
  getHistory(key) { return this._history[key] || []; },

  setupCanvas(canvas) {
    var dpr = window.devicePixelRatio || 1;
    var rect = canvas.getBoundingClientRect();
    if (rect.width < 1 || rect.height < 1) return { ctx: null, w: 0, h: 0 };
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    var ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);
    return { ctx: ctx, w: rect.width, h: rect.height };
  },

  _rgba(hex, a) {
    if (!hex) return 'rgba(255,255,255,' + a + ')';
    var m = hex.match(/^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})/i);
    if (!m) return hex;
    return 'rgba(' + parseInt(m[1],16) + ',' + parseInt(m[2],16) + ',' + parseInt(m[3],16) + ',' + a + ')';
  },

  _grad2(ctx, color) {
    return this._gradPairs[color] || color;
  },

  /** Semi-circle Gauge — 180deg arc, L→R gradient, bold stroke */
  drawDonut(canvas, value, total, color) {
    var s = this.setupCanvas(canvas);
    if (!s.ctx) return;
    var ctx = s.ctx, w = s.w, h = s.h;
    var cx = w / 2, cy = h * 0.65;
    var r = Math.min(cx, cy * 0.9) - 2;
    var lineW = Math.max(8, Math.round(r * 0.35));
    var pct = total > 0 ? value / total : 0;
    var self = this;

    ctx.clearRect(0, 0, w, h);

    /* Track — semi-circle (left to right) */
    ctx.beginPath();
    ctx.arc(cx, cy, r, Math.PI, 0);
    ctx.strokeStyle = self._track();
    ctx.lineWidth = lineW;
    ctx.lineCap = 'round';
    ctx.stroke();

    /* Value arc with L→R gradient */
    if (pct > 0) {
      var grad = ctx.createLinearGradient(cx - r, cy, cx + r, cy);
      grad.addColorStop(0, color);
      grad.addColorStop(1, self._grad2(ctx, color));

      /* Glow layer */
      ctx.save();
      ctx.shadowColor = self._rgba(color, 0.4);
      ctx.shadowBlur = 12;
      ctx.beginPath();
      ctx.arc(cx, cy, r, Math.PI, Math.PI + Math.PI * pct);
      ctx.strokeStyle = grad;
      ctx.lineWidth = lineW;
      ctx.lineCap = 'round';
      ctx.stroke();
      ctx.restore();

      /* Crisp layer */
      ctx.beginPath();
      ctx.arc(cx, cy, r, Math.PI, Math.PI + Math.PI * pct);
      ctx.strokeStyle = grad;
      ctx.lineWidth = lineW - 2;
      ctx.lineCap = 'round';
      ctx.stroke();
    }

    /* Center % text */
    var fs = Math.max(13, Math.round(r * 0.55));
    ctx.fillStyle = 'var(--text)';
    ctx.font = '800 ' + fs + 'px ' + self._font();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(Math.round(pct * 100) + '%', cx, cy - r * 0.1);
  },

  /** Sparkline — Bold bezier + gradient fill */
  drawSparkline(canvas, data, color) {
    var s = this.setupCanvas(canvas);
    if (!s.ctx) return;
    var ctx = s.ctx, w = s.w, h = s.h;
    var self = this;
    ctx.clearRect(0, 0, w, h);

    if (!data || data.length < 2) {
      ctx.strokeStyle = self._track();
      ctx.setLineDash([3, 4]);
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, h / 2);
      ctx.lineTo(w, h / 2);
      ctx.stroke();
      return;
    }

    var pad = 2;
    var min = Math.min.apply(null, data), max = Math.max.apply(null, data);
    var range = max - min || 1;
    var stepX = (w - pad * 2) / (data.length - 1);
    var pts = [];
    for (var i = 0; i < data.length; i++) {
      pts.push({ x: pad + i * stepX, y: pad + (1 - (data[i] - min) / range) * (h - pad * 2) });
    }

    var buildPath = function() {
      ctx.moveTo(pts[0].x, pts[0].y);
      for (var j = 1; j < pts.length; j++) {
        var cpx = (pts[j-1].x + pts[j].x) / 2;
        ctx.bezierCurveTo(cpx, pts[j-1].y, cpx, pts[j].y, pts[j].x, pts[j].y);
      }
    };

    /* L→R gradient fill */
    ctx.beginPath();
    buildPath();
    ctx.lineTo(pts[pts.length-1].x, h);
    ctx.lineTo(pts[0].x, h);
    ctx.closePath();
    var areaGrad = ctx.createLinearGradient(0, 0, w, 0);
    areaGrad.addColorStop(0, self._rgba(color, 0.25));
    areaGrad.addColorStop(1, self._rgba(self._grad2(ctx, color), 0.05));
    ctx.fillStyle = areaGrad;
    ctx.fill();

    /* Bold line with glow */
    var lineGrad = ctx.createLinearGradient(0, 0, w, 0);
    lineGrad.addColorStop(0, color);
    lineGrad.addColorStop(1, self._grad2(ctx, color));

    ctx.save();
    ctx.shadowColor = self._rgba(color, 0.5);
    ctx.shadowBlur = 6;
    ctx.beginPath();
    buildPath();
    ctx.strokeStyle = lineGrad;
    ctx.lineWidth = 2.5;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.stroke();
    ctx.restore();

    /* End dot */
    var last = pts[pts.length - 1];
    ctx.beginPath();
    ctx.arc(last.x, last.y, 3.5, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.beginPath();
    ctx.arc(last.x, last.y, 1.5, 0, Math.PI * 2);
    ctx.fillStyle = 'var(--text)';
    ctx.fill();
  },

  /** Stacked Bar — Bold rounded segments + gradient */
  drawStackedBar(canvas, segments) {
    var s = this.setupCanvas(canvas);
    if (!s.ctx) return;
    var ctx = s.ctx, w = s.w, h = s.h;
    var self = this;
    ctx.clearRect(0, 0, w, h);
    var total = 0;
    for (var i = 0; i < segments.length; i++) total += segments[i].value;
    if (!total) return;

    var barH = 14;
    var y = (h - barH) / 2 - 6;
    var r = barH / 2;

    /* Track */
    ctx.fillStyle = self._track();
    ctx.beginPath();
    ctx.roundRect(0, y, w, barH, r);
    ctx.fill();

    /* Segments with glow */
    var x = 0;
    for (i = 0; i < segments.length; i++) {
      var seg = segments[i];
      var segW = (seg.value / total) * w;
      if (segW < 1) { x += segW; continue; }
      ctx.save();
      ctx.shadowColor = self._rgba(seg.color, 0.4);
      ctx.shadowBlur = 4;
      ctx.fillStyle = seg.color;
      ctx.fillRect(x, y, segW, barH);
      ctx.restore();
      x += segW;
    }

    /* Round mask */
    ctx.globalCompositeOperation = 'destination-in';
    ctx.beginPath();
    ctx.roundRect(0, y, w, barH, r);
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';

    /* Labels */
    var font = self._font();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    x = 0;
    for (i = 0; i < segments.length; i++) {
      var sg = segments[i];
      var sw = (sg.value / total) * w;
      if (sw > 22) {
        ctx.fillStyle = sg.color;
        ctx.font = '700 10px ' + font;
        ctx.fillText(sg.value, x + sw / 2, y + barH + 4);
      }
      x += sw;
    }
  },

  /** Semi-circle Gauge — 180deg, L→R gradient, bold */
  drawArcGauge(canvas, percent, color) {
    var s = this.setupCanvas(canvas);
    if (!s.ctx) return;
    var ctx = s.ctx, w = s.w, h = s.h;
    var self = this;
    var cx = w / 2, cy = h * 0.7;
    var r = Math.min(cx, cy * 0.85) - 2;
    var lineW = Math.max(8, Math.round(r * 0.35));

    ctx.clearRect(0, 0, w, h);

    /* Track */
    ctx.beginPath();
    ctx.arc(cx, cy, r, Math.PI, 0);
    ctx.strokeStyle = self._track();
    ctx.lineWidth = lineW;
    ctx.lineCap = 'round';
    ctx.stroke();

    /* Value with gradient + glow */
    var pct = Math.min(Math.max(percent / 100, 0), 1);
    if (pct > 0) {
      var grad = ctx.createLinearGradient(cx - r, cy, cx + r, cy);
      grad.addColorStop(0, color);
      grad.addColorStop(1, self._grad2(ctx, color));

      ctx.save();
      ctx.shadowColor = self._rgba(color, 0.5);
      ctx.shadowBlur = 14;
      ctx.beginPath();
      ctx.arc(cx, cy, r, Math.PI, Math.PI + Math.PI * pct);
      ctx.strokeStyle = grad;
      ctx.lineWidth = lineW;
      ctx.lineCap = 'round';
      ctx.stroke();
      ctx.restore();

      ctx.beginPath();
      ctx.arc(cx, cy, r, Math.PI, Math.PI + Math.PI * pct);
      ctx.strokeStyle = grad;
      ctx.lineWidth = lineW - 2;
      ctx.lineCap = 'round';
      ctx.stroke();
    }

    /* Center text */
    var fs = Math.max(14, Math.round(r * 0.55));
    ctx.fillStyle = 'var(--text)';
    ctx.font = '800 ' + fs + 'px ' + self._font();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(percent + '%', cx, cy - r * 0.15);
  },

  /** Pulse — Glassmorphism style alert */
  drawPulse(canvas, count, color) {
    var key = canvas.id || 'pulse';
    if (this._pulseFrames[key]) cancelAnimationFrame(this._pulseFrames[key]);

    var s = this.setupCanvas(canvas);
    if (!s.ctx) return;
    var ctx = s.ctx, w = s.w, h = s.h;
    var cx = w / 2, cy = h / 2;
    var dpr = window.devicePixelRatio || 1;
    var baseR = Math.min(cx, cy) * 0.3;
    var self = this;

    if (count === 0) {
      ctx.clearRect(0, 0, w, h);
      var green = Utils.cssVar('--green') || '#4BCA81';
      /* Glass circle */
      ctx.beginPath();
      ctx.arc(cx, cy, baseR + 2, 0, Math.PI * 2);
      ctx.fillStyle = self._rgba(green, 0.1);
      ctx.fill();
      ctx.strokeStyle = self._rgba(green, 0.3);
      ctx.lineWidth = 1.5;
      ctx.stroke();
      ctx.fillStyle = green;
      ctx.font = '800 ' + Math.round(baseR * 0.7) + 'px ' + self._font();
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('OK', cx, cy);
      return;
    }

    var phase = 0;
    var animate = function() {
      phase = (phase + 0.018) % 1;
      ctx.save();
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);

      /* 2 pulse rings */
      for (var i = 0; i < 2; i++) {
        var p = (phase + i * 0.5) % 1;
        var rr = baseR + p * (Math.min(cx, cy) - baseR);
        ctx.beginPath();
        ctx.arc(cx, cy, rr, 0, Math.PI * 2);
        ctx.strokeStyle = self._rgba(color, (1 - p) * 0.35);
        ctx.lineWidth = 2 * (1 - p);
        ctx.stroke();
      }

      /* Glow center */
      ctx.save();
      ctx.shadowColor = self._rgba(color, 0.6);
      ctx.shadowBlur = 16;
      ctx.beginPath();
      ctx.arc(cx, cy, baseR, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
      ctx.restore();

      /* Glass highlight */
      var ig = ctx.createRadialGradient(cx - baseR * 0.2, cy - baseR * 0.3, 0, cx, cy, baseR);
      ig.addColorStop(0, 'rgba(255,255,255,0.25)');
      ig.addColorStop(1, 'transparent');
      ctx.beginPath();
      ctx.arc(cx, cy, baseR, 0, Math.PI * 2);
      ctx.fillStyle = ig;
      ctx.fill();

      ctx.fillStyle = 'var(--text)';
      ctx.font = '800 ' + Math.round(baseR * 0.8) + 'px ' + self._font();
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(count, cx, cy);

      ctx.restore();
      self._pulseFrames[key] = requestAnimationFrame(animate);
    };
    animate();
  },

  animateValue(el, from, to, duration, suffix) {
    suffix = suffix || '';
    var start = performance.now();
    var diff = to - from;
    var step = function(now) {
      var elapsed = now - start;
      var progress = Math.min(elapsed / duration, 1);
      var eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.round(from + diff * eased) + suffix;
      if (progress < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  },

  cleanup() {
    Object.values(this._pulseFrames).forEach(function(id) { cancelAnimationFrame(id); });
    this._pulseFrames = {};
  }
};
