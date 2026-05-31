#!/usr/bin/env python3
"""
Kanban Realtime Supervisor v3
- SSE-based: instant reaction to ALL events (no polling delay)
- Sends encouragement, advice, and warnings in real-time
- Tracks all teams, tickets, conversations, member spawns
- Exits after 30 minutes of no events
"""
import json, urllib.request, threading, time, sys, random, http.client
from datetime import datetime
from urllib.parse import urlparse

BASE = 'http://localhost:5555'
SSE_URL = f'{BASE}/api/supervisor/events'
IDLE_TIMEOUT = 1800  # 30 minutes

# ── 구어체 피드백 템플릿 ──
MESSAGES = {
    'team_created': [
        '오 새 팀이네! 티켓부터 만들고, 에이전트 스폰해서 일 나누면 돼. 화이팅~',
        '팀 생성 확인했어. description 잘 써두면 나중에 아카이브할 때 편해. 잘 해보자!',
        '새 팀 왔다! project_group 맞게 설정했는지 한번 확인해봐~',
    ],
    'member_spawned': [
        '에이전트 합류! Backlog에서 제일 급한 거부터 claim 해서 잡아봐.',
        '새 멤버 왔네~ 보드 먼저 훑어보고 본인 역할에 맞는 티켓 골라.',
        '스폰 확인! 하나 잡아서 끝내고 다음 거 잡는 게 젤 빨라.',
    ],
    'ticket_created': [
        '티켓 접수! priority 잘 잡았지? critical이면 먼저 처리해야 해.',
        '좋아 티켓 만들었네. 다른 티켓이랑 의존성 있으면 depends_on 걸어둬.',
        '오케이 접수 완료~ estimate_minutes 넣어두면 나중에 벤치마크할 때 좋아.',
    ],
    'ticket_claimed': [
        '잡았다! 이거 하나에 집중하고, 시작하면 InProgress로 바꿔줘.',
        '할당 완료~ 중간중간 메시지 남겨두면 팀원들이 진행상황 알 수 있어.',
    ],
    'status_to_InProgress': [
        '시작이다! 집중 모드 돌입~ 오래 걸리면 중간 결과라도 남겨둬.',
        '진행 중! 15분 넘게 막히면 메시지 남기고 다른 방법 시도해봐.',
        '가자! 작은 단위로 쪼개서 하나씩 치우면 금방이야.',
        '좋아 달리고 있네! 커밋 자주 하는 거 잊지 말고~',
    ],
    'status_to_Done': [
        '끝났어?! 수고했다!! 산출물 있으면 artifact로 남기고 다음 거 ㄱㄱ',
        '오 완료! 잘했어~ 팀 진행률 올라간다!',
        '마무리 깔끔하네. actual_minutes 기록해두면 다음에 견적 잡을 때 도움 돼.',
        '와 빠르다! Done 확인. 이 기세로 다음 것도 부탁해~',
        '잘 끝냈다! 다른 티켓 남아있으면 바로 claim 해서 이어가자.',
    ],
    'status_to_Blocked': [
        '어 막혔어? 뭐 때문인지 메시지로 남겨봐. 외부 문제야 기술 문제야?',
        'Blocked이네... 차단 원인 적어두고, 다른 팀원이 도울 수 있는지 확인해봐.',
        '막힌 거 보여. 우회 방법 먼저 찾아보고, 안 되면 에스컬레이션 하자.',
        '흠 Blocked... depends_on 있으면 걸어두고, 원인을 구체적으로 적어줘.',
    ],
    'status_to_Review': [
        '리뷰 단계! 산출물 다 붙였지? 빠진 거 없는지 한번 확인해봐.',
        '리뷰 들어갔네. 셀프 체크 — 티켓 설명이랑 결과물 맞는지 한번 비교해봐.',
    ],
    'message_created': [
        '좋아 소통 잘 하고 있네! 팀워크가 속도를 만든다.',
        '대화 확인~ 이렇게 주고받으면 훨씬 효율적이야.',
    ],
    'artifact_created': [
        '산출물 등록! 이거 나중에 아카이브할 때 같이 백업되니까 잘 해뒀어.',
        '오 artifact 남겼네 좋은 습관이야~',
    ],
}

def pick(category):
    templates = MESSAGES.get(category, ['[SUPERVISOR] Noted. Keep up the good work!'])
    return random.choice(templates)

