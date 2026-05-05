/* U2DIA 재설계 — Sprints 뷰 (2026-04-17) */
const SprintsView = {
  async renderList(listEl, sprintId) {
    let teams = [];
    try { const ov = await API.overview(); teams = ov.teams || []; } catch(e) {}
    const allSprints = [];
    for (const t of teams.slice(0, 10)) {
      const team = t.team || t;
      try {
        const res = await API.get('/api/teams/' + team.team_id + '/sprints');
        (res.sprints || []).forEach(s => allSprints.push({ ...s, team_name: team.name }));
      } catch(e) {}
    }
    const active = allSprints.filter(s => s.phase !== 'Reflect' && s.phase !== 'Done');
    const done   = allSprints.filter(s => s.phase === 'Reflect' || s.phase === 'Done');

    let html = '<div class="shell-list__header"><span class="shell-list__title">\uc2a4\ud504\ub9b0\ud2b8</span></div><div class="shell-list__body">';
    if (!allSprints.length) {
      html += '<div class="u-empty"><div class="u-empty__title">\uc2a4\ud504\ub9b0\ud2b8 \uc5c6\uc74c</div></div>';
    } else {
      if (active.length) {
        html += '<div style="padding:var(--space-2) var(--space-3);font-size:var(--text-xs);color:var(--text-muted-new);text-transform:uppercase">\ud65c\uc131 (' + active.length + ')</div>';
        active.forEach(s => {
          const act = s.sprint_id === sprintId;
          html += '<div class="u-list-item' + (act ? ' u-list-item--active' : '') + '" onclick="Router.navigate(\'#/sprints/' + Utils.esc(s.sprint_id) + '\')">' +
            '<div style="flex:1;min-width:0">' +
            '<div style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">' + Utils.esc(s.name || s.sprint_id) + '</div>' +
            '<div style="font-size:var(--text-xs);color:var(--text-muted-new)">' + Utils.esc(s.team_name || '') + ' \u00b7 ' + Utils.esc(s.phase || '\u2014') + '</div>' +
            '</div></div>';
        });
      }
      if (done.length) {
        html += '<div style="padding:var(--space-2) var(--space-3);font-size:var(--text-xs);color:var(--text-muted-new);text-transform:uppercase;margin-top:var(--space-3)">\uc644\ub8cc (' + done.length + ')</div>';
        done.forEach(s => {
          const act = s.sprint_id === sprintId;
          html += '<div class="u-list-item' + (act ? ' u-list-item--active' : '') + '" onclick="Router.navigate(\'#/sprints/' + Utils.esc(s.sprint_id) + '\')"><span style="opacity:0.6">' + Utils.esc(s.name || s.sprint_id) + '</span></div>';
        });
      }
    }
    html += '</div>';
    listEl.innerHTML = html;
  },

  async render(mainEl, sprintId) {
    if (!sprintId) {
      mainEl.innerHTML =
        '<div class="shell-main__content">' +
        '<div class="u-empty"><div class="u-empty__icon">' + Utils.icon('zap', 40, 1.25) + '</div><div class="u-empty__title">\uc2a4\ud504\ub9b0\ud2b8\ub97c \uc120\ud0dd\ud558\uc138\uc694</div></div>' +
        '</div>';
      return;
    }
    mainEl.innerHTML = '<div class="shell-main__content"><div class="u-skeleton u-skeleton--block"></div></div>';
    try {
      const [sprintRes, burndownRes, retroRes] = await Promise.all([
        API.get('/api/sprints/' + encodeURIComponent(sprintId)),
        API.get('/api/sprints/' + encodeURIComponent(sprintId) + '/burndown').catch(() => null),
        API.get('/api/sprints/' + encodeURIComponent(sprintId) + '/retro').catch(() => null)
      ]);
      const s = sprintRes || {};
      const phases = ['Think', 'Plan', 'Build', 'Review', 'Test', 'Ship', 'Reflect'];
      const currentIdx = phases.indexOf(s.phase || 'Think');
      const phaseRow = phases.map((p, i) => {
        const done = i < currentIdx;
        const active = i === currentIdx;
        const cls = active ? 'sprint-phase sprint-phase--active' : done ? 'sprint-phase sprint-phase--done' : 'sprint-phase';
        return '<div class="' + cls + '"><span class="sprint-phase__idx">' + (i+1) + '</span><span class="sprint-phase__label">' + p + '</span></div>';
      }).join('<div class="sprint-phase__sep"></div>');

      const gates = (s.gates || []).map(g =>
        '<div class="sprint-gate sprint-gate--' + (g.status || 'pending').toLowerCase() + '">' +
        '<div class="sprint-gate__name">' + Utils.esc(g.gate_type || '-') + '</div>' +
        '<div class="sprint-gate__status">' + Utils.esc(g.status || 'Pending') + (g.score ? ' (' + g.score + '/10)' : '') + '</div>' +
        '</div>').join('') || '<div class="u-empty"><div class="u-empty__desc">\uac8c\uc774\ud2b8 \uc5c6\uc74c</div></div>';

      const burndownData = burndownRes && burndownRes.burndown ? burndownRes.burndown : [];
      const burndownSvg = burndownData.length > 1
        ? (() => {
            const w = 600, h = 120, pad = 8;
            const max = Math.max(1, ...burndownData.map(d => d.remaining || 0));
            const pts = burndownData.map((d, i) => {
              const x = pad + (i / (burndownData.length - 1)) * (w - pad * 2);
              const y = pad + (1 - (d.remaining || 0) / max) * (h - pad * 2);
              return x.toFixed(1) + ',' + y.toFixed(1);
            }).join(' ');
            return '<svg viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none" style="width:100%;height:120px">' +
              '<polyline points="' + pts + '" fill="none" stroke="var(--brand-light)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' +
              '</svg>';
          })()
        : '<div class="u-empty"><div class="u-empty__desc">\ub370\uc774\ud130 \ubd80\uc871</div></div>';

      const retro = retroRes && retroRes.retro ? retroRes.retro : null;

      mainEl.innerHTML =
        '<div class="shell-main__content">' +
        '<div class="sprint-header">' +
        '  <h1 class="sprint-title">' + Utils.esc(s.name || sprintId) + '</h1>' +
        '  <div class="sprint-goal">' + Utils.esc(s.goal || '\ubaa9\ud45c \uc5c6\uc74c') + '</div>' +
        '</div>' +
        '<div class="u-panel" style="margin-top:var(--space-4)">' +
        '  <div class="u-panel__header"><h2 class="u-panel__title">\ud398\uc774\uc988 \ud0c0\uc784\ub77c\uc778</h2><span class="u-badge u-badge--brand">' + Utils.esc(s.phase || '\u2014') + '</span></div>' +
        '  <div class="u-panel__body"><div class="sprint-phases">' + phaseRow + '</div></div>' +
        '</div>' +
        '<div class="sprint-grid" style="margin-top:var(--space-4)">' +
        '  <div class="u-panel">' +
        '    <div class="u-panel__header"><h2 class="u-panel__title">\ud488\uc9c8 \uac8c\uc774\ud2b8</h2></div>' +
        '    <div class="u-panel__body sprint-gates">' + gates + '</div>' +
        '  </div>' +
        '  <div class="u-panel">' +
        '    <div class="u-panel__header"><h2 class="u-panel__title">\ubc88\ub2e4\uc6b4</h2></div>' +
        '    <div class="u-panel__body">' + burndownSvg + '</div>' +
        '  </div>' +
        '</div>' +
        (retro ? (
          '<div class="u-panel" style="margin-top:var(--space-4)">' +
          '  <div class="u-panel__header"><h2 class="u-panel__title">\ud68c\uace0</h2></div>' +
          '  <div class="u-panel__body"><pre style="white-space:pre-wrap;font-family:var(--font);font-size:13px;line-height:1.6;color:var(--text-secondary)">' + Utils.esc(retro.content || JSON.stringify(retro, null, 2)) + '</pre></div>' +
          '</div>'
        ) : '') +
        '</div>';
    } catch(e) {
      mainEl.innerHTML = '<div class="shell-main__content"><div class="u-empty"><div class="u-empty__title">\ub85c\ub529 \uc2e4\ud328</div><div class="u-empty__desc">' + Utils.esc(e.message || String(e)) + '</div></div></div>';
    }
  }
};

if (typeof App !== 'undefined') App.registerView('sprints', SprintsView);
