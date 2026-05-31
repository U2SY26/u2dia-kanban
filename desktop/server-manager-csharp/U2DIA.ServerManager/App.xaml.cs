using System.Windows;
using U2DIA.ServerManager.Services;


namespace U2DIA.ServerManager;

public partial class App : Application
{
    public bool IsQuitting { get; set; }

    // --hidden 플래그로 실행 시 백그라운드 모드
    public bool LaunchedHidden =>
        Environment.GetCommandLineArgs().Contains("--hidden");

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 시작 프로그램 설정 적용
        var settings = new SettingsService();
        StartupService.Apply(settings.Get<bool>("startWithWindows", false));

        if (LaunchedHidden)
        {
            // 백그라운드 모드: 창 없이 트레이만
            // MainWindow는 생성하되 숨김
            var win = new MainWindow();
            MainWindow = win;
            // 창을 보여주지 않음 — 트레이에서 "매니저 열기" 클릭 시 Show()
        }
    }
}
