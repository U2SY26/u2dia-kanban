/* U2DIA AI SERVER AGENT — CLI Panel v1.0 (하단 상주 CLI) */
const CliPanel = {
  _el: null,
  _logEl: null,
  _inputEl: null,
  _projectEl: null,
  _resizerEl: null,
  _selectedProject: null,
  _ralphCount: 0,
  _ralphMax: 3,
  _isRunning: false,

  init() {
    this._el = document.getElementById('wsCli');
    this._resizerEl = document.getElementById('wsCliResizer');
    if (!this._el) return;
    this._build();
    this._setupResizer();
    this._connectSSE();
    this.log('[시스템] CLI 패널 준비됨 — 지시를 입력하여 팀/티켓/에이전트를 자동화하세요', 'system');
  },

  _build() {
    this._el.innerHTML = [
      '<div class="cli-header">',
      '  <span class="cli-title">CLI — 지시 센터</span>',
      '  <span class="cli-status-dot" id="cliStatusDot"></span>',
      '  <span class="cli-ralph-badge ok" id="cliRalphBadge">Ralph 0/' + this._ralphMax + '</span>',
      '  <button class="btn btn-xs" onclick="CliPanel.toggleTeamList()" style="margin-left:8px;font-size:10px" id="cliTeamListBtn">📋 팀</button>',
      '  <button class="btn btn-xs" onclick="CliPanel.clear()" style="font-size:10px">Clear</button>',
      '  <button class="btn btn-xs" onclick="CliPanel.toggleCollapse()" id="cliCollapseBtn" style="font-size:10px">▼</button>',
      '</div>',
      '<div class="cli-team-list" id="cliTeamList" style="display:none"></div>',
      '<div class="cli-log-area" id="cliLogArea"></div>',
      '<div class="cli-input-row">',
      '  <select class="cli-project-select" id="cliProjectSelect"',
      '    onchange="CliPanel.onProjectChange(this.value)">',
      '    <option value="">-- 프로젝트 선택 --</option>',
      '  </select>',
      '  <input class="cli-input" id="cliInput"',
      '    placeholder="팀 생성, 티켓 발행, 에이전트 지시... (Enter로 전송)"',
      '    onkeydown="if(event.key===\'Enter\'&&!event.shiftKey){CliPanel.send();event.preventDefault()}" />',
      '  <button class="cli-send-btn" id="cliSendBtn" onclick="CliPanel.send()">전송</button>',
      '</div>'
    ].join('');
    this._logEl = document.getElementById('cliLogArea');
    this._inputEl = document.getElementById('cliInput');
    this._projectEl = document.getElementById('cliProjectSelect');
    this._teamListEl = document.getElementById('cliTeamList');
    this._loadProjects();
  },

  async _loadProjects() {
    try {
      var res = await API.get('/api/github/projects');
      if (!res.ok || !this._projectEl) return;
      var html = '<option value="">-- 프로젝트 선택 --</option>';
      (res.projects || []).forEach(function(p) {
        var label = (p.alias && p.alias !== p.name) ? p.alias : p.name;
        html += '<option value="' + Utils.esc(p.name) + '">' + Utils.esc(label) + '</option>';
      });
      this._projectEl.innerHTML = html;
      if (this._selectedProject) this._projectEl.value = this._selectedProject;
    } catch(e) {}
  },

  _setupResizer() {
    if (!this._resizerEl || !this._el) return;
    var self = this;
    var startY, startH;
    this._resizerEl.addEventListener('mousedown', function(e) {
      startY = e.clientY;
      startH = self._el.offsetHeight;
      self._resizerEl.classList.add('dragging');
      document.body.style.userSelect = 'none';
      function onMove(ev) {
        var delta = startY - ev.clientY;
        var newH = Math.min(520, Math.max(80, startH + delta));
        self._el.style.height = newH + 'px';
      }
      function onUp() {
        self._resizerEl.classList.remove('dragging');
        document.body.style.userSelect = '';
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
      }
      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    });
  },

  _connectSSE() {
    var self = this;
    if (typeof SSE === 'undefined') return;
    SSE.connectGlobal(function(data) {
      var et = data.event_type || data.type || '';
      var important = ['ticket_claimed','ticket_status_changed','member_spawned',
                       'team_created','team_archived','team_auto_archived',
                       'ticket_created','artifact_created'];
      if (important.indexOf(et) < 0) return;
      var msg = '[SSE] ' + et;
      if (data.team_name) msg += ' • ' + data.team_name;
      if (data.data) {
        if (data.data.title) msg += ': ' + data.data.title;
        else if (data.data.status) msg += ' → ' + data.data.status;
        else if (data.data.member_name) msg += ' (' + data.data.member_name + ')';
      }
      self.log(msg, 'sse');
      // Ralph Loop 성공 시 카운터 리셋
      if (et === 'ticket_status_changed' && data.data && data.data.status === 'Done') {
        if (self._ralphCount > 0) { self._ralphCount = 0; self._updateRalph(); }
      }
    });
  },

  setProject(name) {
    this._selectedProject = name;
    if (this._projectEl) this._projectEl.value = name || '';
  },

  onProjectChange(name) {
    this._selectedProject = name;
    if (name && typeof Sidebar !== 'undefined' && Sidebar._mode !== 'teams') {
      // 사이드바와 동기화는 사이드바가 선택할 때 처리
    }
  },

  log(msg, type) {
    if (!this._logEl) return;
    type = type || 'system';
    var now = new Date();
    var ts = ('0'+now.getHours()).slice(-2)+':'+('0'+now.getMinutes()).slice(-2)+':'+('0'+now.getSeconds()).slice(-2);
    var line = document.createElement('div');
    line.className = 'log-line log-' + type;
    var tsEl = document.createElement('span');
    tsEl.className = 'log-ts';
    tsEl.textContent = ts;
    var msgEl = document.createElement('span');
    msgEl.className = 'log-msg';
    msgEl.textContent = msg;
    line.appendChild(tsEl);
    line.appendChild(msgEl);
    this._logEl.appendChild(line);
    this._logEl.scrollTop = this._logEl.scrollHeight;
    while (this._logEl.children.length > 500) this._logEl.removeChild(this._logEl.firstChild);
  },

  clear() {
    if (this._logEl) this._logEl.innerHTML = '';
    this._ralphCount = 0;
    this._updateRalph();
  },

  toggleCollapse() {
    if (!this._el || !this._logEl) return;
    var btn = document.getElementById('cliCollapseBtn');
    var collapsed = this._el.style.height === '36px';
    if (collapsed) {
      this._el.style.height = '';
      if (btn) btn.textContent = '▼';
    } else {
      this._el.style.height = '36px';
      if (btn) btn.textContent = '▲';
    }
  },

  _setRunning(v) {
    this._isRunning = v;
    var dot = document.getElementById('cliStatusDot');
    var btn = document.getElementById('cliSendBtn');
    if (dot) dot.className = 'cli-status-dot' + (v ? ' running' : '');
    if (btn) btn.disabled = v;
  },

  _updateRalph() {
    var badge = document.getElementById('cliRalphBadge');
    if (!badge) return;
    badge.textContent = 'Ralph ' + this._ralphCount + '/' + this._ralphMax;
    badge.className = 'cli-ralph-badge' +
      (this._ralphCount >= this._ralphMax ? ' block' : this._ralphCount > 0 ? ' warn' : ' ok');
  },

  _teamListVisible: false,

  toggleTeamList() {
    this._teamListVisible = !this._teamListVisible;
    var el = document.getElementById('cliTeamList');
    if (!el) return;
    el.style.display = this._teamListVisible ? 'block' : 'none';
    if (this._teamListVisible) this._renderTeamList();
  },

  async _renderTeamList() {
    var el = document.getElementById('cliTeamList');
    if (!el) return;
    el.innerHTML = '<div style="padding:8px;color:var(--muted);font-size:11px">로딩...</div>';
    try {
      var [projRes, ovRes] = await Promise.all([
        API.get('/api/github/projects'),
        API.overview()
      ]);
      var projects = (projRes.ok && projRes.projects) ? projRes.projects : [];
      var teams = (ovRes.ok && ovRes.teams) ? ovRes.teams : [];
      if (!projects.length && !teams.length) {
        el.innerHTML = '<div style="padding:8px;color:var(--muted);font-size:11px">프로젝트/팀 없음</div>';
        return;
      }

      var html = '';
      // 프로젝트별 그룹핑
      var grouped = {};
      var ungrouped = [];
      teams.forEach(function(t) {
        var team = t.team || t;
        var pg = (team.project_group || t.project_group || '').toLowerCase();
        if (!pg) { ungrouped.push(t); return; }
        if (!grouped[pg]) grouped[pg] = [];
        grouped[pg].push(t);
      });

      projects.forEach(function(proj) {
        var nameLow = proj.name.toLowerCase();
        var alias = (proj.alias && proj.alias !== proj.name) ? proj.alias : '';
        var label = alias || proj.name;
        // 이 프로젝트에 속하는 팀 찾기
        var matchTeams = [];
        Object.keys(grouped).forEach(function(pg) {
          if (pg === nameLow || (alias && pg === alias.toLowerCase()) || pg.indexOf(nameLow) >= 0 || nameLow.indexOf(pg) >= 0) {
            matchTeams = matchTeams.concat(grouped[pg]);
            delete grouped[pg]; // 매칭된 것은 제거
          }
        });
        if (!matchTeams.length) return;

        html += '<div class="cli-tl-group">';
        html += '<div class="cli-tl-proj">' + Utils.esc(label) + ' <span style="color:var(--muted)">(' + matchTeams.length + ')</span></div>';
        matchTeams.forEach(function(t) {
          var team = t.team || t;
          var tid = team.team_id || t.team_id;
          var name = (team.name || t.name || tid).replace(/^TEAM-/, '');
          var done = t.done_tickets || 0;
          var total = t.total_tickets || 0;
          var pct = total > 0 ? Math.round(done / total * 100) : 0;
          var pColor = pct === 100 ? 'var(--green)' : pct > 0 ? 'var(--brand)' : 'var(--muted)';
          html += '<div class="cli-tl-team" onclick="CliPanel.selectTeamFromList(\'' + Utils.esc(tid) + '\')">'
            + '<span class="cli-tl-name">' + Utils.esc(name) + '</span>'
            + '<span class="cli-tl-pct" style="color:' + pColor + '">' + pct + '%</span>'
            + '<span class="cli-tl-stat">' + done + '/' + total + '</span>'
            + '</div>';
        });
        html += '</div>';
      });

      // 나머지 미그룹 팀 + 남은 grouped
      var rest = ungrouped;
      Object.keys(grouped).forEach(function(pg) { rest = rest.concat(grouped[pg]); });
      if (rest.length) {
        html += '<div class="cli-tl-group">';
        html += '<div class="cli-tl-proj">기타 <span style="color:var(--muted)">(' + rest.length + ')</span></div>';
        rest.forEach(function(t) {
          var team = t.team || t;
          var tid = team.team_id || t.team_id;
          var name = (team.name || t.name || tid).replace(/^TEAM-/, '');
          html += '<div class="cli-tl-team" onclick="CliPanel.selectTeamFromList(\'' + Utils.esc(tid) + '\')">'
            + '<span class="cli-tl-name">' + Utils.esc(name) + '</span>'
            + '</div>';
        });
        html += '</div>';
      }

      el.innerHTML = html || '<div style="padding:8px;color:var(--muted);font-size:11px">팀 없음</div>';
    } catch(e) {
      el.innerHTML = '<div style="padding:8px;color:var(--red);font-size:11px">로드 실패</div>';
    }
  },

  selectTeamFromList(teamId) {
    this._teamListVisible = false;
    var el = document.getElementById('cliTeamList');
    if (el) el.style.display = 'none';
    // 사이드바와 대시보드에 팀 선택 전파
    if (typeof Sidebar !== 'undefined') Sidebar.selectTeam(teamId);
    else if (typeof Dashboard !== 'undefined') Dashboard.selectTeam(teamId);
    this.log('[시스템] 팀 선택: ' + teamId, 'system');
  },

  async send() {
    var instruction = this._inputEl ? this._inputEl.value.trim() : '';
    if (!instruction || this._isRunning) return;
    var project = this._selectedProject || (this._projectEl ? this._projectEl.value : '');
    this.log('> ' + (project ? '[' + project + '] ' : '') + instruction, 'user');
    if (this._inputEl) this._inputEl.value = '';
    this._setRunning(true);
    try {
      var body = { instruction: instruction };
      if (project) body.project_name = project;
      var res = await API.post('/api/orchestrate', body);
      if (res.ok !== false) {
        this.log('[완료] ' + (res.message || '지시가 전달되었습니다'), 'success');
        if (res.team_id || res.team_name) {
          this.log('[팀] ' + (res.team_name || res.team_id) + ' 생성/할당됨', 'system');
          if (typeof Sidebar !== 'undefined') setTimeout(function() { Sidebar.refresh(); }, 1000);
        }
        if (res.tickets && res.tickets.length) {
          this.log('[티켓] ' + res.tickets.length + '개 생성됨', 'system');
        }
        // 성공 시 Ralph 카운터 리셋
        if (this._ralphCount > 0) { this._ralphCount = 0; this._updateRalph(); }
      } else {
        this.log('[오류] ' + (res.error || res.message || '알 수 없는 오류'), 'error');
        this._ralphCount = Math.min(this._ralphMax, this._ralphCount + 1);
        this._updateRalph();
        if (this._ralphCount >= this._ralphMax) {
          this.log('[Ralph ⊘] 최대 재시도(' + this._ralphMax + '회) 도달. 지시를 구체적으로 재입력하세요.', 'ralph');
        }
      }
    } catch(e) {
      this.log('[오류] 네트워크: ' + e.message, 'error');
      this._ralphCount = Math.min(this._ralphMax, this._ralphCount + 1);
      this._updateRalph();
    } finally {
      this._setRunning(false);
    }
  }
};
