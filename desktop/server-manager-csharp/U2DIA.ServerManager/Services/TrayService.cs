using System.Drawing;
using System.IO;
using System.Windows;
using WinForms = System.Windows.Forms;

namespace U2DIA.ServerManager.Services;

public class TrayService : IDisposable
{
    private readonly WinForms.NotifyIcon _trayIcon;
    private readonly PythonServerManager _server;
    private readonly Action _showWindow;
    private readonly Action _quitApp;

    public TrayService(PythonServerManager server, Action showWindow, Action quitApp)
    {
        _server = server;
        _showWindow = showWindow;
        _quitApp = quitApp;

        _trayIcon = new WinForms.NotifyIcon
        {
            Text = "U2DIA Server Manager",
            Icon = LoadIcon(),
            Visible = true
        };

        _trayIcon.DoubleClick += (_, _) => _showWindow();
        _server.StateChanged += (state, _) => UpdateMenu();

        UpdateMenu();
    }

    public void ShowBalloon(string title, string message, WinForms.ToolTipIcon icon = WinForms.ToolTipIcon.Info)
    {
        _trayIcon.ShowBalloonTip(3000, title, message, icon);
    }

    public void UpdateMenu()
    {
        var isRunning = _server.State == "running";
        var stateText = _server.State switch
        {
            "running" => $"실행 중 (포트 {_server.Port})",
            "starting" => "시작 중...",
            "stopped" => "정지됨",
            "error" => "오류",
            _ => "알 수 없음"
        };

        _trayIcon.ContextMenuStrip = new WinForms.ContextMenuStrip();
        var items = _trayIcon.ContextMenuStrip.Items;

        var statusItem = items.Add($"서버: {stateText}");
        statusItem.Enabled = false;

        items.Add(new WinForms.ToolStripSeparator());

        items.Add("매니저 열기", null, (_, _) => _showWindow());

        items.Add(new WinForms.ToolStripSeparator());

        var startItem = items.Add("서버 시작", null, async (_, _) =>
        {
            try { await _server.StartAsync(); }
            catch (Exception ex) { ShowBalloon("오류", ex.Message, WinForms.ToolTipIcon.Error); }
        });
        startItem.Enabled = !isRunning && _server.State != "starting";

        var restartItem = items.Add("서버 재시작", null, async (_, _) =>
        {
            try { await _server.RestartAsync(); }
            catch (Exception ex) { ShowBalloon("오류", ex.Message, WinForms.ToolTipIcon.Error); }
        });
        restartItem.Enabled = isRunning;

        var stopItem = items.Add("서버 정지", null, async (_, _) =>
        {
            try { await _server.StopAsync(); }
            catch (Exception ex) { ShowBalloon("오류", ex.Message, WinForms.ToolTipIcon.Error); }
        });
        stopItem.Enabled = isRunning;

        items.Add(new WinForms.ToolStripSeparator());

        items.Add("종료", null, (_, _) => _quitApp());

        // 트레이 툴팁 업데이트
        _trayIcon.Text = $"U2DIA Server Manager — {stateText}";
    }

    private static Icon LoadIcon()
    {
        // 실행 파일 옆 Assets/tray-icon.ico 또는 기본 아이콘
        var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Assets", "tray-icon.ico");
        if (File.Exists(iconPath))
            return new Icon(iconPath);

        // PNG → Icon 시도
        var pngPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "..", "assets", "tray-icon.png");
        if (File.Exists(pngPath))
        {
            using var bmp = new Bitmap(pngPath);
            return Icon.FromHandle(bmp.GetHicon());
        }

        // 기본: 파란색 16x16 아이콘 생성
        using var defaultBmp = new Bitmap(16, 16);
        using var g = Graphics.FromImage(defaultBmp);
        g.FillEllipse(Brushes.DodgerBlue, 1, 1, 14, 14);
        return Icon.FromHandle(defaultBmp.GetHicon());
    }

    public void Dispose()
    {
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
    }
}
