#!/usr/bin/env python3
"""Kanban Supervisor Monitor v2 - polls, tracks conversations, sends encouragement."""
import json, urllib.request, time, sys, random
from datetime import datetime

BASE = 'http://localhost:5555'
POLL_INTERVAL = 300  # 5 minutes
IDLE_TIMEOUT = 1800  # 30 minutes

ENCOURAGEMENT = {
    'new_ticket': [
        'New ticket! Clear goals are half the battle. Fighting!',
        'Good start! Break it into small chunks for faster progress.',
        'Well-defined ticket. Proceed as planned!',
    ],
    'in_progress': [
        'Work started! Focus mode on. Leave a message if stuck.',
        'Great! Save intermediate results every 30 minutes.',
        'In progress! Check dependent tickets in advance.',
    ],
    'done': [
        'Done! Great work. Move on to the next ticket!',
        'Excellent! Done confirmed. Team progress is rising.',
        'Well finished! Leave artifacts or notes if applicable.',
    ],
    'blocked': [
        'Blocked -- clarify if external dependency or technical issue.',
        'Blocked. Check if another team member can assist.',
        'When stuck, find workarounds first, then escalate.',
    ],
    'new_member': [
        'New agent spawned! Claim the highest priority Backlog ticket.',
        'Welcome to the team. Check the board and pick a ticket matching your role.',
    ],
    'new_team': [
        'New team created! Create tickets, spawn agents, then distribute work.',
        'Welcome! Write a clear description -- it helps at archive time.',
    ],
}

def pick(category):
    return random.choice(ENCOURAGEMENT.get(category, ['Keep going!']))

def api(path):
    try:
        req = urllib.request.Request(f'{BASE}{path}')
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except:
        return None

def post(path, data):
    try:
        req = urllib.request.Request(f'{BASE}{path}',
            data=json.dumps(data).encode(),
            headers={'Content-Type': 'application/json'},
            method='POST')
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except:
        return None

def send_activity(team_id, action, message):
    post('/api/activity', {'team_id': team_id, 'action': action, 'message': message})

def get_snapshot():
    teams_data = api('/api/teams')
    if not teams_data or not teams_data.get('ok'):
        return None
    snapshot = {}
    for t in teams_data['teams']:
        tid = t['team_id']
        board = api(f'/api/teams/{tid}/board')
        if not board or not board.get('ok'):
            continue
        b = board['board']
        tickets = b.get('tickets', [])
        members = b.get('members', [])

        msg_counts = {}
        for tk in tickets:
            msgs = api(f'/api/tickets/{tk["ticket_id"]}/messages')
            msg_counts[tk['ticket_id']] = msgs.get('count', 0) if msgs and msgs.get('ok') else 0

        ticket_map = {}
        for tk in tickets:
            ticket_map[tk['ticket_id']] = {
                'status': tk['status'],
                'title': tk['title'],
                'priority': tk.get('priority', '?'),
                'assigned': tk.get('assigned_member_id'),
                'msg_count': msg_counts.get(tk['ticket_id'], 0),
            }

        snapshot[tid] = {
            'name': t['name'],
            'group': t.get('project_group', '?'),
            'member_count': len(members),
            'ticket_count': len(tickets),
            'tickets': ticket_map,
        }
    return snapshot