def api_get(path):
    try:
        req = urllib.request.Request(f'{BASE}{path}')
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except:
        return None

def api_post(path, data):
    try:
        req = urllib.request.Request(f'{BASE}{path}',
            data=json.dumps(data).encode(),
            headers={'Content-Type': 'application/json'},
            method='POST')
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except:
        return None

def send_advice(team_id, action, message):
    api_post('/api/activity', {'team_id': team_id, 'action': action, 'message': message})

def get_team_context(team_id):
    """Get quick context about a team for smarter advice."""
    board = api_get(f'/api/teams/{team_id}/board')
    if not board or not board.get('ok'):
        return None
    b = board['board']
    tickets = b.get('tickets', [])
    members = b.get('members', [])
    done = sum(1 for t in tickets if t['status'] == 'Done')
    total = len(tickets)
    progress = round(done / total * 100) if total > 0 else 0
    return {
        'name': b['team']['name'],
        'members': len(members),
        'tickets': total,
        'done': done,
        'progress': progress,
        'blocked': sum(1 for t in tickets if t['status'] == 'Blocked'),
    }

# ── SSE Event Handlers ──

def handle_event(event_type, data, team_id):
    """Process each SSE event and send appropriate feedback."""
    ts = datetime.now().strftime('%H:%M:%S')

    if event_type == 'team_created':
        name = data.get('name', '?')
        print(f'[{ts}] + TEAM CREATED: {name} ({team_id})')
        send_advice(team_id, 'supervisor_welcome', pick('team_created'))

    elif event_type == 'member_spawned':
        role = data.get('role', '?')
        mid = data.get('member_id', '?')
        print(f'[{ts}] + AGENT SPAWNED: {role} ({mid}) in {team_id}')
        send_advice(team_id, 'supervisor_encouragement', pick('member_spawned'))

    elif event_type == 'ticket_created':
        title = data.get('title', '?')
        tkid = data.get('ticket_id', '?')
        print(f'[{ts}] + TICKET: {tkid} "{title}" in {team_id}')
        send_advice(team_id, 'supervisor_encouragement', pick('ticket_created'))

    elif event_type == 'ticket_claimed':
        tkid = data.get('ticket_id', '?')
        mid = data.get('member_id', '?')
        print(f'[{ts}] ~ CLAIMED: {tkid} by {mid} in {team_id}')
        send_advice(team_id, 'supervisor_encouragement', pick('ticket_claimed'))

    elif event_type == 'ticket_status_changed':
        tkid = data.get('ticket_id', '?')
        new_status = data.get('status', '?')
        print(f'[{ts}] ~ STATUS: {tkid} -> {new_status} in {team_id}')

        cat = f'status_to_{new_status}'
        msg = pick(cat)
        action = 'supervisor_advice' if new_status == 'Blocked' else 'supervisor_encouragement'
        send_advice(team_id, action, msg)

        # Extra: check team progress on Done
        if new_status == 'Done':
            ctx = get_team_context(team_id)
            if ctx and ctx['progress'] >= 80:
                send_advice(team_id, 'supervisor_milestone',
                    f'[SUPERVISOR MILESTONE] {ctx["name"]} progress: {ctx["progress"]}% ({ctx["done"]}/{ctx["tickets"]}). Almost there!')
            if ctx and ctx['progress'] == 100:
                send_advice(team_id, 'supervisor_complete',
                    f'[SUPERVISOR] {ctx["name"]} 100% COMPLETE! All {ctx["tickets"]} tickets Done. Ready to archive!')

    elif event_type == 'message_created':
        tkid = data.get('ticket_id', '?')
        print(f'[{ts}] MSG: new message on {tkid} in {team_id}')
        # Don't spam on every message -- only log, no advice

    elif event_type == 'artifact_created':
        tkid = data.get('ticket_id', '?')
        aid = data.get('artifact_id', '?')
        print(f'[{ts}] ARTIFACT: {aid} on {tkid} in {team_id}')
        send_advice(team_id, 'supervisor_encouragement', pick('artifact_created'))

    elif event_type == 'feedback_created':
        tkid = data.get('ticket_id', '?')
        score = data.get('score', '?')
        print(f'[{ts}] FEEDBACK: {tkid} score={score} in {team_id}')

    elif event_type == 'activity_logged':
        action = data.get('action', '?')
        # Ignore our own supervisor messages to avoid loops
        if 'supervisor' in action:
            return False  # Don't count as external activity
        print(f'[{ts}] ACTIVITY: {action} in {team_id}')

    elif event_type == 'team_archived':
        name = data.get('name', '?')
        print(f'[{ts}] ARCHIVED: {name} ({team_id})')

    else:
        print(f'[{ts}] EVENT: {event_type} in {team_id}')

    return True  # Count as activity


