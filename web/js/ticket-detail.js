/* Ticket Detail Modal — Tabbed (히스토리/대화/산출물/피드백) */
/* Dashboard.showTicketDetail 에서 호출 */

(function() {
  var _typeIcons = {conversation:'\ud83d\udcac',review:'\ud83d\udccb',artifact:'\ud83d\udce6',artifact_detail:'\ud83d\udcc4',activity:'\u26a1',feedback:'\u2b50'};

  function _makeRow(h) {
    var row = document.createElement('div');
    row.className = 'td-row';

    var left = document.createElement('div');
    left.className = 'td-row-left';
    var iconEl = document.createElement('span');
    iconEl.className = 'td-icon';
    iconEl.textContent = _typeIcons[h.type] || '\u2139\ufe0f';
    left.appendChild(iconEl);
    var timeEl = document.createElement('span');
    timeEl.className = 'td-time';
    timeEl.textContent = (h.created_at || '').substring(11, 16);
    left.appendChild(timeEl);
    row.appendChild(left);

    var right = document.createElement('div');
    right.className = 'td-row-right';

    if (h.actor || h.sub_type) {
      var actor = document.createElement('div');
      actor.className = 'td-actor';
      actor.textContent = (h.actor || '') + (h.sub_type ? ' [' + h.sub_type + ']' : '');
      right.appendChild(actor);
    }
    if (h.score) {
      var scoreEl = document.createElement('span');
      scoreEl.className = 'td-score';
      scoreEl.textContent = '\u2b50'.repeat(Math.min(h.score, 5)) + ' ' + h.score + '/5';
      right.appendChild(scoreEl);
    }
    if (h.detail) {
      var content = document.createElement('div');
      content.className = 'td-content';
      content.textContent = h.detail;
      right.appendChild(content);
    }
    if (h.file_path) {
      var fileRow = document.createElement('div');
      fileRow.className = 'td-file';
      var fName = document.createElement('span');
      fName.className = 'td-filename';
      fName.textContent = h.file_path;
      fileRow.appendChild(fName);
      if (h.lines_added || h.lines_removed) {
        var chg = document.createElement('span');
        chg.className = 'td-changes';
        var p = [];
        if (h.lines_added) p.push('+' + h.lines_added);
        if (h.lines_removed) p.push('-' + h.lines_removed);
        chg.textContent = p.join(' / ');
        fileRow.appendChild(chg);
      }
      right.appendChild(fileRow);
    }
    if (h.issues) {
      var iss = document.createElement('div');
      iss.className = 'td-issues';
      iss.textContent = '\u26a0\ufe0f ' + h.issues;
      right.appendChild(iss);
    }
    row.appendChild(right);
    return row;
  }

  window.TicketDetail = {
    async show(ticketId) {
      var res = await API.get('/api/tickets/' + ticketId + '/history');
      var ticket = await API.get('/api/tickets/' + ticketId);
      var tk = ticket.ticket || ticket;
      var items = (res.ok ? res.history : []) || [];

      var existing = document.getElementById('ticketDetailModal');
      if (existing) existing.remove();

      var modal = document.createElement('div');
      modal.className = 'modal-overlay';
      modal.id = 'ticketDetailModal';
      modal.style.display = 'flex';
      modal.addEventListener('click', function(e) { if (e.target === modal) modal.remove(); });

      var box = document.createElement('div');
      box.className = 'modal-box ticket-detail-modal';

      /* Header */
      var hdr = document.createElement('div');
      hdr.className = 'td-header';
      var hdrLeft = document.createElement('div');
      hdrLeft.className = 'td-header-left';
      var h3 = document.createElement('h3');
      h3.textContent = tk.title || ticketId;
      hdrLeft.appendChild(h3);
      var statusBadge = document.createElement('span');
      statusBadge.className = 'badge';
      statusBadge.style.background = Utils.statusColor(tk.status || 'Backlog');
      statusBadge.textContent = tk.status || '?';
      hdrLeft.appendChild(statusBadge);
      if (tk.retry_count) {
        var retryBadge = document.createElement('span');
        retryBadge.className = 'badge';
        retryBadge.style.background = 'var(--chart-red, #ef4444)';
        retryBadge.textContent = 'R' + tk.retry_count + '/3';
        hdrLeft.appendChild(retryBadge);
      }
      hdr.appendChild(hdrLeft);
      var closeBtn = document.createElement('button');
      closeBtn.className = 'btn btn-sm';
      closeBtn.textContent = '\u2715';
      closeBtn.addEventListener('click', function() { modal.remove(); });
      hdr.appendChild(closeBtn);
      box.appendChild(hdr);

      /* Info bar */
      var info = document.createElement('div');
      info.className = 'td-info';
      info.textContent = [
        tk.priority || '',
        tk.assigned_member_id ? 'Agent: ' + (tk.assigned_member_id || '').substring(0, 10) : '',
        tk.started_at ? 'Start: ' + (tk.started_at || '').substring(0, 16) : '',
        tk.completed_at ? 'End: ' + (tk.completed_at || '').substring(0, 16) : ''
      ].filter(Boolean).join(' \u00b7 ');
      box.appendChild(info);

      if (tk.description) {
        var desc = document.createElement('div');
        desc.className = 'td-desc';
        desc.textContent = tk.description;
        box.appendChild(desc);
      }

      /* Tab definitions */
      var tabDefs = [
        { id: 'history', label: '\u26a1 \ud788\uc2a4\ud1a0\ub9ac', filter: function(h) { return h.type === 'activity' || h.type === 'review'; } },
        { id: 'conv', label: '\ud83d\udcac \ub300\ud654', filter: function(h) { return h.type === 'conversation'; } },
        { id: 'artifacts', label: '\ud83d\udce6 \uc0b0\ucd9c\ubb3c', filter: function(h) { return h.type === 'artifact' || h.type === 'artifact_detail'; } },
        { id: 'feedback', label: '\u2b50 \ud53c\ub4dc\ubc31', filter: function(h) { return h.type === 'feedback'; } }
      ];

      var tabBar = document.createElement('div');
      tabBar.className = 'td-tabs';
      var tabPanels = document.createElement('div');
      tabPanels.className = 'td-panels';

      tabDefs.forEach(function(tab, i) {
        var filtered = items.filter(tab.filter);
        if (tab.id === 'history' && filtered.length === 0) filtered = items;

        var btn = document.createElement('button');
        btn.className = 'td-tab' + (i === 0 ? ' td-tab-active' : '');
        btn.textContent = tab.label + ' (' + filtered.length + ')';
        btn.addEventListener('click', function() {
          tabBar.querySelectorAll('.td-tab').forEach(function(b) { b.classList.remove('td-tab-active'); });
          btn.classList.add('td-tab-active');
          tabPanels.querySelectorAll('.td-panel').forEach(function(p) { p.style.display = 'none'; });
          tabPanels.querySelector('[data-tab="' + tab.id + '"]').style.display = 'block';
        });
        tabBar.appendChild(btn);

        var panel = document.createElement('div');
        panel.className = 'td-panel';
        panel.setAttribute('data-tab', tab.id);
        panel.style.display = i === 0 ? 'block' : 'none';

        if (!filtered.length) {
          var empty = document.createElement('div');
          empty.className = 'terminal-placeholder';
          empty.textContent = '\ub370\uc774\ud130 \uc5c6\uc74c';
          panel.appendChild(empty);
        }

        filtered.forEach(function(h) {
          panel.appendChild(_makeRow(h));
        });

        tabPanels.appendChild(panel);
      });

      box.appendChild(tabBar);
      box.appendChild(tabPanels);
      modal.appendChild(box);
      document.body.appendChild(modal);
    }
  };
})();
