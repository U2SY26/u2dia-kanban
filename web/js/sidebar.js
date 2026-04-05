/* U2DIA AI SERVER AGENT — Sidebar v1.0 (Dual-mode: projects ↔ teams) */
const Sidebar = {
  _mode: 'projects',   // 'projects' | 'teams'
  _projects: [],
  _teams: [],
  _selectedProject: null,
  _selectedTeam: null,
  _el: null,

  async init() {
    this._el = document.getElementById('wsSidebar');
    if (!this._el) return;
    await this.refresh();
    // 30초마다 자동 갱신
    var self = this;
    setInterval(function() { self.refresh(); }, 30000);
  },

  async refresh() {
    try {
      var res = await API.get('/api/github/projects');
      if (res.ok && res.projects) this._projects = res.projects;
    } catch(e) {}
    try {
      var ov = await API.overview();
      if (ov.ok && ov.teams) this._teams = ov.teams;
    } catch(e) {}
    this._render();
  },

  updateTeams(teams) {
    if (teams) this._teams = teams;
    this._render();
  },

  _teamsByProject(projectName) {
    if (!projectName) return [];
    var proj = this._projects.find(function(p) { return p.name === projectName; });
    var alias = (proj && proj.alias) ? proj.alias : '';
    var nameLow = projectName.toLowerCase();
    return this._teams.filter(function(t) {
      var team = t.team || t;
      var g = (team.project_group || t.project_group || '').toLowerCase();
      return g === nameLow || (alias && g === alias.toLowerCase()) ||
             g.indexOf(nameLow) >= 0 || nameLow.indexOf(g) >= 0;
    });
  },

  _render() {
    if (!this._el) return;
    if (this._mode === 'projects') this._renderProjects();
    else this._renderTeams();
  },

  _renderProjects() {
    if (!this._el) return;
    var self = this;
    var IDLE_MS = 7 * 24 * 60 * 60 * 1000; // 7일
    var now = Date.now();

    // last_activity 기준으로 정렬: 최신순, 없으면 team_count로
    var sorted = this._projects.slice().sort(function(a, b) {
      var ta = a.last_activity ? new Date(a.last_activity).getTime() : 0;
      var tb = b.last_activity ? new Date(b.last_activity).getTime() : 0;
      if (tb !== ta) return tb - ta;
      return (b.team_count || 0) - (a.team_count || 0);
    });

    // 활성 vs 유휴 분리 (7일 기준)
    var active = [], idle = [];
    sorted.forEach(function(proj) {
      var lastTs = proj.last_activity ? new Date(proj.last_activity).getTime() : 0;
      if (lastTs > 0 && (now - lastTs) < IDLE_MS) active.push(proj);
      else idle.push(proj);
    });

    var html = [
      '<div class="sb-header">',
      '  <span class="sb-header-title">Projects</span>',
      '  <span class="sb-badge">' + this._projects.length + '</span>',
      '</div>',
      '<div class="sb-scroll">'
    ];

    if (!this._projects.length) {
      html.push('<div class="sb-empty">프로젝트 없음<br><small>/api/github/projects</small></div>');
    }

    function renderProjItem(proj) {
      var teams = self._teamsByProject(proj.name);
      var isActive = self._selectedProject === proj.name;
      var icon = proj.is_git
        ? '<span class="proj-icon git">⬡</span>'
        : '<span class="proj-icon dir">◻</span>';

      var projDone = 0, projTotal = 0;
      teams.forEach(function(t) {
        projDone += (t.done_tickets || 0);
        projTotal += (t.total_tickets || 0);
      });
      var projPct = projTotal > 0 ? Math.round(projDone / projTotal * 100) : -1;
      var pctColor = projPct === 100 ? 'var(--green,#4BCA81)' : 'var(--muted,#6b7a90)';

      var nameEl = proj.alias && proj.alias !== proj.name
        ? '<span class="proj-name">' + Utils.esc(proj.alias) + '<span class="proj-alias">' + Utils.esc(proj.name) + '</span></span>'
        : '<span class="proj-name">' + Utils.esc(proj.name) + '</span>';

      var badge = teams.length > 0
        ? '<span class="proj-team-badge has-teams">' + teams.length + '</span>'
        : '<span class="proj-team-badge">0</span>';

      var pctEl = projPct >= 0
        ? '<span style="font-size:10px;color:' + pctColor + ';margin-right:4px">' + projPct + '%</span>'
        : '';

      var safeName = Utils.esc(proj.name).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
      return [
        '<div class="proj-item' + (isActive ? ' active' : '') + '"',
        '  onclick="Sidebar.selectProject(\'' + safeName + '\')">',
        icon, nameEl, pctEl, badge,
        '</div>'
      ].join('');
    }

    // 활성 프로젝트
    active.forEach(function(proj) { html.push(renderProjItem(proj)); });

    // 유휴 프로젝트 그룹 (드릴업)
    if (idle.length > 0) {
      var idleOpen = self._idleOpen;
      html.push(
        '<div class="sb-idle-header" onclick="Sidebar.toggleIdle()">',
        '  <span class="sb-idle-chevron">' + (idleOpen ? '▼' : '▶') + '</span>',
        '  유휴 프로젝트',
        '  <span class="sb-badge" style="margin-left:auto">' + idle.length + '</span>',
        '</div>'
      );
      if (idleOpen) {
        idle.forEach(function(proj) { html.push(renderProjItem(proj)); });
      }
    }

    html.push('</div>');
    this._el.innerHTML = html.join('');
  },

  _idleOpen: false,

  toggleIdle() {
    this._idleOpen = !this._idleOpen;
    this._renderProjects();
  },

  _renderTeams() {
    if (!this._el) return;
    var self = this;
    var teams = this._teamsByProject(this._selectedProject || '');
    var projName = this._selectedProject || '';
    var proj = this._projects.find(function(p) { return p.name === projName; });
    var displayName = (proj && proj.alias && proj.alias !== projName) ? proj.alias : projName;

    var html = [
      '<div class="sb-header">',
      '  <button class="sb-back-btn" onclick="Sidebar.backToProjects()">← Projects</button>',
      '  <span class="sb-header-title" title="' + Utils.esc(projName) + '">' + Utils.esc(displayName) + '</span>',
      '  <span class="sb-badge">' + teams.length + '</span>',
      '</div>',
      '<div class="sb-scroll">'
    ];

    if (!teams.length) {
      html.push(
        '<div class="sb-empty">팀이 없습니다<br>',
        '<small>CLI에서 지시를 입력하여<br>팀을 생성하세요</small>',
        '</div>'
      );
    }

    teams.forEach(function(t) {
      var team = t.team || t;
      var teamId = team.team_id || t.team_id;
      var teamName = Utils.esc((team.name || t.name || teamId).replace(/^TEAM-/, ''));
      var tickets = t.total_tickets || team.total_tickets || 0;
      var done = t.done_tickets || team.done_tickets || 0;
      var pct = tickets > 0 ? Math.round(done / tickets * 100) : 0;
      var isActive = self._selectedTeam === teamId;
      var pColor = pct === 100 ? 'var(--green,#4BCA81)' : pct > 0 ? 'var(--brand,#1B96FF)' : 'var(--muted,#6b7a90)';
      var sc = team.status_counts || t.status_counts || {};
      var inProg = sc.InProgress || 0;
      var blocked = sc.Blocked || 0;

      var statusBits = '';
      if (inProg > 0) statusBits += '<span style="color:var(--brand,#1B96FF);margin-right:4px">▶' + inProg + '</span>';
      if (blocked > 0) statusBits += '<span style="color:var(--red,#EA001E);margin-right:4px">⊘' + blocked + '</span>';

      html.push(
        '<div class="team-item' + (isActive ? ' active' : '') + '"',
        '  onclick="Sidebar.selectTeam(\'' + Utils.esc(teamId) + '\')">',
        '  <div class="team-item-name">' + teamName + '</div>',
        '  <div class="team-progress-row">',
        '    <div class="team-pbar">',
        '      <div class="team-pbar-fill" style="width:' + pct + '%;background:' + pColor + '"></div>',
        '    </div>',
        '    <span class="team-pct">' + pct + '%</span>',
        '  </div>',
        '  <div class="team-tickets">' + statusBits + done + '/' + tickets + ' done</div>',
        '</div>'
      );
    });

    html.push('</div>');
    this._el.innerHTML = html.join('');
  },

  selectProject(name) {
    this._selectedProject = name;
    this._selectedTeam = null;
    this._mode = 'teams';
    this._render();
    if (typeof Dashboard !== 'undefined' && Dashboard.selectProject) {
      Dashboard.selectProject(name);
    }
    if (typeof CliPanel !== 'undefined') {
      CliPanel.setProject(name);
    }
  },

  backToProjects() {
    this._mode = 'projects';
    this._selectedProject = null;
    this._selectedTeam = null;
    this._render();
    if (typeof Dashboard !== 'undefined' && Dashboard.showDashboard) {
      Dashboard.showDashboard();
    }
  },

  selectTeam(teamId) {
    this._selectedTeam = teamId;
    this._render();
    if (typeof Dashboard !== 'undefined' && Dashboard.selectTeam) {
      Dashboard.selectTeam(teamId);
    }
    if (typeof CliPanel !== 'undefined') {
      var team = this._teams.find(function(t) {
        return (t.team_id || (t.team && t.team.team_id)) === teamId;
      });
      var name = team ? ((team.team && team.team.name) || team.name || teamId) : teamId;
      CliPanel.log('[시스템] 팀 선택: ' + name, 'system');
    }
  },

  setActiveTeam(teamId) {
    this._selectedTeam = teamId;
    this._render();
  }
};
