using System.IO;
using System.Windows;
using System.Windows.Input;
using Microsoft.Web.WebView2.Core;
using U2DIA.ServerManager.Services;
using U2DIA.ServerManager.Bridge;

namespace U2DIA.ServerManager;

public partial class MainWindow : Window
{
    private readonly PythonServerManager _serverManager;
    private readonly SettingsService _settings;
    private TrayService? _tray;
    private NotificationService? _notifications;
    private JsBridge? _bridge;

    public MainWindow()
    {
        InitializeComponent();

        _settings = new SettingsService();
        _serverManager = new PythonServerManager(_settings);

        Loaded += MainWindow_Loaded;
        Closing += MainWindow_Closing;
        StateChanged += MainWindow_StateChanged;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        var app = (App)Application.Current;

        // 트레이 아이콘 생성
        _tray = new TrayService(_serverManager, ShowWindow, QuitApp);

        // 서버 상태 변경 시 트레이 알림
        _serverManager.StateChanged += (state, msg) =>
        {
            Dispatcher.Invoke(() => _tray.UpdateMenu());
            if (state == "running")
            {
                _tray.ShowBalloon("서버 시작됨", $"포트 {_serverManager.Port}에서 실행 중");
                _notifications?.Connect();
            }
            else if (state == "stopped" || state == "error")
            {
                _notifications?.Disconnect();
            }
        };

        // WebView2 초기화
        var env = await CoreWebView2Environment.CreateAsync(
            userDataFolder: Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "U2DIA.ServerManager", "WebView2"));

        await WebView.EnsureCoreWebView2Async(env);

        // 보안 설정
        WebView.CoreWebView2.Settings.AreDevToolsEnabled = false;
        WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        WebView.CoreWebView2.Settings.AreBrowserAcceleratorKeysEnabled = false;
        WebView.CoreWebView2.Settings.IsStatusBarEnabled = false;

        // JS Bridge
        _bridge = new JsBridge(_serverManager, _settings, this);
        WebView.CoreWebView2.AddHostObjectToScript("nativeBridge", _bridge);

        // 서버 시작
        try
        {
            await _serverManager.StartAsync();
        }
        catch (Exception ex)
        {
            if (!app.LaunchedHidden)
                MessageBox.Show($"서버 시작 실패: {ex.Message}", "오류",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            else
                _tray.ShowBalloon("서버 시작 실패", ex.Message,
                    System.Windows.Forms.ToolTipIcon.Error);
        }

        // SSE 알림 서비스
        _notifications = new NotificationService(_settings, _tray);
        if (_serverManager.State == "running")
            _notifications.Connect();

        // UI 로드
        var port = _settings.Get<int>("port", 5555);
        WebView.CoreWebView2.Navigate($"http://localhost:{port}/");

        // 백그라운드 모드면 숨김
        if (app.LaunchedHidden)
            Hide();
    }

    private void MainWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        var app = (App)Application.Current;

        if (!app.IsQuitting && _settings.Get<bool>("minimizeToTray", true))
        {
            // 트레이로 최소화 (닫기 대신)
            e.Cancel = true;
            Hide();
            _tray?.ShowBalloon("백그라운드 실행 중",
                "트레이 아이콘을 더블 클릭하여 다시 열 수 있습니다.");
            return;
        }

        // 실제 종료
        _settings.Set("windowBounds", new
        {
            Left, Top, Width, Height,
            State = WindowState.ToString()
        });

        _notifications?.Dispose();
        _tray?.Dispose();
        _ = _serverManager.StopAsync();
    }

    private void MainWindow_StateChanged(object? sender, EventArgs e)
    {
        // WebView2에 창 상태 알림
        if (WebView.CoreWebView2 != null)
        {
            var state = WindowState.ToString().ToLower();
            WebView.CoreWebView2.ExecuteScriptAsync(
                $"window.dispatchEvent(new CustomEvent('windowStateChanged', {{detail: '{state}'}}))");
        }
    }

    private void ShowWindow()
    {
        Dispatcher.Invoke(() =>
        {
            Show();
            WindowState = WindowState.Normal;
            Activate();
            Focus();
        });
    }

    private void QuitApp()
    {
        Dispatcher.Invoke(() =>
        {
            var app = (App)Application.Current;
            app.IsQuitting = true;
            Close();
            app.Shutdown();
        });
    }

    // --- Title Bar ---

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
            ToggleMaximize();
        else
            DragMove();
    }

    private void BtnMinimize_Click(object sender, RoutedEventArgs e) =>
        WindowState = WindowState.Minimized;

    private void BtnMaximize_Click(object sender, RoutedEventArgs e) =>
        ToggleMaximize();

    private void BtnClose_Click(object sender, RoutedEventArgs e) =>
        Close();

    private void ToggleMaximize() =>
        WindowState = WindowState == WindowState.Maximized
            ? WindowState.Normal
            : WindowState.Maximized;
}
