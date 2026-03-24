/* U2DIA AI SERVER AGENT — Ticket Detail Modal */
const Modal = {
  _ticketId: null,
  _data: null,
  _activeTab: 0,
  _escHandler: null,

  /** Open modal for a ticket */
  async open(ticketId) {
    this._ticketId = ticketId;
    this._activeTab = 0;

    const overlay = Utils.$('ticketModalOverlay');
    overlay.classList.add('open');
    Utils.$('modalBody').innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">로딩중...</div>';
    Utils.$('modalHeader').innerHTML = '';
    Utils.$('modalTabs').innerHTML = '';
    Utils.$('modalFooter').innerHTML = '';

    const res = await API.ticketDetail(ticketId);
    if (!res.ok) { this.close(); return; }

    this._data = res;
    this._renderHeader(res.ticket, res.assigned_member);
    this._renderTabs(res);
    this._renderTabContent(0);
    this._renderFooter(res.ticket);

    this._escHandler = (e) => { if (e.key === 'Escape') this.close(); };
    document.addEventListener('keydown', this._escHandler);
  },

  /** Close modal */
  close(event) {
    if (event && event.target !== event.currentTarget) return;
    const overlay = Utils.$('ticketModalOverlay');
    if (overlay) overlay.classList.remove('open');
    if (this._escHandler) {
      document.removeEventListener('keydown', this._escHandler);
      this._escHandler = null;
    }
    this._ticketId = null;
    this._data = null;
  },

  /** Switch tab */
  switchTab(idx) {
    this._activeTab = idx;
    document.querySelectorAll('#modalTabs .modal-tab').forEach((t, i) => {
      t.classList.toggle('active', i === idx);
    });
    this._renderTabContent(idx);
  },

  // ── Header ──
  _renderHeader(ticket, member) {
    const el = Utils.$('modalHeader');
    const agentName = member ? (member.display_name || member.role) : (ticket.assigned_member_id || '미배정');
    const initial = Utils.agentInitial(agentName);

    el.innerHTML = `
      <div class="modal-header-info">
        <div class="modal-header-title">${Utils.esc(ticket.title)}</div>
        <div class="modal-header-badges">
          <span class="status-badge status-${ticket.status || 'Todo'}">${Utils.colName(ticket.status) || ticket.status}</span>
          <span class="pri pri-${ticket.priority || 'Medium'}">${ticket.priority || 'Medium'}</span>
          <span class="kb-card-agent">
            <span class="kb-card-avatar">${Utils.esc(initial)}</span>
            ${Utils.esc(agentName)}
          </span>
          <span class="text-xs text-muted">${ticket.ticket_id}</span>
        </div>
      </div>
      <button class="modal-close" onclick="Modal.close()">&times;</button>`;
  },

  // ── Tabs ──
  _renderTabs(data) {
    const el = Utils.$('modalTabs');
    const tabs = [
      { name: '개요', badge: null },
      { name: '작업기록', badge: (data.logs || []).length || null },
      { name: '스레드', badge: null },
      { name: '산출물', badge: data.artifact_count || null },
      { name: '피드백', badge: null }
    ];
    el.innerHTML = tabs.map((t, i) => {
      const badge = t.badge ? `<span class="modal-tab-badge">${t.badge}</span>` : '';
      return `<div class="modal-tab ${i === 0 ? 'active' : ''}" onclick="Modal.switchTab(${i})">${t.name}${badge}</div>`;
    }).join('');
  },

  // ── Tab Content ──
  async _renderTabContent(tabIdx) {
    const body = Utils.$('modalBody');
    if (!body || !this._data) return;
    const ticket = this._data.ticket || {};
    const logs = this._data.logs || [];

    switch (tabIdx) {
      case 0: this._renderOverview(body, ticket, logs); break;
      case 1: this._renderActivity(body, logs); break;
      case 2: await this._renderThread(body, this._ticketId); break;
      case 3: await this._renderArtifacts(body, this._ticketId); break;
      case 4: await this._renderFeedback(body, this._ticketId); break;
    }
  },

  // ── Tab 0: Overview ──
  _renderOverview(body, ticket, logs) {
    const tags = Array.isArray(ticket.tags) ? ticket.tags : (ticket.tags ? [ticket.tags] : []);
    const deps = Array.isArray(ticket.depends_on) ? ticket.depends_on : (ticket.depends_on ? [ticket.depends_on] : []);
    body.innerHTML = `
      <div class="section-title">설명</div>
      <div class="text-sm" style="margin-bottom:16px;white-space:pre-wrap;line-height:1.6">${Utils.esc(ticket.description || '설명 없음')}</div>
      <div class="section-title">정보</div>
      <div class="token-stat"><span class="token-label">ID</span><span class="token-value">${ticket.ticket_id || '-'}</span></div>
      <div class="token-stat"><span class="token-label">상태</span><span class="token-value">${Utils.colName(ticket.status) || '-'}</span></div>
      <div class="token-stat"><span class="token-label">우선순위</span><span class="token-value">${ticket.priority || '-'}</span></div>
      <div class="token-stat"><span class="token-label">담당자</span><span class="token-value">${Utils.esc(ticket.assigned_member_id || '미배정')}</span></div>
      <div class="token-stat"><span class="token-label">팀</span><span class="token-value">${Utils.esc(ticket.team_id || '-')}</span></div>
      <div class="token-stat"><span class="token-label">생성일</span><span class="token-value">${Utils.dateFmt(ticket.created_at)}</span></div>
      <div class="token-stat"><span class="token-label">시작일</span><span class="token-value">${Utils.dateFmt(ticket.started_at)}</span></div>
      <div class="token-stat"><span class="token-label">완료일</span><span class="token-value">${Utils.dateFmt(ticket.completed_at)}</span></div>
      ${ticket.estimated_minutes ? `<div class="token-stat"><span class="token-label">예상 시간</span><span class="token-value">${ticket.estimated_minutes}분</span></div>` : ''}
      ${ticket.actual_minutes ? `<div class="token-stat"><span class="token-label">실제 시간</span><span class="token-value">${ticket.actual_minutes}분</span></div>` : ''}
      ${tags.length ? `<div class="section-title" style="margin-top:16px">태그</div><div class="flex gap-4" style="flex-wrap:wrap">${tags.map(t => `<span class="kb-card-tag" style="font-size:var(--fs-xs);padding:2px 8px">${Utils.esc(t)}</span>`).join('')}</div>` : ''}
      ${deps.length ? `<div class="section-title" style="margin-top:16px">의존성</div><div class="text-sm">${deps.map(d => `<span class="text-xs" style="color:var(--orange);margin-right:6px">${Utils.esc(d)}</span>`).join('')}</div>` : ''}`;
  },

  // ── Tab 1: Activity ──
  _renderActivity(body, logs) {
    if (!logs.length) {
      body.innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">작업기록 없음</div>';
      return;
    }
    body.innerHTML = '<div class="timeline">' + [...logs].reverse().map(l => {
      const cls = l.action === 'status_changed' && (l.message || '').includes('Done') ? 'done'
                : l.action === 'status_changed' && (l.message || '').includes('Blocked') ? 'blocked' : '';
      return `<div class="timeline-node ${cls}">
        <div class="flex justify-between items-center">
          <span class="text-xs" style="color:var(--cyan)">${Utils.esc(l.agent_name || l.member_id || '-')}</span>
          <span class="text-xs text-muted">${Utils.dateFmt(l.created_at)}</span>
        </div>
        <div class="text-sm" style="margin-top:2px"><span style="color:var(--purple)">${Utils.esc(l.action)}</span> ${Utils.esc(l.message || '')}</div>
      </div>`;
    }).join('') + '</div>';
  },

  // ── Tab 2: Messages ──
  // ── Tab 2: Thread (대화+QA+활동+산출물 통합 스레드) ──
  async _renderThread(body, ticketId) {
    body.innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">로딩중...</div>';
    const res = await API.ticketThread(ticketId);
    const thread = res.ok ? (res.thread || []) : [];
    if (!thread.length) {
      body.innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">대화 기록 없음</div>';
      return;
    }
    const kindMeta = {
      conversation: { icon: '💬', color: 'var(--cyan)',   label: '대화' },
      qa:           { icon: '🔍', color: 'var(--green)',  label: 'QA'   },
      activity:     { icon: '📊', color: 'var(--brand)',  label: '진행' },
      artifact:     { icon: '📦', color: 'var(--purple)', label: '산출물' },
    };
    const typeLabel = {
      meeting:   { icon: '🏛', color: 'var(--orange)', label: '회의' },
      rework:    { icon: '🔄', color: 'var(--orange)', label: '재작업' },
      response:  { icon: '↩', color: 'var(--text)',   label: '답변' },
      qa:        { icon: '✅', color: 'var(--green)',  label: 'QA통과' },
      fail:      { icon: '❌', color: 'var(--danger)', label: 'QA실패' },
      question:  { icon: '❓', color: 'var(--cyan)',   label: '질문' },
      progress:  { icon: '▶', color: 'var(--brand)',  label: '진행' },
    };
    body.innerHTML = thread.map(item => {
      const kind = item.kind || 'conversation';
      const meta = kindMeta[kind] || { icon: '▸', color: 'var(--muted)', label: kind };
      const msgType = item.msg_type || '';
      const typeMeta = typeLabel[msgType] || null;
      const speaker = item.speaker || '-';
      const toAgent = item.to_agent && item.to_agent !== '팀' && item.to_agent !== '전체' ? item.to_agent : '';
      const score = item.score != null ? ` ${item.score}/5` : '';

      return `<div class="thread-item" style="
        display:flex;gap:10px;padding:10px 4px;
        border-bottom:1px solid var(--line);
      ">
        <div style="flex-shrink:0;width:32px;height:32px;border-radius:50%;
          background:${meta.color}22;display:flex;align-items:center;justify-content:center;
          font-size:15px;border:1px solid ${meta.color}44">${meta.icon}</div>
        <div style="flex:1;min-width:0">
          <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-bottom:4px">
            <span style="font-size:11px;font-weight:700;color:${meta.color}">${Utils.esc(speaker)}</span>
            ${toAgent ? `<span style="font-size:10px;color:var(--muted)">→ ${Utils.esc(toAgent)}</span>` : ''}
            ${typeMeta ? `<span style="font-size:10px;padding:1px 5px;border-radius:3px;background:${typeMeta.color}22;color:${typeMeta.color}">${typeMeta.icon} ${typeMeta.label}</span>` : ''}
            ${score ? `<span style="font-size:10px;color:var(--green);font-weight:700">${score}</span>` : ''}
            <span style="font-size:10px;color:var(--muted);margin-left:auto">${Utils.timeFmt(item.created_at)}</span>
          </div>
          <div style="font-size:12px;color:var(--text-secondary);white-space:pre-wrap;line-height:1.5;word-break:break-word">${Utils.esc(item.message || '')}</div>
        </div>
      </div>`;
    }).join('');
  },

  async _renderMessages(body, ticketId) {
    body.innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">로딩중...</div>';
    const res = await API.messages(ticketId);
    const msgs = res.ok ? (res.messages || []) : [];

    if (!msgs.length) {
      body.innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">대화 없음</div>';
      return;
    }
    body.innerHTML = msgs.map(m => {
      const initial = Utils.agentInitial(m.sender_name || m.sender_id || '?');
      return `<div style="padding:10px;margin-bottom:8px;background:var(--panel);border-radius:var(--radius-md);border:1px solid var(--line)">
        <div class="flex justify-between items-center mb-8">
          <div class="flex gap-8 items-center">
            <span class="kb-card-avatar">${Utils.esc(initial)}</span>
            <span class="text-sm fw-bold" style="color:var(--cyan)">${Utils.esc(m.sender_name || m.sender_id || '-')}</span>
            ${m.message_type && m.message_type !== 'comment' ? `<span class="text-xs text-muted">[${Utils.esc(m.message_type)}]</span>` : ''}
          </div>
          <span class="text-xs text-muted">${Utils.dateFmt(m.created_at)}</span>
        </div>
        <div class="text-sm" style="white-space:pre-wrap;line-height:1.5">${Utils.esc(m.content || m.body || '')}</div>
      </div>`;
    }).join('');
  },

  // ── Tab 3: Artifacts ──
  async _renderArtifacts(body, ticketId) {
    body.innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">로딩중...</div>';
    const res = await API.artifacts(ticketId);
    const arts = res.ok ? (res.artifacts || []) : [];

    if (!arts.length) {
      body.innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">산출물 없음</div>';
      return;
    }
    body.innerHTML = arts.map(a => `
      <div style="padding:10px;margin-bottom:8px;background:var(--panel);border-radius:var(--radius-md);border:1px solid var(--line)">
        <div class="flex justify-between items-center">
          <span class="text-sm fw-bold">${Utils.esc(a.title || a.artifact_type || '산출물')}</span>
          <span class="text-xs text-muted">${Utils.dateFmt(a.created_at)}</span>
        </div>
        <div class="text-xs text-muted" style="margin-top:2px">${Utils.esc(a.artifact_type || '-')}${a.language ? ' / ' + Utils.esc(a.language) : ''}${a.file_path ? ' | ' + Utils.esc(a.file_path) : ''}</div>
        ${a.content ? `<pre style="font-size:10px;margin-top:6px;padding:8px;background:var(--bg);border:1px solid var(--line);border-radius:var(--radius-sm);overflow-x:auto;max-height:250px;font-family:var(--mono);color:var(--text-secondary)">${Utils.esc(a.content)}</pre>` : ''}
        ${a.summary ? `<div class="text-sm mt-8">${Utils.esc(a.summary)}</div>` : ''}
      </div>
    `).join('');
  },

  // ── Tab 4: Feedback ──
  async _renderFeedback(body, ticketId) {
    body.innerHTML = '<div class="text-muted text-sm p-16" style="text-align:center">로딩중...</div>';
    const res = await API.feedbackList(ticketId);
    const fbs = res.ok ? (res.feedbacks || res.feedback || []) : [];

    let html = '';
    if (fbs.length) {
      fbs.forEach(f => {
        const stars = '\u2605'.repeat(f.score || 0) + '\u2606'.repeat(5 - (f.score || 0));
        html += `<div style="padding:10px;margin-bottom:8px;background:var(--panel);border-radius:var(--radius-md);border:1px solid var(--line)">
          <div class="flex justify-between items-center">
            <span style="color:var(--yellow);font-size:16px;letter-spacing:2px">${stars}</span>
            <span class="text-xs text-muted">${Utils.dateFmt(f.created_at)}</span>
          </div>
          <div class="flex gap-4 items-center mt-8">
            <span class="text-xs text-muted">${Utils.esc(f.author || 'user')}</span>
            ${f.categories ? `<span class="text-xs" style="color:var(--cyan)">[${Utils.esc(Array.isArray(f.categories) ? f.categories.join(', ') : f.categories)}]</span>` : ''}
          </div>
          ${f.comment ? `<div class="text-sm" style="margin-top:6px;white-space:pre-wrap">${Utils.esc(f.comment)}</div>` : ''}
        </div>`;
      });
    } else {
      html = '<div class="text-muted text-sm" style="padding:16px;text-align:center">피드백 없음</div>';
    }

    // Feedback form
    html += `
      <div class="section-title" style="margin-top:20px">피드백 남기기</div>
      <div class="stars" id="fbStars">${[1,2,3,4,5].map(i => `<span class="star" data-val="${i}" onclick="Modal._setScore(${i})">\u2606</span>`).join('')}</div>
      <textarea id="fbComment" placeholder="코멘트 (선택)" style="width:100%;margin-top:8px;padding:8px;background:var(--panel);border:1px solid var(--line);border-radius:var(--radius-sm);color:var(--text);font-size:var(--fs-sm);resize:vertical;min-height:60px;font-family:var(--font)"></textarea>
      <button class="btn btn-primary btn-sm" style="margin-top:8px" onclick="Modal._submitFeedback('${ticketId}')">제출</button>`;
    body.innerHTML = html;
  },

  // ── Feedback helpers ──
  _fbScore: 0,
  _setScore(val) {
    this._fbScore = val;
    document.querySelectorAll('#fbStars .star').forEach((s, i) => {
      s.textContent = i < val ? '\u2605' : '\u2606';
      s.classList.toggle('active', i < val);
    });
  },

  async _submitFeedback(ticketId) {
    if (!this._fbScore) { alert('점수를 선택해주세요'); return; }
    const comment = Utils.$('fbComment')?.value || '';
    const res = await API.feedbackCreate(ticketId, {
      score: this._fbScore,
      comment: comment,
      author: 'user'
    });
    if (res.ok) {
      this._fbScore = 0;
      this._renderFeedback(Utils.$('modalBody'), ticketId);
    }
  },

  // ── Footer (status actions) ──
  _renderFooter(ticket) {
    const footer = Utils.$('modalFooter');
    if (!footer) return;
    const status = ticket?.status || 'Todo';
    const ticketId = ticket?.ticket_id;
    const actions = [];

    if (status !== 'InProgress' && status !== 'Done')
      actions.push(`<button class="btn btn-sm btn-primary" onclick="Modal._changeStatus('${ticketId}','InProgress')">시작</button>`);
    if (status === 'InProgress')
      actions.push(`<button class="btn btn-sm" onclick="Modal._changeStatus('${ticketId}','Review')">리뷰 요청</button>`);
    if (status === 'Review')
      actions.push(`<button class="btn btn-sm btn-primary" onclick="Modal._changeStatus('${ticketId}','Done')">완료</button>`);
    if (status !== 'Blocked' && status !== 'Done')
      actions.push(`<button class="btn btn-sm btn-danger" onclick="Modal._changeStatus('${ticketId}','Blocked')">차단</button>`);
    if (status === 'Done' || status === 'Blocked')
      actions.push(`<button class="btn btn-sm" onclick="Modal._changeStatus('${ticketId}','Todo')">재작업</button>`);

    footer.innerHTML = actions.join('');
  },

  async _changeStatus(ticketId, status) {
    const res = await API.ticketStatus(ticketId, status);
    if (res.ok) {
      // Refresh modal data
      const detail = await API.ticketDetail(ticketId);
      if (detail.ok) {
        this._data = detail;
        this._renderHeader(detail.ticket, detail.assigned_member);
        this._renderTabs(detail);
        this._renderTabContent(this._activeTab);
        this._renderFooter(detail.ticket);
      }
      // Trigger kanban refresh if Kanban is active
      if (typeof Kanban !== 'undefined' && Kanban._teamId) {
        Kanban._refreshBoard();
      }
    }
  }
};
