import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService extends ChangeNotifier {
  String _baseUrl = 'http://localhost:5555';
  String? _authToken;
  bool _connected = false;

  bool get connected => _connected;
  String get baseUrl => _baseUrl;

  void configure(String baseUrl, {String? token}) {
    _baseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
    _authToken = token;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-cache, no-store',
    'Pragma': 'no-cache',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  Future<Map<String, dynamic>> get(String path) async {
    try {
      final sep = path.contains('?') ? '&' : '?';
      final url = '$_baseUrl$path${sep}_t=${DateTime.now().millisecondsSinceEpoch}';
      final res = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));
      _connected = res.statusCode < 500;
      notifyListeners();
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      _connected = false;
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    try {
      final timeout = path.contains('agent/chat') ? 120 : 15;
      final res = await http.post(Uri.parse('$_baseUrl$path'),
          headers: _headers, body: jsonEncode(body))
          .timeout(Duration(seconds: timeout));
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    try {
      final res = await http.put(Uri.parse('$_baseUrl$path'),
          headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    try {
      final res = await http.delete(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // ── Teams ──
  Future<List<Map<String, dynamic>>> getTeams({String? status}) async {
    final res = await get('/api/teams${status != null ? '?status=$status' : ''}');
    return ((res['teams'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  // ── Board ──
  Future<Map<String, dynamic>> getBoard(String teamId) async => get('/api/teams/$teamId/board');
  Future<Map<String, dynamic>> getStats(String teamId) async => get('/api/teams/$teamId/stats');

  // ── Overview ──
  Future<Map<String, dynamic>> getOverview() async => get('/api/supervisor/overview');

  // ── Projects ──
  Future<List<Map<String, dynamic>>> getProjects() async {
    final res = await get('/api/github/projects');
    return ((res['projects'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  // ── Archives ──
  Future<List<Map<String, dynamic>>> getArchives() async {
    final res = await get('/api/archives');
    return ((res['archives'] as List?) ?? []).cast<Map<String, dynamic>>();
  }
  Future<Map<String, dynamic>> archiveDetail(String teamId) => get('/api/archives/$teamId');

  // ── Messages ──
  Future<List<Map<String, dynamic>>> getMessages(String teamId) async {
    final res = await get('/api/teams/$teamId/messages');
    return ((res['messages'] as List?) ?? []).cast<Map<String, dynamic>>();
  }
  Future<Map<String, dynamic>> sendMessage(String teamId, String content, {String sender = '유디(앱)'}) =>
      post('/api/teams/$teamId/messages', {'content': content, 'sender': sender, 'role': 'orchestrator'});

  // ── Tickets ──
  // ── Ticket Thread ──
  Future<List<Map<String, dynamic>>> ticketThread(String ticketId) async {
    final res = await get('/api/tickets/$ticketId/thread');
    return ((res['thread'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> updateTicketProgress(String ticketId, String note) =>
      put('/api/tickets/$ticketId/progress', {'note': note});

  Future<Map<String, dynamic>> createTicket(String teamId, Map<String, dynamic> data) =>
      post('/api/teams/$teamId/tickets', data);
  Future<Map<String, dynamic>> updateTicketStatus(String ticketId, String status) =>
      put('/api/tickets/$ticketId/status', {'status': status});
  Future<Map<String, dynamic>> claimTicket(String ticketId, String agentId) =>
      post('/api/tickets/$ticketId/claim', {'agent_id': agentId, 'agent_role': 'user'});

  // ── System ──
  Future<Map<String, dynamic>> getMetrics() async => get('/api/system/metrics');
  Future<List<Map<String, dynamic>>> getClients() async {
    final res = await get('/api/system/clients');
    return ((res['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
  }
  Future<List<Map<String, dynamic>>> getTokens() async {
    final res = await get('/api/tokens');
    return ((res['tokens'] as List?) ?? []).cast<Map<String, dynamic>>();
  }
  Future<List<Map<String, dynamic>>> getProcesses() async {
    final res = await get('/api/system/processes');
    return ((res['processes'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  // ── Resident Agent (유디) ──
  Future<Map<String, dynamic>> residentHistory({int limit = 200, String type = 'all'}) =>
      get('/api/resident/history?limit=$limit&type=$type');
  Future<Map<String, dynamic>> residentKpi() => get('/api/resident/kpi');
  Future<Map<String, dynamic>> agentsKpi({String? teamId}) =>
      get('/api/agents/kpi${teamId != null ? '?team_id=$teamId' : ''}');

  // ── Activity ──
  Future<List<Map<String, dynamic>>> getActivity({int limit = 50}) async {
    final res = await get('/api/activity?limit=$limit');
    return ((res['logs'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  // ── Artifacts ──
  Future<List<Map<String, dynamic>>> getArtifacts(String teamId) async {
    final res = await get('/api/teams/$teamId/artifacts');
    return ((res['artifacts'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  // ── Teams with stats (병렬 조회) ──
  Future<List<Map<String, dynamic>>> getTeamsWithStats({String? status}) async {
    final teams = await getTeams(status: status);
    if (teams.isEmpty) return [];
    final statsResults = await Future.wait(
      teams.map((t) => getStats(t['team_id'] as String)),
    );
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < teams.length; i++) {
      final team = Map<String, dynamic>.from(teams[i]);
      final s = (statsResults[i]['stats'] as Map?) ?? {};
      final total = (s['total_tickets'] as num?)?.toInt() ?? 0;
      final sc = (s['status_counts'] as Map?) ?? {};
      final done = (sc['Done'] as num?)?.toInt() ?? 0;
      team['total_tickets'] = total;
      team['done_tickets'] = done;
      team['in_progress'] = (sc['InProgress'] as num?)?.toInt() ?? 0;
      team['progress'] = total > 0 ? (done / total * 100) : 0.0;
      team['completion_rate'] = (s['completion_rate'] as num?)?.toDouble() ?? 0.0;
      result.add(team);
    }
    return result;
  }

  // ── Teams management ──
  Future<Map<String, dynamic>> createTeam(Map<String, dynamic> data) => post('/api/teams', data);
  Future<Map<String, dynamic>> archiveTeam(String teamId) => post('/api/teams/$teamId/archive', {});

  // ── Telegram ──
  Future<Map<String, dynamic>> sendTelegram(String msg) =>
      post('/api/telegram/send', {'message': msg});

  // ── MCP / Orchestrator ──
  Future<Map<String, dynamic>> triggerOrchestrator(String teamId) =>
      post('/api/teams/$teamId/orchestrate', {});

  // ── Dashboard data ──
  Future<Map<String, dynamic>> globalStats() => get('/api/supervisor/stats');
  Future<Map<String, dynamic>> heatmap() => get('/api/supervisor/heatmap?mode=10min');
  Future<Map<String, dynamic>> timeline() => get('/api/supervisor/timeline?hours=24');
  Future<Map<String, dynamic>> usageGlobal() => get('/api/usage/global');
  Future<Map<String, dynamic>> systemMetrics() => get('/api/system/metrics');
  Future<Map<String, dynamic>> globalActivity({int limit = 80}) => get('/api/supervisor/activity?limit=$limit');

  // ── Project Visibility Settings ──
  Future<Map<String, dynamic>> getVisibleProjects() => get('/api/settings/visible-projects');
  Future<Map<String, dynamic>> setVisibleProjects(List<String> projects) =>
      put('/api/settings/visible-projects', {'projects': projects});

  // ── Project Architecture & Inventory ──
  Future<Map<String, dynamic>> projectArchitecture() => get('/api/projects/architecture');
  Future<Map<String, dynamic>> projectInventory() => get('/api/projects/inventory');

  // ── Sprint ──
  Future<Map<String, dynamic>> sprintGlobalStats() => get('/api/sprints/global/stats');
  Future<List<Map<String, dynamic>>> sprintList(String teamId) async {
    final res = await get('/api/teams/$teamId/sprints');
    return ((res['sprints'] as List?) ?? []).cast<Map<String, dynamic>>();
  }
  Future<Map<String, dynamic>> sprintVelocity(String teamId) => get('/api/teams/$teamId/velocity');

  // ── Project Goals ──
  Future<Map<String, dynamic>> projectGoals() => get('/api/projects/goals');

  // ── Team History ──
  Future<Map<String, dynamic>> teamHistory(String teamId, {int limit = 100}) =>
      get('/api/teams/$teamId/history?limit=$limit');

  // ── Project Goal Registration ──
  Future<Map<String, dynamic>> registerProjectGoal(String project, String goal, List<Map<String, dynamic>> milestones) =>
      post('/api/projects/goals/register', {'project': project, 'goal': goal, 'milestones': milestones});

  Future<Map<String, dynamic>> getProjectGoal(String project) =>
      get('/api/projects/$project/goals');

  // ── Sprint Detail ──
  Future<Map<String, dynamic>> sprintDetail(String sprintId) => get('/api/sprints/$sprintId');
  Future<Map<String, dynamic>> sprintBurndown(String sprintId) => get('/api/sprints/$sprintId/burndown');
  Future<Map<String, dynamic>> sprintRetro(String sprintId) => get('/api/sprints/$sprintId/retro');

  Future<List<Map<String, dynamic>>> chatHistory() async {
    final res = await get('/api/agent/chat/sessions');
    return ((res['sessions'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  // ── Chat ──
  Future<Map<String, dynamic>> agentChat(String message, String sessionId, {String? project, bool dispatch = false}) =>
      post('/api/agent/chat', {
        'message': message,
        'session_id': sessionId,
        if (project != null) 'project': project,
        if (dispatch) 'dispatch': true,
      });

  // ── Notification preferences ──
  Future<Map<String, dynamic>> getNotifPrefs() => get('/api/settings/notifications');
  Future<Map<String, dynamic>> setNotifPrefs(Map<String, dynamic> prefs) => post('/api/settings/notifications', prefs);

  // ── CLI Jobs ──
  Future<List<Map<String, dynamic>>> cliJobs({String? status}) async {
    final q = status != null ? '?status=$status' : '';
    final res = await get('/api/cli/jobs$q');
    return ((res['jobs'] as List?) ?? []).cast<Map<String, dynamic>>();
  }
  Future<Map<String, dynamic>> createCliJob(Map<String, dynamic> data) =>
      post('/api/cli/jobs', data);
  Future<Map<String, dynamic>> approveCliJob(String jobId) =>
      put('/api/cli/jobs/$jobId/approve', {});
  Future<Map<String, dynamic>> cancelCliJob(String jobId) =>
      put('/api/cli/jobs/$jobId/cancel', {});
  Future<Map<String, dynamic>> killCliJob(String jobId) =>
      put('/api/cli/jobs/$jobId/kill', {});
  Future<Map<String, dynamic>> cliJobLog(String jobId) =>
      get('/api/cli/jobs/$jobId/log');
  Future<Map<String, dynamic>> cliStats() => get('/api/cli/stats');

  // ── Exchange Rate ──
  Future<Map<String, dynamic>> exchangeRate() => get('/api/exchange-rate');

  // ── Usage History ──
  Future<Map<String, dynamic>> usageHistory() => get('/api/usage/history');

  // ── Team Specialists ──
  Future<Map<String, dynamic>> teamSpecialists(String teamId) => get('/api/teams/$teamId/specialists');

  // ── Supervisor Pipeline ──
  Future<Map<String, dynamic>> supervisorPipeline() => get('/api/supervisor/pipeline');
  Future<Map<String, dynamic>> supervisorReviewStats() => get('/api/supervisor/review/stats');
  Future<List<Map<String, dynamic>>> cliModels() async {
    final res = await get('/api/cli/models');
    return ((res['models'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  // ── Ping ──
  Future<bool> ping() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/teams'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      _connected = res.statusCode == 200;
      notifyListeners();
      return _connected;
    } catch (_) {
      _connected = false;
      notifyListeners();
      return false;
    }
  }
}
