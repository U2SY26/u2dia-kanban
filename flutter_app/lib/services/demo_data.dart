/// Play Store 검토 + 첫 체험용 데모 모드 정적 mock 데이터.
/// 서버/네트워크 없이 모든 화면 동작. AuthService.demoMode == true 시 활성.
library;

class DemoData {
  static const String demoTeamId = 'demo-team-001';

  /// /api/teams 응답
  static Map<String, dynamic> teamsResponse() => {
        'ok': true,
        'count': 3,
        'teams': [
          {
            'team_id': 'demo-team-001',
            'name': 'AI Agent Team',
            'description': 'Multi-agent collaborative kanban demo',
            'leader_agent': 'orchestrator',
            'status': 'Active',
            'project_group': 'Demo Project',
            'created_at': '2026-05-01 10:00:00',
          },
          {
            'team_id': 'demo-team-002',
            'name': 'Sprint v2.0',
            'description': '인증 시스템 + 결제 모듈 통합',
            'leader_agent': 'architect',
            'status': 'Active',
            'project_group': 'Demo Project',
            'created_at': '2026-05-02 14:00:00',
          },
          {
            'team_id': 'demo-team-003',
            'name': 'QA Pipeline',
            'description': 'E2E + 보안 + 디자인 검수',
            'leader_agent': 'qa',
            'status': 'Active',
            'project_group': 'Demo Project',
            'created_at': '2026-05-03 09:00:00',
          },
        ],
      };

  /// /api/teams/{id}/board 응답 (12 멤버 + 20 티켓)
  static Map<String, dynamic> boardResponse(String teamId) {
    return {
      'ok': true,
      'board': {
        'team': {
          'team_id': teamId,
          'name': teamId == 'demo-team-001' ? 'AI Agent Team' : 'Sprint v2.0',
          'project_group': 'Demo Project',
          'leader_agent': 'orchestrator',
          'status': 'Active',
        },
        'members': _members,
        'tickets': _tickets(teamId),
        'project_group': 'Demo Project',
      },
    };
  }

  static const List<Map<String, dynamic>> _members = [
    {'member_id': 'm1', 'display_name': 'Alex (Frontend)', 'role': 'frontend', 'status': 'Working'},
    {'member_id': 'm2', 'display_name': 'Blake (Backend)', 'role': 'backend', 'status': 'Working'},
    {'member_id': 'm3', 'display_name': 'Casey (DB)', 'role': 'sqlite', 'status': 'Working'},
    {'member_id': 'm4', 'display_name': 'Dana (QA)', 'role': 'qa', 'status': 'Review'},
    {'member_id': 'm5', 'display_name': 'Ellis (DevOps)', 'role': 'devops', 'status': 'Idle'},
    {'member_id': 'm6', 'display_name': 'Finn (Security)', 'role': 'security', 'status': 'Working'},
    {'member_id': 'm7', 'display_name': 'Gray (Architect)', 'role': 'architect', 'status': 'Working'},
    {'member_id': 'm8', 'display_name': 'Harper (Mobile)', 'role': 'flutter', 'status': 'Working'},
    {'member_id': 'm9', 'display_name': 'Ivy (Docs)', 'role': 'docs', 'status': 'Idle'},
    {'member_id': 'm10', 'display_name': 'Jules (CS)', 'role': 'cs', 'status': 'Idle'},
    {'member_id': 'm11', 'display_name': 'Kit (Auth)', 'role': 'auth', 'status': 'Working'},
    {'member_id': 'm12', 'display_name': 'Logan (Supervisor)', 'role': 'supervisor', 'status': 'Review'},
  ];

  static List<Map<String, dynamic>> _tickets(String teamId) => [
        {'ticket_id': 'T-DEMO01', 'title': 'OAuth2 PKCE flow implementation', 'priority': 'high', 'status': 'InProgress', 'assigned_member_id': 'm11', 'progress_note': 'PKCE 검증 + token endpoint 작성 중'},
        {'ticket_id': 'T-DEMO02', 'title': 'WebSocket reconnect with backoff', 'priority': 'medium', 'status': 'InProgress', 'assigned_member_id': 'm2', 'progress_note': 'exponential backoff 적용 완료'},
        {'ticket_id': 'T-DEMO03', 'title': 'Sprint burndown chart UI', 'priority': 'medium', 'status': 'InProgress', 'assigned_member_id': 'm1', 'progress_note': 'Chart.js 통합'},
        {'ticket_id': 'T-DEMO04', 'title': 'SQLite WAL checkpoint tuning', 'priority': 'low', 'status': 'InProgress', 'assigned_member_id': 'm3', 'progress_note': 'wal_autocheckpoint 1000 적용'},
        {'ticket_id': 'T-DEMO05', 'title': 'E2E playwright suite for auth', 'priority': 'high', 'status': 'InProgress', 'assigned_member_id': 'm4', 'progress_note': '12개 시나리오 작성'},
        {'ticket_id': 'T-DEMO06', 'title': 'Penetration test — XSS vectors', 'priority': 'high', 'status': 'InProgress', 'assigned_member_id': 'm6', 'progress_note': 'OWASP Top 10 점검'},
        {'ticket_id': 'T-DEMO07', 'title': 'API rate limit middleware', 'priority': 'medium', 'status': 'InProgress', 'assigned_member_id': 'm7', 'progress_note': 'sliding window 알고리즘'},
        {'ticket_id': 'T-DEMO08', 'title': 'Mobile push notification', 'priority': 'medium', 'status': 'InProgress', 'assigned_member_id': 'm8', 'progress_note': 'FCM 통합'},
        {'ticket_id': 'T-DEMO09', 'title': 'Deduplicate notification events', 'priority': 'low', 'status': 'Review', 'assigned_member_id': 'm12', 'progress_note': '리뷰 대기'},
        {'ticket_id': 'T-DEMO10', 'title': 'Refactor sprint phase enum', 'priority': 'low', 'status': 'Review', 'assigned_member_id': 'm12', 'progress_note': '리뷰 대기'},
        {'ticket_id': 'T-DEMO11', 'title': 'Initial DB schema migration', 'priority': 'high', 'status': 'Done'},
        {'ticket_id': 'T-DEMO12', 'title': 'Login screen redesign', 'priority': 'medium', 'status': 'Done'},
        {'ticket_id': 'T-DEMO13', 'title': 'Onboarding tour', 'priority': 'medium', 'status': 'Done'},
        {'ticket_id': 'T-DEMO14', 'title': 'Project group filter', 'priority': 'low', 'status': 'Done'},
        {'ticket_id': 'T-DEMO15', 'title': 'Activity heatmap', 'priority': 'medium', 'status': 'Done'},
        {'ticket_id': 'T-DEMO16', 'title': 'Token usage dashboard', 'priority': 'low', 'status': 'Done'},
        {'ticket_id': 'T-DEMO17', 'title': 'Velocity trend chart', 'priority': 'low', 'status': 'Done'},
        {'ticket_id': 'T-DEMO18', 'title': 'Mock i18n keys', 'priority': 'low', 'status': 'Backlog'},
        {'ticket_id': 'T-DEMO19', 'title': 'Email digest scheduler', 'priority': 'low', 'status': 'Backlog'},
        {'ticket_id': 'T-DEMO20', 'title': 'Stuck on external review', 'priority': 'medium', 'status': 'Blocked'},
      ];

