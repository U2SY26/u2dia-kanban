import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class ArchivesScreen extends StatefulWidget {
  const ArchivesScreen({super.key});

  @override
  State<ArchivesScreen> createState() => _ArchivesScreenState();
}

class _ArchivesScreenState extends State<ArchivesScreen> {
  List<Map<String, dynamic>> _archives = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = context.read<ApiService>();
    final archives = await api.getArchives();
    if (mounted) setState(() { _archives = archives; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('아카이브', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF161b22),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF30363d)),
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _archives.isEmpty
              ? const Center(child: Text('아카이브된 팀이 없습니다', style: TextStyle(color: Color(0xFF8b949e))))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _archives.length,
                    itemBuilder: (_, i) {
                      final t = _archives[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161b22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF30363d)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.archive_outlined, color: Color(0xFF8b949e), size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t['name'] ?? '', style: const TextStyle(
                                  color: Color(0xFFe6edf3), fontSize: 13, fontWeight: FontWeight.w600,
                                )),
                                if (t['description']?.isNotEmpty == true)
                                  Text(t['description'], style: const TextStyle(color: Color(0xFF8b949e), fontSize: 11)),
                              ],
                            )),
                            Text(
                              t['archived_at']?.toString().substring(0, 10) ?? '',
                              style: const TextStyle(color: Color(0xFF8b949e), fontSize: 10),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
