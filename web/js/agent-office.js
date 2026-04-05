/* U2DIA Agent Office — Pixel Sprite Canvas Simulation */
const AgentOffice = {
  _canvas: null, _ctx: null, _teamId: null, _agents: [], _desks: [],
  _particles: [], _frame: 0, _running: false, _sprites: {}, _loaded: false,
  _boardData: null, T: 32, S: 2,

  async loadSprites() {
    if (this._loaded) return;
    var urls = {
      body: '/sprites/CharacterModel/character.png',
      hairs: '/sprites/Hair/Hairs.png',
      shadow: '/sprites/CharacterModel/Shadow.png',
      outfit1: '/sprites/Outfits/Outfit1.png',
      outfit2: '/sprites/Outfits/Outfit2.png',
      outfit3: '/sprites/Outfits/Outfit3.png',
      outfit4: '/sprites/Outfits/Outfit4.png',
      outfit5: '/sprites/Outfits/Outfit5.png',
      outfit6: '/sprites/Outfits/Outfit6.png',
      tv: '/sprites/Furniture/TV-Sheet.png',
      desk: '/sprites/Furniture/LivingRoom-Sheet.png',
    };
    var self = this;
    var promises = Object.keys(urls).map(function(key) {
      return new Promise(function(res) {
        var img = new Image();
        img.onload = function() { self._sprites[key] = img; res(); };
        img.onerror = function() { console.warn('sprite load fail:', key); res(); };
        img.src = urls[key];
      });
    });
    await Promise.all(promises);
    this._loaded = true;
  },

  async open(teamId) {
    this._teamId = teamId;
    await this.loadSprites();
    var boardRes = await API.teamBoard(teamId);
    if (!boardRes.ok) return;
    this._boardData = boardRes.board;

    var overlay = document.createElement('div');
    overlay.id = 'agentOfficeOverlay';
    overlay.style.cssText = 'position:fixed;inset:0;z-index:2000;background:rgba(0,0,0,0.8);display:flex;align-items:center;justify-content:center';
    overlay.onclick = function(e) { if (e.target === overlay) AgentOffice.close(); };

    var box = document.createElement('div');
    box.style.cssText = 'background:#1c2333;border:2px solid #3d4663;border-radius:12px;overflow:hidden;width:92vw;max-width:960px';

    var team = this._boardData.team || {};
    var tickets = this._boardData.tickets || [];
    var done = tickets.filter(function(t){return t.status==='Done'}).length;
    var hdr = document.createElement('div');
    hdr.style.cssText = 'display:flex;justify-content:space-between;align-items:center;padding:10px 16px;background:#252d41;border-bottom:1px solid #3d4663';
    hdr.innerHTML = '<div style="display:flex;align-items:center;gap:8px"><span style="font-size:20px">🏢</span><span style="color:#e6edf3;font-size:14px;font-weight:700">' + Utils.esc(team.name || '') + '</span><span style="color:#8b949e;font-size:11px">' + done + '/' + tickets.length + ' done</span></div><button onclick="AgentOffice.close()" style="background:none;border:none;color:#8b949e;font-size:20px;cursor:pointer;padding:4px 8px">✕</button>';

    this._canvas = document.createElement('canvas');
    this._canvas.width = 928;
    this._canvas.height = 520;
    this._canvas.style.cssText = 'width:100%;display:block;image-rendering:pixelated';
    this._ctx = this._canvas.getContext('2d');
    this._ctx.imageSmoothingEnabled = false;

    box.appendChild(hdr);
    box.appendChild(this._canvas);
    overlay.appendChild(box);
    document.body.appendChild(overlay);
    this._initOffice();
    this._running = true;
    this._frame = 0;
    this._animate();
  },

  close() { this._running = false; var o = document.getElementById('agentOfficeOverlay'); if (o) o.remove(); },

  _initOffice() {
    var board = this._boardData;
    var members = board.members || [];
    var tickets = board.tickets || [];
    var W = this._canvas.width / this.S;
    var H = this._canvas.height / this.S;
    var workingTickets = tickets.filter(function(t){return t.status==='InProgress'||t.status==='Review'});
    var isIdle = workingTickets.length === 0;

    // 데스크: 에이전트 수만큼 (최대 20개, 4열 배치)
    this._desks = [];
    var n = Math.max(members.length, 2);
    var cols = Math.min(Math.ceil(Math.sqrt(n * 1.5)), 5);
    for (var i = 0; i < n; i++) {
      var row = Math.floor(i / cols);
      var col = i % cols;
      var spacing = Math.min(105, (W - 40) / cols);
      this._desks.push({ x: 30 + col * spacing, y: 50 + row * 80, screenOn: false });
    }

    // 에이전트: 멤버 전원 + 티켓 1:1 매칭
    this._agents = [];
    var idleChats = ['☕ 커피타임~', '🎮 잠깐 쉬자', '📱 SNS', '💤 zzz...', '🍕 배고프다', '😎 여유~', '🎵 ♪♪', '🧋 버블티!', '🤔 생각중', '✨ 평화~'];
    var effectiveMembers = members.length > 0 ? members : [{display_name:'agent-1',member_id:'p1'},{display_name:'agent-2',member_id:'p2'}];

    for (var j = 0; j < effectiveMembers.length; j++) {
      var m = effectiveMembers[j];
      // 이 에이전트에 할당된 티켓 찾기
      var assignedTicket = null;
      for (var k = 0; k < tickets.length; k++) {
        if (tickets[k].assigned_member_id === m.member_id && (tickets[k].status === 'InProgress' || tickets[k].status === 'Review')) {
          assignedTicket = tickets[k];
          break;
        }
      }
      var seed = 0;
      for (var c = 0; c < (m.member_id||'x').length; c++) seed += (m.member_id||'x').charCodeAt(c);

      var deskIdx = j % this._desks.length;
      var desk = this._desks[deskIdx];
      var isWorking = assignedTicket !== null;
      desk.screenOn = isWorking;

      var chatMsg = '';
      if (isWorking) {
        chatMsg = '💻 ' + (assignedTicket.title||'').substring(0, 16);
      } else if (isIdle) {
        chatMsg = idleChats[j % idleChats.length];
      }

      var a = {
        name: (m.display_name || m.role || 'agent').substring(0, 14),
        x: desk.x + 12, y: desk.y + 32,
        targetX: desk.x + 12, targetY: desk.y + 32,
        vx: 0, vy: 0,
        skinRow: seed % 6, hairRow: seed % 8, outfitIdx: (seed % 6) + 1,
        animFrame: Math.floor(Math.random() * 4), direction: 0,
        state: isWorking ? 'working' : 'idle',
        ticket: assignedTicket,
        ticketStatus: assignedTicket ? assignedTicket.status : null,
        deskIdx: deskIdx,
        stateTimer: 80 + Math.floor(Math.random() * 200),
        chatMsg: chatMsg,
        chatTimer: 80 + Math.floor(Math.random() * 150),
      };
      this._agents.push(a);
    }
    this._particles = [];
  },

  _animate() {
    if (!this._running) return;
    this._update();
    this._draw();
    this._frame++;
    requestAnimationFrame(function() { AgentOffice._animate(); });
  },

  _update() {
    var W = this._canvas.width / this.S, H = this._canvas.height / this.S;
    for (var i = 0; i < this._agents.length; i++) {
      var a = this._agents[i];
      a.stateTimer--;
      if (this._frame % 8 === 0) a.animFrame = (a.animFrame + 1) % 4;
      if (a.stateTimer <= 0) {
        if (a.state === 'working') {
          if (Math.random() < 0.12) {
            a.state = 'walking'; a.targetX = 20 + Math.random() * 60; a.targetY = H - 50 + Math.random() * 20;
            a.chatMsg = '☕'; a.chatTimer = 100; a.stateTimer = 100;
          } else {
            a.stateTimer = 80 + Math.floor(Math.random() * 200);
            this._particles.push({x:a.x+10,y:a.y-10,life:35,text:['{}','()','fn','if','=>','++','</>','SQL','API','GET'][Math.floor(Math.random()*10)]});
          }
        } else if (a.state === 'idle') {
          if (Math.random() < 0.25) {
            a.state = 'walking'; a.targetX = 30+Math.random()*(W-60); a.targetY = 30+Math.random()*(H-60);
            a.stateTimer = 70+Math.floor(Math.random()*100);
          } else {
            a.stateTimer = 50+Math.floor(Math.random()*120);
            var chats = ['☕ 커피~','🎮 게임할까','💤 졸려','😎 여유~','📱 SNS','🍕 피자!','🎵 ♪♪','✨ 평화롭다','🧋 버블티','🤔 심심...'];
            a.chatMsg = chats[Math.floor(Math.random()*chats.length)]; a.chatTimer = 120;
          }
        } else {
          var desk = this._desks[a.deskIdx];
          if (desk) { a.targetX = desk.x+12; a.targetY = desk.y+32; }
          a.state = a.ticket ? 'working' : 'idle';
          a.stateTimer = 80+Math.floor(Math.random()*200);
          if (a.ticket) a.chatMsg = '💻 '+(a.ticket.title||'').substring(0,18);
        }
      }
      var dx = a.targetX-a.x, dy = a.targetY-a.y, dist = Math.sqrt(dx*dx+dy*dy);
      if (dist > 2) {
        var spd = 0.7; a.vx = dx/dist*spd; a.vy = dy/dist*spd; a.x += a.vx; a.y += a.vy;
        a.direction = Math.abs(dx) > Math.abs(dy) ? (dx>0?2:1) : (dy>0?0:3);
      } else { a.vx = 0; a.vy = 0; }
      if (a.chatTimer > 0) a.chatTimer--;
    }
    for (var p = this._particles.length-1; p >= 0; p--) {
      this._particles[p].y -= 0.4; this._particles[p].life--;
      if (this._particles[p].life <= 0) this._particles.splice(p, 1);
    }
  },

  _draw() {
    var ctx = this._ctx, S = this.S, W = this._canvas.width, H = this._canvas.height;
    ctx.save(); ctx.scale(S, S);
    var w = W/S, h = H/S;

    /* ── 밝은 사무실 배경 ── */
    // 바닥 (나무 타일)
    ctx.fillStyle = '#3b3526';
    ctx.fillRect(0, 0, w, h);
    for (var tx = 0; tx < w; tx += 32) {
      for (var ty = 0; ty < h; ty += 32) {
        ctx.fillStyle = (tx/32+ty/32)%2===0 ? '#433d2e' : '#3b3526';
        ctx.fillRect(tx, ty, 32, 32);
      }
    }
    // 벽 (밝은 베이지)
    ctx.fillStyle = '#5c6b4f';
    ctx.fillRect(0, 0, w, 28);
    ctx.fillStyle = '#6d7a5e';
    ctx.fillRect(0, 26, w, 3);
    // 창문
    for (var wi = 0; wi < 3; wi++) {
      var wx = 60 + wi * 150;
      ctx.fillStyle = '#87CEEB';
      ctx.fillRect(wx, 4, 50, 18);
      ctx.strokeStyle = '#4a5a3e';
      ctx.lineWidth = 1.5;
      ctx.strokeRect(wx, 4, 50, 18);
      ctx.beginPath(); ctx.moveTo(wx+25, 4); ctx.lineTo(wx+25, 22); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(wx, 13); ctx.lineTo(wx+50, 13); ctx.stroke();
    }
    // 양탄자
    ctx.fillStyle = 'rgba(120,60,60,0.15)';
    ctx.fillRect(40, 45, w-80, h-65);

    /* ── 데스크 + 모니터 ── */
    for (var d = 0; d < this._desks.length; d++) {
      var desk = this._desks[d];
      // 책상 (나무)
      ctx.fillStyle = '#8B6914';
      ctx.fillRect(desk.x, desk.y, 52, 26);
      ctx.fillStyle = '#A07818';
      ctx.fillRect(desk.x+2, desk.y+2, 48, 22);
      // 다리
      ctx.fillStyle = '#6B5010';
      ctx.fillRect(desk.x+4, desk.y+24, 4, 8);
      ctx.fillRect(desk.x+44, desk.y+24, 4, 8);
      // 모니터
      ctx.fillStyle = '#222';
      ctx.fillRect(desk.x+14, desk.y-16, 24, 17);
      ctx.fillStyle = desk.screenOn ? '#2563eb' : '#111';
      ctx.fillRect(desk.x+16, desk.y-14, 20, 13);
      // 화면 내용 (켜져있을 때)
      if (desk.screenOn) {
        ctx.fillStyle = 'rgba(255,255,255,0.15)';
        for (var sl = 0; sl < 4; sl++) {
          ctx.fillRect(desk.x+18, desk.y-12+sl*3, 10+Math.random()*6, 1.5);
        }
        // 스캔라인
        var scanY = (this._frame % 13);
        ctx.fillStyle = 'rgba(100,180,255,0.2)';
        ctx.fillRect(desk.x+16, desk.y-14+scanY, 20, 1);
      }
      // 모니터 받침
      ctx.fillStyle = '#333';
      ctx.fillRect(desk.x+24, desk.y-1, 4, 2);
      // 키보드
      ctx.fillStyle = '#444';
      ctx.fillRect(desk.x+16, desk.y+6, 16, 5);
    }

    /* ── 에이전트 (스프라이트) ── */
    var sorted = this._agents.slice().sort(function(a,b){return a.y-b.y;});
    for (var i = 0; i < sorted.length; i++) {
      this._drawAgent(ctx, sorted[i]);
    }

    /* ── 코딩 파티클 ── */
    for (var p = 0; p < this._particles.length; p++) {
      var pt = this._particles[p];
      var alpha = pt.life / 35;
      ctx.font = '7px monospace';
      ctx.fillStyle = 'rgba(56,189,248,' + alpha + ')';
      ctx.fillText(pt.text, pt.x, pt.y);
    }

    /* ── 하단 상태바 ── */
    this._drawStatusBar(ctx, w, h);
    ctx.restore();
  },

  _drawAgent(ctx, a) {
    var T = this.T, x = Math.round(a.x), y = Math.round(a.y);

    // 그림자
    if (this._sprites.shadow) {
      ctx.globalAlpha = 0.5;
      ctx.drawImage(this._sprites.shadow, 0, 0, 32, 32, x-2, y+12, 20, 6);
      ctx.globalAlpha = 1;
    }

    // 스프라이트 프레임: 24col x 6row
    // 방향: down=col0-3, left=col4-7, right=col8-11, up=col12-15
    var isMoving = Math.abs(a.vx) > 0.1 || Math.abs(a.vy) > 0.1;
    var col = isMoving ? (a.direction * 4 + a.animFrame % 4) : (a.direction * 4 + ((this._frame % 40 < 20) ? 0 : 1));
    var row = a.skinRow % 6;
    var sx = col * T, sy = row * T;
    var drawW = 24, drawH = 24;

    // 몸체
    if (this._sprites.body) {
      ctx.drawImage(this._sprites.body, sx, sy, T, T, x-4, y-8, drawW, drawH);
    }
    // 의상
    var ok = 'outfit' + a.outfitIdx;
    if (this._sprites[ok]) {
      ctx.drawImage(this._sprites[ok], sx, 0, T, T, x-4, y-8, drawW, drawH);
    }
    // 머리카락
    if (this._sprites.hairs) {
      var hsy = (a.hairRow % 8) * T;
      ctx.drawImage(this._sprites.hairs, sx, hsy, T, T, x-4, y-8, drawW, drawH);
    }

    // 상태 아이콘 (티켓 상태 반영)
    if (a.state === 'working' && a.ticketStatus === 'Review') {
      ctx.font = '8px sans-serif'; ctx.fillText('🔍', x+14, y-6);
    } else if (a.state === 'working' && this._frame % 25 < 18) {
      ctx.font = '8px sans-serif'; ctx.fillText('⚡', x+14, y-6);
    } else if (a.state === 'idle' && this._frame % 50 < 25) {
      ctx.font = '7px sans-serif'; ctx.fillText('💤', x+14, y-6);
    }

    // 이름
    ctx.font = '6px sans-serif'; ctx.fillStyle = '#ddd'; ctx.textAlign = 'center';
    ctx.fillText(a.name, x+6, y+20); ctx.textAlign = 'left';

    // 말풍선
    if (a.chatTimer > 0 && a.chatMsg) {
      var bw = Math.min(a.chatMsg.length * 4.5 + 10, 90);
      var bx = x - 8, by = y - 26;
      ctx.fillStyle = 'rgba(255,255,255,0.92)';
      ctx.strokeStyle = '#aaa';
      ctx.lineWidth = 0.5;
      ctx.beginPath();
      if (ctx.roundRect) ctx.roundRect(bx, by, bw, 12, 4);
      else { ctx.moveTo(bx+4,by); ctx.lineTo(bx+bw-4,by); ctx.lineTo(bx+bw,by+4); ctx.lineTo(bx+bw,by+8); ctx.lineTo(bx+bw-4,by+12); ctx.lineTo(bx+4,by+12); ctx.lineTo(bx,by+8); ctx.lineTo(bx,by+4); ctx.closePath(); }
      ctx.fill(); ctx.stroke();
      // 꼬리
      ctx.beginPath(); ctx.moveTo(x+2,by+12); ctx.lineTo(x+4,by+16); ctx.lineTo(x+8,by+12); ctx.fillStyle='rgba(255,255,255,0.92)'; ctx.fill();
      ctx.font = '6px sans-serif'; ctx.fillStyle = '#333';
      ctx.fillText(a.chatMsg.substring(0,20), bx+4, by+9);
    }
  },

  _drawStatusBar(ctx, w, h) {
    var board = this._boardData;
    var tickets = board.tickets || [];
    var members = board.members || [];
    var done = tickets.filter(function(t){return t.status==='Done'}).length;
    var total = tickets.length;
    var pct = total > 0 ? Math.round(done/total*100) : 0;

    ctx.fillStyle = 'rgba(37,45,65,0.9)';
    ctx.fillRect(0, h-18, w, 18);
    ctx.fillStyle = '#3d4663';
    ctx.fillRect(0, h-18, w, 0.5);

    ctx.font = '7px monospace'; ctx.fillStyle = '#8b949e';
    ctx.fillText('Agents: ' + members.length, 8, h-6);
    ctx.fillText(done + '/' + total + ' (' + pct + '%)', 90, h-6);

    // 진행률 바
    ctx.fillStyle = '#1e2740';
    ctx.fillRect(190, h-12, 130, 5);
    ctx.fillStyle = pct >= 80 ? '#4AC99B' : '#3b82f6';
    ctx.fillRect(190, h-12, 130 * pct / 100, 5);

    // 상태
    var sc = {};
    tickets.forEach(function(t){sc[t.status]=(sc[t.status]||0)+1});
    var sx = 340;
    var colors = {InProgress:'#3b82f6',Review:'#f59e0b',Done:'#22c55e',Blocked:'#ef4444',Backlog:'#6b7280'};
    Object.keys(sc).forEach(function(s){
      ctx.fillStyle = colors[s] || '#888';
      ctx.fillText(s.substring(0,4)+':'+sc[s], sx, h-6);
      sx += 50;
    });
  }
};
