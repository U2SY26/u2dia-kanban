/* U2DIA AI SERVER AGENT — Utilities (Salesforce Lightning)
 * SECURITY: All user-facing HTML rendering uses Utils.esc() to sanitize
 * input before innerHTML assignment, preventing XSS attacks.
 * Utils.esc() uses textContent-based escaping (DOM-native safe method).
 */
const Utils = {
  /** Number format with commas */
  fmtNum(n) { return (n || 0).toLocaleString(); },

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