def diff_and_respond(old, new):
    changes = []

    for tid in new:
        if tid not in old:
            changes.append(('new_team', tid, new[tid]['name']))
            send_activity(tid, 'supervisor_encouragement',
                f'[SUPERVISOR] {pick("new_team")}')

    for tid in old:
        if tid not in new:
            changes.append(('removed_team', tid, old[tid]['name']))

    for tid in new:
        if tid not in old:
            continue
        o, n = old[tid], new[tid]

        for tkid in n['tickets']:
            if tkid not in o['tickets']:
                tk = n['tickets'][tkid]
                changes.append(('new_ticket', tid, n['name'], tkid, tk['title']))
                send_activity(tid, 'supervisor_encouragement',
                    f'[SUPERVISOR] New ticket [{tkid}] {tk["title"][:40]} -- {pick("new_ticket")}')

        for tkid in n['tickets']:
            if tkid in o['tickets']:
                old_s = o['tickets'][tkid]['status']
                new_s = n['tickets'][tkid]['status']
                if old_s != new_s:
                    tk = n['tickets'][tkid]
                    changes.append(('status', tid, n['name'], tkid, tk['title'], old_s, new_s))

                    if new_s == 'Done':
                        send_activity(tid, 'supervisor_encouragement',
                            f'[SUPERVISOR] {tkid} Done! {pick("done")}')
                    elif new_s == 'Blocked':
                        send_activity(tid, 'supervisor_advice',
                            f'[SUPERVISOR] {tkid} Blocked. {pick("blocked")}')
                    elif new_s in ('In Progress', 'InProgress'):
                        send_activity(tid, 'supervisor_encouragement',
                            f'[SUPERVISOR] {tkid} Started! {pick("in_progress")}')

        for tkid in n['tickets']:
            if tkid in o['tickets']:
                old_mc = o['tickets'][tkid].get('msg_count', 0)
                new_mc = n['tickets'][tkid].get('msg_count', 0)
                if new_mc > old_mc:
                    diff = new_mc - old_mc
                    changes.append(('new_msgs', tid, n['name'], tkid,
                                   n['tickets'][tkid]['title'], diff))

        if o['member_count'] != n['member_count']:
            changes.append(('members', tid, n['name'], o['member_count'], n['member_count']))
            if n['member_count'] > o['member_count']:
                send_activity(tid, 'supervisor_encouragement',
                    f'[SUPERVISOR] New agent joined! ({o["member_count"]}->{n["member_count"]}) {pick("new_member")}')

    return changes

# === Main Loop ===
print(f'[{datetime.now():%H:%M:%S}] Kanban Supervisor Monitor v2 started')
print(f'  Poll: {POLL_INTERVAL}s | Idle timeout: {IDLE_TIMEOUT}s')
print(f'  Features: status + conversation + encouragement')
sys.stdout.flush()

prev = get_snapshot()
if not prev:
    print('ERROR: Cannot reach kanban server')
    sys.exit(1)

print(f'[{datetime.now():%H:%M:%S}] Snapshot: {len(prev)} teams')
sys.stdout.flush()

last_activity = time.time()
cycle = 0

while True:
    time.sleep(POLL_INTERVAL)
    cycle += 1

    now = get_snapshot()
    if not now:
        print(f'[{datetime.now():%H:%M:%S}] WARNING: Server unreachable')
        sys.stdout.flush()
        continue

    changes = diff_and_respond(prev, now)
    ts = f'[{datetime.now():%H:%M:%S}]'

    if changes:
        last_activity = time.time()
        print(f'{ts} Cycle #{cycle} -- {len(changes)} changes:')
        for c in changes:
            if c[0] == 'new_team':
                print(f'  + TEAM: {c[2]}')
            elif c[0] == 'removed_team':
                print(f'  - TEAM: {c[2]}')
            elif c[0] == 'new_ticket':
                print(f'  + TICKET: {c[2]}/{c[3]} {c[4][:50]}')
            elif c[0] == 'status':
                print(f'  ~ {c[2]}/{c[3]} [{c[5]}]->[{c[6]}] {c[4][:45]}')
            elif c[0] == 'new_msgs':
                print(f'  MSG {c[2]}/{c[3]} +{c[5]} messages -- {c[4][:40]}')
            elif c[0] == 'members':
                print(f'  MEMBER {c[2]}: {c[3]}->{c[4]}')
    else:
        elapsed = time.time() - last_activity
        remain = IDLE_TIMEOUT - elapsed
        print(f'{ts} Cycle #{cycle} -- quiet. Idle {elapsed:.0f}s (exit in {remain:.0f}s)')

    sys.stdout.flush()
    prev = now

    if time.time() - last_activity >= IDLE_TIMEOUT:
        print(f'[{datetime.now():%H:%M:%S}] === 30min idle. Shutting down ===')
        total_teams = len(now)
        total_tickets = sum(s['ticket_count'] for s in now.values())
        print(f'  Final: {total_teams} teams, {total_tickets} tickets')
        if now:
            send_activity(list(now.keys())[0], 'supervisor_shutdown',
                f'[SUPERVISOR] 30min idle -- monitor off. {total_teams} teams, {total_tickets} tickets.')
        sys.stdout.flush()
        break

print('Monitor v2 exited.')
