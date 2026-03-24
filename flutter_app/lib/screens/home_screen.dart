import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/colors.dart';
import 'dashboard/dashboard_screen.dart';
import 'kanban/kanban_screen.dart';
import 'chat/chat_screen.dart';
import 'feed/feed_screen.dart';
import 'system/system_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String? _kanbanTeamId;
  String? _kanbanTeamName;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    api.configure(auth.serverUrl);
    api.ping();
    NotificationService().init(api);
  }

  void navigateToBoard(String teamId, String teamName) {
    setState(() {
      _kanbanTeamId = teamId;
      _kanbanTeamName = teamName;
      _tab = 3; // 칸반 탭
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final screens = [
      DashboardScreen(onTeamTap: navigateToBoard),
      const ChatScreen(),
      const FeedScreen(),
      _kanbanTeamId != null
          ? KanbanScreen(teamId: _kanbanTeamId!, teamName: _kanbanTeamName ?? '')
          : _noTeamSelected(theme),
      const SystemScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.border, 
              width: 0.5,
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: AppColors.backgroundElevated,
          indicatorColor: AppColors.brandBg,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, size: 22), 
              selectedIcon: Icon(Icons.dashboard, size: 22), 
              label: '대시보드',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_outlined, size: 22), 
              selectedIcon: Icon(Icons.chat, size: 22), 
              label: '유디',
            ),
            NavigationDestination(
              icon: Icon(Icons.rss_feed_outlined, size: 22), 
              selectedIcon: Icon(Icons.rss_feed, size: 22), 
              label: '피드',
            ),
            NavigationDestination(
              icon: Icon(Icons.view_kanban_outlined, size: 22), 
              selectedIcon: Icon(Icons.view_kanban, size: 22), 
              label: '칸반',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, size: 22), 
              selectedIcon: Icon(Icons.settings, size: 22), 
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }

  Widget _noTeamSelected(ThemeData theme) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: const Text('칸반보드'), 
      backgroundColor: AppColors.backgroundElevated, 
      elevation: 0,
    ),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          Icon(
            Icons.view_kanban_outlined, 
            size: 48, 
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            '대시보드에서 팀을 선택하세요', 
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() => _tab = 0),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(160, 40),
            ),
            child: const Text('대시보드로 이동'),
          ),
        ],
      ),
    ),
  );
}