# ── SSE Client ──

def connect_sse():
    """Connect to global SSE and yield parsed events."""
    parsed = urlparse(SSE_URL)
    conn = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=60)
    conn.request('GET', parsed.path)
    resp = conn.getresponse()

    if resp.status != 200:
        raise ConnectionError(f'SSE returned {resp.status}')

    buffer = ''
    while True:
        chunk = resp.read(1).decode('utf-8', errors='replace')
        if not chunk:
            break
        buffer += chunk
        while '\n\n' in buffer:
            block, buffer = buffer.split('\n\n', 1)
            event_type = None
            event_data = None
            for line in block.split('\n'):
                if line.startswith('event:'):
                    event_type = line[6:].strip()
                elif line.startswith('data:'):
                    event_data = line[5:].strip()
            if event_data:
                try:
                    parsed_data = json.loads(event_data)
                    yield {
                        'event': event_type or parsed_data.get('type', 'unknown'),
                        'team_id': parsed_data.get('team_id', ''),
                        'data': parsed_data.get('data', parsed_data),
                        'ts': parsed_data.get('ts', ''),
                    }
                except json.JSONDecodeError:
                    pass


# ── Main ──

def main():
    print(f'[{datetime.now():%H:%M:%S}] === Kanban Realtime Supervisor v3 ===')
    print(f'  Mode: SSE (instant reaction)')
    print(f'  Idle timeout: {IDLE_TIMEOUT}s')
    print(f'  Endpoint: {SSE_URL}')
    sys.stdout.flush()

    # Initial team summary
    teams = api_get('/api/teams')
    if teams and teams.get('ok'):
        print(f'  Active teams: {teams["count"]}')
        for t in teams['teams']:
            ctx = get_team_context(t['team_id'])
            if ctx:
                print(f'    - {ctx["name"]}: {ctx["members"]} agents, {ctx["tickets"]} tickets, {ctx["progress"]}% done')
    sys.stdout.flush()

    last_activity = time.time()
    reconnect_count = 0

    while True:
        try:
            print(f'[{datetime.now():%H:%M:%S}] Connecting to SSE stream...')
            sys.stdout.flush()

            for event in connect_sse():
                etype = event['event']
                team_id = event['team_id']
                edata = event['data']

                # Skip heartbeats and connected events
                if etype in ('connected', 'heartbeat', ''):
                    # Check idle timeout on heartbeat
                    if time.time() - last_activity >= IDLE_TIMEOUT:
                        print(f'[{datetime.now():%H:%M:%S}] === 30min idle. Supervisor shutting down ===')
                        sys.stdout.flush()
                        return
                    continue

                is_external = handle_event(etype, edata, team_id)
                if is_external:
                    last_activity = time.time()
                sys.stdout.flush()

                # Check idle timeout
                if time.time() - last_activity >= IDLE_TIMEOUT:
                    print(f'[{datetime.now():%H:%M:%S}] === 30min idle. Supervisor shutting down ===')
                    sys.stdout.flush()
                    return

        except (ConnectionError, http.client.HTTPException, OSError) as e:
            reconnect_count += 1
            wait = min(30, 5 * reconnect_count)
            print(f'[{datetime.now():%H:%M:%S}] SSE disconnected: {e}. Reconnecting in {wait}s...')
            sys.stdout.flush()
            time.sleep(wait)

            # Check idle timeout during reconnect
            if time.time() - last_activity >= IDLE_TIMEOUT:
                print(f'[{datetime.now():%H:%M:%S}] === 30min idle during reconnect. Shutting down ===')
                sys.stdout.flush()
                return
        except KeyboardInterrupt:
            print(f'\n[{datetime.now():%H:%M:%S}] Supervisor stopped by user.')
            sys.stdout.flush()
            return

    print('Supervisor v3 exited.')


if __name__ == '__main__':
    main()
