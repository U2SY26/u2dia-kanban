import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SseService {
  StreamController<Map<String, dynamic>>? _controller;
  http.Client? _client;
  bool _active = false;

  Stream<Map<String, dynamic>>? get stream => _controller?.stream;

  Future<void> connect(String url, {Map<String, String>? headers}) async {
    await disconnect();
    _active = true;
    _controller = StreamController<Map<String, dynamic>>.broadcast();
    _client = http.Client();
    _listenLoop(url, headers ?? {});
  }

  void _listenLoop(String url, Map<String, String> headers) async {
    while (_active) {
      try {
        final req = http.Request('GET', Uri.parse(url));
        req.headers.addAll({'Accept': 'text/event-stream', ...headers});
        final res = await _client!.send(req);
        final stream = res.stream.transform(utf8.decoder).transform(const LineSplitter());
        String dataBuffer = '';
        await for (final line in stream) {
          if (!_active) break;
          if (line.startsWith('data: ')) {
            dataBuffer = line.substring(6);
          } else if (line.isEmpty && dataBuffer.isNotEmpty) {
            try {
              final data = jsonDecode(dataBuffer) as Map<String, dynamic>;
              _controller?.add(data);
            } catch (_) {}
            dataBuffer = '';
          }
        }
      } catch (_) {
        if (!_active) break;
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> disconnect() async {
    _active = false;
    _client?.close();
    await _controller?.close();
    _controller = null;
    _client = null;
  }
}