  static Map<String, dynamic> overviewResponse() => {
        'ok': true,
        'overview': {
          'total_teams': 3, 'active_teams': 3,
          'total_tickets': 60, 'inprogress': 24, 'review': 6, 'done': 21,
          'blocked': 3, 'backlog': 6,
          'agents_active': 12, 'usage_today_tokens': 142000,
        },
      };

  static Map<String, dynamic> statsResponse(String teamId) => {
        'ok': true,
        'stats': {
          'team_id': teamId,
          'tickets_by_status': {'Backlog': 2, 'InProgress': 8, 'Review': 2, 'Done': 7, 'Blocked': 1},
          'completion_rate': 0.35, 'velocity_avg': 6.5,
          'avg_qa_score': 4.2, 'rework_rate': 0.08,
        },
      };

  /// /api/cli/tmux/sessions
  static Map<String, dynamic> tmuxSessions() => {
        'ok': true,
        'current': 'demo',
        'sessions': [
          {'name': 'demo', 'windows': 3, 'attached': true, 'created': '2026-05-05'},
          {'name': 'build', 'windows': 1, 'attached': false, 'created': '2026-05-04'},
        ],
      };

  static Map<String, dynamic> tmuxWindows(String session) => {
        'ok': true, 'session': session,
        'windows': [
          {'index': 0, 'name': 'editor', 'active': true, 'panes': 2},
          {'index': 1, 'name': 'server', 'active': false, 'panes': 1},
          {'index': 2, 'name': 'logs', 'active': false, 'panes': 1},
        ],
      };

  /// /api/vscode/sessions
  static Map<String, dynamic> vscodeSessions() => {
        'ok': true, 'count': 0, 'sessions': [], 'port_range': [8100, 8199],
      };

  static Map<String, dynamic> vscodeRecent() => {
        'ok': true, 'count': 3,
        'candidates': [
          {'path': '~/demo/u2dia-kanban', 'label': 'u2dia-kanban', 'source': 'demo'},
          {'path': '~/demo/example-frontend', 'label': 'example-frontend', 'source': 'demo'},
          {'path': '~/demo/example-backend', 'label': 'example-backend', 'source': 'demo'},
        ],
      };

  /// 활동 로그 / 액티비티 등 일반 응답
  static Map<String, dynamic> activityResponse() => {
        'ok': true, 'count': 5,
        'activity': [
          {'id': 1, 'event': 'ticket_status_changed', 'detail': 'T-DEMO11 → Done', 'created_at': '2026-05-05 14:32:00'},
          {'id': 2, 'event': 'message_created', 'detail': 'Casey: "DB 마이그레이션 완료"', 'created_at': '2026-05-05 14:25:00'},
          {'id': 3, 'event': 'artifact_created', 'detail': 'Alex: design-spec.md', 'created_at': '2026-05-05 14:10:00'},
          {'id': 4, 'event': 'ticket_claimed', 'detail': 'Kit ↔ T-DEMO01', 'created_at': '2026-05-05 13:55:00'},
          {'id': 5, 'event': 'sprint_phase_changed', 'detail': 'Sprint v2.0 → Build', 'created_at': '2026-05-05 13:30:00'},
        ],
      };

  /// 스프린트
  static Map<String, dynamic> sprintsResponse(String teamId) => {
        'ok': true, 'count': 2,
        'sprints': [
          {'sprint_id': 'sprint-1', 'name': 'Sprint v1.9', 'phase': 'Done', 'goal': 'API 안정화', 'tickets_total': 14, 'tickets_done': 14, 'velocity': 7.2},
          {'sprint_id': 'sprint-2', 'name': 'Sprint v2.0', 'phase': 'Build', 'goal': '인증 + 결제', 'tickets_total': 20, 'tickets_done': 7, 'velocity': 6.5},
        ],
      };

  /// 일반 fallback (인식 못한 모든 GET 경로)
  static Map<String, dynamic> okEmpty() => {'ok': true, 'data': []};
  static Map<String, dynamic> okSimple() => {'ok': true};
}
