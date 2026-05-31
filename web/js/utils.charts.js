// utils.charts.js — 순수 inline SVG 차트 라이브러리 (외부 의존성 0)
// 전역 SvgCharts. 각 함수는 SVG 문자열을 반환 (DOM 미생성, innerHTML 용도).
// (utils.js 의 Canvas 기반 Charts 객체와 이름 충돌 방지를 위해 SvgCharts 사용)

const SvgCharts = (function () {
  'use strict';

  // ── 내부 헬퍼 ──────────────────────────────────────────────

  // 큰 수 축약: 1.2K / 3.4M / 2.1B
  function abbr(n) {
    const v = Number(n) || 0;
    const a = Math.abs(v);
    if (a >= 1e9) return (v / 1e9).toFixed(1).replace(/\.0$/, '') + 'B';
    if (a >= 1e6) return (v / 1e6).toFixed(1).replace(/\.0$/, '') + 'M';
    if (a >= 1e3) return (v / 1e3).toFixed(1).replace(/\.0$/, '') + 'K';
    return String(Math.round(v * 100) / 100);
  }

  // USD: $ + 천단위 콤마
  function usd(n) {
    const v = Number(n) || 0;
    const sign = v < 0 ? '-' : '';
    const abs = Math.abs(v);
    const fixed = abs >= 100 ? abs.toFixed(0) : abs.toFixed(2);
    const parts = fixed.split('.');
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return sign + '$' + parts.join('.');
  }

  // 안전한 텍스트 escape (라벨용)
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  // 숫자 반올림 (좌표 깔끔하게)
  function r(n) {
    return Math.round(n * 100) / 100;
  }

  // SVG 컨테이너 래퍼
  function svg(w, h, label, inner) {
    return (
      '<svg class="u-chart" width="' + w + '" height="' + h + '" ' +
      'viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="xMidYMid meet" ' +
      'role="img" aria-label="' + esc(label) + '" xmlns="http://www.w3.org/2000/svg">' +
      inner +
      '</svg>'
    );
  }

  // 고유 id 생성 (gradient 충돌 방지)
  let _uid = 0;
  function uid(prefix) {
    _uid += 1;
    return (prefix || 'c') + '-' + _uid + '-' + Math.floor(Math.random() * 1e6);
  }

  // ── 1. sparkline ───────────────────────────────────────────
  function sparkline(values, opts) {
    opts = opts || {};
    const w = opts.w || 120;
    const h = opts.h || 32;
    const stroke = opts.stroke || 'var(--brand)';
    const fill = opts.fill !== false;
    const data = (values || []).map(Number).filter(function (v) { return !isNaN(v); });

    if (data.length <= 1) {
      return svg(w, h, 'sparkline (no data)', '');
    }

    const pad = 2;
    const min = Math.min.apply(null, data);
    const max = Math.max.apply(null, data);
    const span = max - min || 1;
    const stepX = (w - pad * 2) / (data.length - 1);

    const pts = data.map(function (v, i) {
      const x = pad + i * stepX;
      const y = pad + (h - pad * 2) * (1 - (v - min) / span);
      return r(x) + ',' + r(y);
    });

    const line = '<polyline points="' + pts.join(' ') + '" fill="none" ' +
      'stroke="' + stroke + '" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" />';

    let area = '';
    let defs = '';
    if (fill) {
      const gid = uid('spark');
      defs =
        '<defs><linearGradient id="' + gid + '" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0%" stop-color="' + stroke + '" stop-opacity="0.28" />' +
        '<stop offset="100%" stop-color="' + stroke + '" stop-opacity="0" />' +
        '</linearGradient></defs>';
      const areaPts = pts.slice();
      areaPts.push(r(pad + (data.length - 1) * stepX) + ',' + r(h - pad));
      areaPts.unshift(r(pad) + ',' + r(h - pad));
      area = '<polygon points="' + areaPts.join(' ') + '" fill="url(#' + gid + ')" stroke="none" />';
    }

    return svg(w, h, 'sparkline', defs + area + line);
  }

  // ── 2. donut ───────────────────────────────────────────────
  function donut(segments, opts) {
    opts = opts || {};
    const size = opts.size || 160;
    const hole = opts.hole != null ? opts.hole : 0.62;
    const showTotal = opts.showTotal !== false;
    const segs = (segments || []).filter(function (s) { return s && Number(s.value) > 0; });

    const cx = size / 2;
    const cy = size / 2;
    const rOuter = size / 2 - 4;
    const thickness = rOuter * (1 - hole);
    const rMid = rOuter - thickness / 2; // stroke 중심 반지름
    const circ = 2 * Math.PI * rMid;

    const total = segs.reduce(function (a, s) { return a + Number(s.value); }, 0);

    let inner = '';

    if (total <= 0) {
      // 빈 회색 링
      inner +=
        '<circle cx="' + cx + '" cy="' + cy + '" r="' + r(rMid) + '" fill="none" ' +
        'stroke="var(--line)" stroke-width="' + r(thickness) + '" />';
      if (showTotal) {
        inner += '<text x="' + cx + '" y="' + (cy + 4) + '" text-anchor="middle" ' +
          'fill="var(--muted)" font-size="13" font-weight="600">0</text>';
      }
      return svg(size, size, 'donut chart (empty)', inner);
    }

    // 트랙
    inner +=
      '<circle cx="' + cx + '" cy="' + cy + '" r="' + r(rMid) + '" fill="none" ' +
      'stroke="var(--line)" stroke-width="' + r(thickness) + '" />';

    const palette = ['var(--chart-blue)', 'var(--chart-green)', 'var(--chart-orange)',
      'var(--chart-purple)', 'var(--chart-cyan)', 'var(--chart-yellow)',
      'var(--chart-pink)', 'var(--chart-indigo)'];

    let offset = 0;
    segs.forEach(function (s, i) {
      const frac = Number(s.value) / total;
      const len = frac * circ;
      const color = s.color || palette[i % palette.length];
      inner +=
        '<circle cx="' + cx + '" cy="' + cy + '" r="' + r(rMid) + '" fill="none" ' +
        'stroke="' + color + '" stroke-width="' + r(thickness) + '" ' +
        'stroke-dasharray="' + r(len) + ' ' + r(circ - len) + '" ' +
        'stroke-dashoffset="' + r(-offset) + '" ' +
        'transform="rotate(-90 ' + cx + ' ' + cy + ')" ' +
        'stroke-linecap="butt"><title>' + esc(s.label || '') + ': ' + abbr(s.value) + '</title></circle>';
      offset += len;
    });

    if (showTotal) {
      inner +=
        '<text x="' + cx + '" y="' + (cy - 2) + '" text-anchor="middle" ' +
        'fill="var(--text)" font-size="18" font-weight="700">' + abbr(total) + '</text>' +
        '<text x="' + cx + '" y="' + (cy + 15) + '" text-anchor="middle" ' +
        'fill="var(--text-secondary)" font-size="11">Total</text>';
    }

    return svg(size, size, 'donut chart', inner);
  }

  // ── 3. bars (세로 막대) ────────────────────────────────────
  function bars(rows, opts) {
    opts = opts || {};
    const w = opts.w || 600;
    const h = opts.h || 240;
    const fmt = opts.fmt || function (v) { return abbr(v); };
    const maxBars = opts.maxBars || 24;
    let data = (rows || []).slice(0, maxBars);

    const padL = 8;
    const padR = 8;
    const padT = 20;   // 막대 위 값 공간
    const padB = 38;   // x축 라벨 공간
    const plotW = w - padL - padR;
    const plotH = h - padT - padB;

    if (!data.length) {
      return svg(w, h, 'bar chart (no data)',
        '<text x="' + (w / 2) + '" y="' + (h / 2) + '" text-anchor="middle" ' +
        'fill="var(--muted)" font-size="12">No data</text>');
    }

    const maxV = Math.max.apply(null, data.map(function (d) { return Number(d.value) || 0; })) || 1;
    const palette = ['var(--chart-blue)', 'var(--chart-green)', 'var(--chart-purple)',
      'var(--chart-cyan)', 'var(--chart-orange)'];

    const slot = plotW / data.length;
    const barW = Math.max(4, Math.min(slot * 0.66, 48));
    const rotate = data.length > 8;

    let inner = '';

    // baseline
    const baseY = padT + plotH;
    inner += '<line x1="' + padL + '" y1="' + r(baseY) + '" x2="' + (w - padR) +
      '" y2="' + r(baseY) + '" stroke="var(--line)" stroke-width="1" />';

    data.forEach(function (d, i) {
      const v = Number(d.value) || 0;
      const bh = (v / maxV) * plotH;
      const x = padL + slot * i + (slot - barW) / 2;
      const y = baseY - bh;
      const color = d.color || palette[i % palette.length];

      inner +=
        '<rect x="' + r(x) + '" y="' + r(y) + '" width="' + r(barW) + '" height="' + r(bh) + '" ' +
        'rx="3" fill="' + color + '"><title>' + esc(d.label) + ': ' + fmt(v) + '</title></rect>';

      // 값 라벨 (막대 위)
      inner +=
        '<text x="' + r(x + barW / 2) + '" y="' + r(y - 5) + '" text-anchor="middle" ' +
        'fill="var(--text-secondary)" font-size="11">' + esc(fmt(v)) + '</text>';

      // x축 라벨
      const lx = x + barW / 2;
      if (rotate) {
        inner +=
          '<text x="' + r(lx) + '" y="' + r(baseY + 12) + '" text-anchor="end" ' +
          'fill="var(--text-secondary)" font-size="11" ' +
          'transform="rotate(-40 ' + r(lx) + ' ' + r(baseY + 12) + ')">' + esc(d.label) + '</text>';
      } else {
        inner +=
          '<text x="' + r(lx) + '" y="' + r(baseY + 16) + '" text-anchor="middle" ' +
          'fill="var(--text-secondary)" font-size="11">' + esc(d.label) + '</text>';
      }
    });

    return svg(w, h, 'bar chart', inner);
  }

  // ── 4. stackedBars (누적 세로 막대 + 범례) ─────────────────
  function stackedBars(rows, series, opts) {
    opts = opts || {};
    const w = opts.w || 600;
    const h = opts.h || 260;
    const fmt = opts.fmt || function (v) { return abbr(v); };
    const data = rows || [];
    const ser = series || [];

    const padL = 8;
    const padR = 8;
    const padT = 14;
    const legendH = 26;
    const padB = 38;
    const plotW = w - padL - padR;
    const plotH = h - padT - padB - legendH;

    if (!data.length || !ser.length) {
      return svg(w, h, 'stacked bar chart (no data)',
        '<text x="' + (w / 2) + '" y="' + (h / 2) + '" text-anchor="middle" ' +
        'fill="var(--muted)" font-size="12">No data</text>');
    }

    // 행별 합계 → 최댓값
    const totals = data.map(function (d) {
      return ser.reduce(function (a, s) { return a + (Number(d[s.key]) || 0); }, 0);
    });
    const maxV = Math.max.apply(null, totals) || 1;

    const slot = plotW / data.length;
    const barW = Math.max(4, Math.min(slot * 0.66, 48));
    const rotate = data.length > 8;
    const baseY = padT + plotH;

    let inner = '';

    // baseline
    inner += '<line x1="' + padL + '" y1="' + r(baseY) + '" x2="' + (w - padR) +
      '" y2="' + r(baseY) + '" stroke="var(--line)" stroke-width="1" />';

    data.forEach(function (d, i) {
      const x = padL + slot * i + (slot - barW) / 2;
      let acc = 0; // 누적 높이 (아래에서 위로)
      ser.forEach(function (s) {
        const v = Number(d[s.key]) || 0;
        if (v <= 0) return;
        const segH = (v / maxV) * plotH;
        const y = baseY - acc - segH;
        inner +=
          '<rect x="' + r(x) + '" y="' + r(y) + '" width="' + r(barW) + '" height="' + r(segH) + '" ' +
          'fill="' + s.color + '"><title>' + esc(d.label) + ' · ' + esc(s.label) + ': ' +
          fmt(v) + '</title></rect>';
        acc += segH;
      });

      // 총합 라벨
      const tot = totals[i];
      if (tot > 0) {
        inner += '<text x="' + r(x + barW / 2) + '" y="' + r(baseY - acc - 5) +
          '" text-anchor="middle" fill="var(--text-secondary)" font-size="11">' +
          esc(fmt(tot)) + '</text>';
      }

      // x축 라벨
      const lx = x + barW / 2;
      if (rotate) {
        inner += '<text x="' + r(lx) + '" y="' + r(baseY + 12) + '" text-anchor="end" ' +
          'fill="var(--text-secondary)" font-size="11" ' +
          'transform="rotate(-40 ' + r(lx) + ' ' + r(baseY + 12) + ')">' + esc(d.label) + '</text>';
      } else {
        inner += '<text x="' + r(lx) + '" y="' + r(baseY + 16) + '" text-anchor="middle" ' +
          'fill="var(--text-secondary)" font-size="11">' + esc(d.label) + '</text>';
      }
    });

    // 범례 (하단)
    const legendY = h - 8;
    let lx = padL + 4;
    ser.forEach(function (s) {
      const labelW = String(s.label).length * 6.5 + 22;
      inner +=
        '<rect x="' + r(lx) + '" y="' + r(legendY - 9) + '" width="10" height="10" rx="2" fill="' + s.color + '" />' +
        '<text x="' + r(lx + 14) + '" y="' + r(legendY) + '" ' +
        'fill="var(--text-secondary)" font-size="11">' + esc(s.label) + '</text>';
      lx += labelW;
    });

    return svg(w, h, 'stacked bar chart', inner);
  }

  // ── 5. timeseries (라인 + area) ────────────────────────────
  function timeseries(points, opts) {
    opts = opts || {};
    const w = opts.w || 600;
    const h = opts.h || 240;
    const stroke = opts.stroke || 'var(--chart-blue)';
    const fmt = opts.fmt || function (v) { return abbr(v); };
    const area = opts.area !== false;
    const data = (points || []).filter(function (p) { return p && !isNaN(Number(p.y)); });

    const padL = 48;
    const padR = 12;
    const padT = 14;
    const padB = 34;
    const plotW = w - padL - padR;
    const plotH = h - padT - padB;

    if (data.length <= 1) {
      return svg(w, h, 'time series (no data)',
        '<text x="' + (w / 2) + '" y="' + (h / 2) + '" text-anchor="middle" ' +
        'fill="var(--muted)" font-size="12">No data</text>');
    }

    const ys = data.map(function (p) { return Number(p.y); });
    const minY = Math.min.apply(null, ys);
    const maxYraw = Math.max.apply(null, ys);
    const lo = Math.min(0, minY);
    const hi = maxYraw > lo ? maxYraw : lo + 1;
    const span = hi - lo || 1;

    const stepX = plotW / (data.length - 1);
    const baseY = padT + plotH;

    function xAt(i) { return padL + i * stepX; }
    function yAt(v) { return padT + plotH * (1 - (v - lo) / span); }

    let inner = '';
    let defs = '';

    // y축 grid (4줄) + 라벨
    const gridN = 4;
    for (let g = 0; g <= gridN; g++) {
      const val = lo + (span * g) / gridN;
      const gy = yAt(val);
      inner += '<line x1="' + padL + '" y1="' + r(gy) + '" x2="' + (w - padR) +
        '" y2="' + r(gy) + '" stroke="var(--line)" stroke-width="1" />';
      inner += '<text x="' + (padL - 6) + '" y="' + r(gy + 4) + '" text-anchor="end" ' +
        'fill="var(--text-secondary)" font-size="11">' + esc(fmt(val)) + '</text>';
    }

    // 라인 points
    const pts = data.map(function (p, i) { return r(xAt(i)) + ',' + r(yAt(Number(p.y))); });

    // area
    if (area) {
      const gid = uid('ts');
      defs =
        '<defs><linearGradient id="' + gid + '" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0%" stop-color="' + stroke + '" stop-opacity="0.25" />' +
        '<stop offset="100%" stop-color="' + stroke + '" stop-opacity="0" />' +
        '</linearGradient></defs>';
      const ap = pts.slice();
      ap.push(r(xAt(data.length - 1)) + ',' + r(baseY));
      ap.unshift(r(xAt(0)) + ',' + r(baseY));
      inner += '<polygon points="' + ap.join(' ') + '" fill="url(#' + gid + ')" stroke="none" />';
    }

    inner += '<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + stroke +
      '" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />';

    // 점 + title
    data.forEach(function (p, i) {
      inner += '<circle cx="' + r(xAt(i)) + '" cy="' + r(yAt(Number(p.y))) + '" r="2.5" ' +
        'fill="' + stroke + '"><title>' + esc(p.x) + ': ' + fmt(Number(p.y)) + '</title></circle>';
    });

    // x축 라벨 (듬성듬성)
    const every = Math.max(1, Math.ceil(data.length / 8));
    data.forEach(function (p, i) {
      if (i % every !== 0 && i !== data.length - 1) return;
      inner += '<text x="' + r(xAt(i)) + '" y="' + r(baseY + 16) + '" text-anchor="middle" ' +
        'fill="var(--text-secondary)" font-size="11">' + esc(p.x) + '</text>';
    });

    return svg(w, h, 'time series chart', defs + inner);
  }

  // ── 6. gauge (반원 게이지) ─────────────────────────────────
  function gauge(value, opts) {
    opts = opts || {};
    const size = opts.size || 160;
    const thresholds = opts.thresholds || [60, 80];
    const label = opts.label || '';
    const v = Math.max(0, Math.min(100, Number(value) || 0));

    const w = size;
    const h = size * 0.62; // 반원 + 텍스트 여백
    const cx = w / 2;
    const cy = h - 10;
    const rad = size / 2 - 12;
    const sw = Math.max(8, rad * 0.18);

    // 색상 결정
    let color = 'var(--green)';
    if (v >= thresholds[1]) color = 'var(--red)';
    else if (v >= thresholds[0]) color = 'var(--orange)';

    // 반원 호 (왼쪽 180° → 오른쪽 0°)
    function pt(angleDeg, radius) {
      const a = (Math.PI * (180 - angleDeg)) / 180; // 180=좌, 0=우
      return [cx + radius * Math.cos(a), cy - radius * Math.sin(a)];
    }

    const start = pt(0, rad);
    const end = pt(180, rad);
    const trackPath =
      'M ' + r(start[0]) + ' ' + r(start[1]) +
      ' A ' + r(rad) + ' ' + r(rad) + ' 0 0 1 ' + r(end[0]) + ' ' + r(end[1]);

    // 값 호
    const valAngle = (v / 100) * 180;
    const ve = pt(valAngle, rad);
    const largeArc = valAngle > 180 ? 1 : 0;
    const valPath =
      'M ' + r(start[0]) + ' ' + r(start[1]) +
      ' A ' + r(rad) + ' ' + r(rad) + ' 0 ' + largeArc + ' 1 ' + r(ve[0]) + ' ' + r(ve[1]);

    let inner =
      '<path d="' + trackPath + '" fill="none" stroke="var(--line)" stroke-width="' + r(sw) + '" stroke-linecap="round" />' +
      '<path d="' + valPath + '" fill="none" stroke="' + color + '" stroke-width="' + r(sw) + '" stroke-linecap="round" />' +
      '<text x="' + cx + '" y="' + r(cy - 6) + '" text-anchor="middle" ' +
      'fill="var(--text)" font-size="22" font-weight="700">' + Math.round(v) + '%</text>';

    if (label) {
      inner += '<text x="' + cx + '" y="' + r(cy + 12) + '" text-anchor="middle" ' +
        'fill="var(--text-secondary)" font-size="11">' + esc(label) + '</text>';
    }

    return svg(w, h, 'gauge ' + Math.round(v) + '%' + (label ? ' ' + label : ''), inner);
  }

  // ── multiLine (멀티 시리즈 꺾은선) ─────────────────────────
  // series: [{label, color, points:[number,...]}]  (모든 series 동일 길이 = xLabels.length)
  // opts: { w, h, xLabels, fmt, dots }
  function multiLine(series, opts) {
    opts = opts || {};
    const xLabels = opts.xLabels || [];
    const n = xLabels.length;
    const w = opts.w || Math.max(560, n * 70);
    const h = opts.h || 300;
    const fmt = opts.fmt || function (v) { return abbr(v); };
    const dots = opts.dots !== false;
    const ss = (series || []).filter(function (s) { return s && s.points && s.points.length; });

    const padL = 56, padR = 16, padT = 16, padB = 40;
    const plotW = w - padL - padR;
    const plotH = h - padT - padB;

    if (!ss.length || n < 2) {
      return svg(w, h, 'multi-line (no data)',
        '<text x="' + (w / 2) + '" y="' + (h / 2) + '" text-anchor="middle" fill="var(--muted)" font-size="12">No data</text>');
    }

    let maxV = 0;
    ss.forEach(function (s) {
      s.points.forEach(function (v) { if (Number(v) > maxV) maxV = Number(v); });
    });
    maxV = maxV || 1;

    const stepX = plotW / (n - 1);
    const X = function (i) { return padL + i * stepX; };
    const Y = function (v) { return padT + plotH * (1 - (Number(v) || 0) / maxV); };

    let inner = '';

    // y grid (4줄) + 라벨
    const grids = 4;
    for (let g = 0; g <= grids; g++) {
      const gv = maxV * g / grids;
      const gy = Y(gv);
      inner += '<line x1="' + padL + '" y1="' + r(gy) + '" x2="' + (w - padR) + '" y2="' + r(gy) +
        '" stroke="var(--line)" stroke-width="1" />';
      inner += '<text x="' + (padL - 8) + '" y="' + r(gy + 4) + '" text-anchor="end" ' +
        'fill="var(--muted)" font-size="10">' + fmt(gv) + '</text>';
    }

    // x 라벨 (듬성듬성)
    const xevery = Math.ceil(n / 12);
    for (let i = 0; i < n; i++) {
      if (i % xevery !== 0 && i !== n - 1) continue;
      inner += '<text x="' + r(X(i)) + '" y="' + (h - padB + 16) + '" text-anchor="middle" ' +
        'fill="var(--muted)" font-size="10">' + esc(xLabels[i]) + '</text>';
    }

    // 각 라인
    ss.forEach(function (s, si) {
      const color = s.color || ['var(--chart-blue)', 'var(--chart-green)', 'var(--chart-orange)',
        'var(--chart-purple)', 'var(--chart-cyan)'][si % 5];
      const sw = s.emphasis ? 2.6 : 1.8;
      const pts = s.points.map(function (v, i) { return r(X(i)) + ',' + r(Y(v)); });
      inner += '<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + color + '" ' +
        'stroke-width="' + sw + '" stroke-linejoin="round" stroke-linecap="round"' +
        (s.dash ? ' stroke-dasharray="5 4"' : '') + ' />';
      if (dots) {
        s.points.forEach(function (v, i) {
          inner += '<circle cx="' + r(X(i)) + '" cy="' + r(Y(v)) + '" r="2.6" fill="' + color + '">' +
            '<title>' + esc(s.label + ' · ' + xLabels[i] + ': ' + fmt(v)) + '</title></circle>';
        });
      }
    });

    return svg(w, h, 'multi-line chart', inner);
  }

  // ── 공개 API ───────────────────────────────────────────────
  return {
    sparkline: sparkline,
    donut: donut,
    bars: bars,
    stackedBars: stackedBars,
    timeseries: timeseries,
    multiLine: multiLine,
    gauge: gauge,
    // 포맷 헬퍼도 노출 (뷰에서 재사용)
    fmt: { abbr: abbr, usd: usd }
  };
})();

// ── 사용 예시 ──────────────────────────────────────────────
// el.innerHTML = SvgCharts.sparkline([3,5,4,8,6,9], { stroke: 'var(--green)' });
// el.innerHTML = SvgCharts.donut([{label:'Sub',value:2508,color:'var(--chart-blue)'},{label:'Addon',value:16284,color:'var(--chart-green)'}]);
// el.innerHTML = SvgCharts.timeseries(months.map(m => ({x:m.month, y:m.total_paid_usd})), { fmt: SvgCharts.fmt.usd });
