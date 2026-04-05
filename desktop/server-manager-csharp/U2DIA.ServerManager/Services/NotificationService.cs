using System.IO;
using System.Net.Http;
using System.Text.Json;
using WinForms = System.Windows.Forms;

namespace U2DIA.ServerManager.Services;

public class NotificationService : IDisposable
{
    private readonly SettingsService _settings;
    private readonly TrayService _tray;
    private CancellationTokenSource? _cts;
    private Task? _listenTask;

    public bool Enabled { get; set; } = true;

    public NotificationService(SettingsService settings, TrayService tray)
    {
        _settings = settings;
        _tray = tray;
        Enabled = settings.Get<bool>("notifications", true);
    }

    public void Connect()
    {
        Disconnect();
        _cts = new CancellationTokenSource();
        _listenTask = ListenSSE(_cts.Token);
    }

    public void Disconnect()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;
        _listenTask = null;
    }

    private async Task ListenSSE(CancellationToken ct)
    {
        var port = _settings.Get<int>("port", 5555);
        var url = $"http://127.0.0.1:{port}/api/supervisor/events";

        while (!ct.IsCancellationRequested)
        {
            try
            {
                using var http = new HttpClient { Timeout = TimeSpan.FromMilliseconds(-1) };
                using var stream = await http.GetStreamAsync(url, ct);
                using var reader = new StreamReader(stream);

                while (!ct.IsCancellationRequested)
                {
                    var line = await reader.ReadLineAsync(ct);
                    if (line == null) break;
                    if (!line.StartsWith("data:")) continue;

                    var json = line[5..].Trim();
                    if (!Enabled || string.IsNullOrEmpty(json)) continue;

                    try
                    {
                        ProcessEvent(json);
                    }
                    catch { }
                }
            }
            catch (OperationCanceledException) { break; }
            catch
            {
                // 재연결 대기
                try { await Task.Delay(3000, ct); }
                catch (OperationCanceledException) { break; }
            }
        }
    }

    private void ProcessEvent(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (!root.TryGetProperty("type", out var typeEl)) return;
        var type = typeEl.GetString() ?? "";

        var (title, message, icon) = type switch
        {
            "team_created" => ("팀 생성", GetProp(root, "name", "새 팀"), WinForms.ToolTipIcon.Info),
            "ticket_created" => ("티켓 생성", GetProp(root, "title", "새 티켓"), WinForms.ToolTipIcon.Info),
            "ticket_claimed" => ("티켓 점유", $"{GetProp(root, "member_id", "에이전트")}가 작업 시작", WinForms.ToolTipIcon.Info),
            "status_changed" => ("상태 변경", GetProp(root, "message", "상태 변경됨"), WinForms.ToolTipIcon.Info),
            "ticket_status_changed" when GetProp(root, "status", "") == "Done"
                => ("티켓 완료", $"{GetProp(root, "ticket_id", "")} 완료", WinForms.ToolTipIcon.Info),
            "ticket_status_changed" when GetProp(root, "status", "") == "Blocked"
                => ("티켓 차단", $"{GetProp(root, "ticket_id", "")} 차단됨", WinForms.ToolTipIcon.Warning),
            "team_archived" => ("팀 아카이브", "모든 티켓 완료 — 자동 아카이브", WinForms.ToolTipIcon.Info),
            _ => (null, null, WinForms.ToolTipIcon.None)
        };

        if (title != null && message != null)
            _tray.ShowBalloon(title, message, icon);
    }

    private static string GetProp(JsonElement el, string key, string fallback)
    {
        if (el.TryGetProperty("data", out var data) && data.TryGetProperty(key, out var val))
            return val.GetString() ?? fallback;
        if (el.TryGetProperty(key, out var direct))
            return direct.GetString() ?? fallback;
        return fallback;
    }

    public void Dispose()
    {
        Disconnect();
    }
}
