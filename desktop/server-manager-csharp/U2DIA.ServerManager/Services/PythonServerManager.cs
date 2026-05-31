using System.Diagnostics;
using System.IO;
using System.Net.Http;

namespace U2DIA.ServerManager.Services;

public class PythonServerManager
{
    private readonly SettingsService _settings;
    private Process? _process;

    public string State { get; private set; } = "stopped";
    public int Port => _settings.Get<int>("port", 5555);
    public string Host => _settings.Get<string>("host", "127.0.0.1");

    public event Action<string, string>? StateChanged;
    public event Action<string>? LogReceived;

    public PythonServerManager(SettingsService settings)
    {
        _settings = settings;
    }

    public async Task StartAsync()
    {
        if (State == "running") return;

        State = "starting";
        StateChanged?.Invoke(State, "서버 시작 중...");

        var serverPy = FindServerPy();
        if (string.IsNullOrEmpty(serverPy))
            throw new FileNotFoundException("server.py를 찾을 수 없습니다.");

        _process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "python",
                Arguments = $"\"{serverPy}\" --port {Port} --host {Host} --no-browser",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(serverPy)!
            },
            EnableRaisingEvents = true
        };

        _process.OutputDataReceived += (_, e) =>
        {
            if (e.Data != null) LogReceived?.Invoke(e.Data);
        };
        _process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data != null) LogReceived?.Invoke($"[ERR] {e.Data}");
        };
        _process.Exited += (_, _) =>
        {
            State = "stopped";
            StateChanged?.Invoke(State, "서버 종료됨");
        };

        _process.Start();
        _process.BeginOutputReadLine();
        _process.BeginErrorReadLine();

        // 서버가 준비될 때까지 대기 (최대 10초)
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
        for (int i = 0; i < 20; i++)
        {
            await Task.Delay(500);
            try
            {
                var resp = await http.GetAsync($"http://{Host}:{Port}/api/supervisor/stats");
                if (resp.IsSuccessStatusCode)
                {
                    State = "running";
                    StateChanged?.Invoke(State, $"서버 실행 중 (포트 {Port})");
                    return;
                }
            }
            catch { }
        }

        State = "error";
        StateChanged?.Invoke(State, "서버 응답 없음");
        throw new TimeoutException("서버가 10초 내에 응답하지 않습니다.");
    }

    public async Task StopAsync()
    {
        if (_process == null || _process.HasExited) return;

        try
        {
            // 먼저 정상 종료 시도
            _process.Kill(entireProcessTree: true);
            await _process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
        }
        catch { }
        finally
        {
            _process?.Dispose();
            _process = null;
            State = "stopped";
            StateChanged?.Invoke(State, "서버 정지됨");
        }
    }

    public async Task RestartAsync()
    {
        await StopAsync();
        await Task.Delay(1000);
        await StartAsync();
    }

    public string ToJson()
    {
        return $"{{\"state\":\"{State}\",\"port\":{Port},\"host\":\"{Host}\"}}";
    }

    private string? FindServerPy()
    {
        // 1. 실행 파일 옆 Resources/server.py
        var exeDir = AppDomain.CurrentDomain.BaseDirectory;
        var candidate = Path.Combine(exeDir, "Resources", "server.py");
        if (File.Exists(candidate)) return candidate;

        // 2. 개발 모드: 프로젝트 루트의 server.py
        var devPath = Path.GetFullPath(Path.Combine(exeDir, "..", "..", "..", "..", "..", "..", "server.py"));
        if (File.Exists(devPath)) return devPath;

        // 3. E:\agents_team\server.py (하드코딩 fallback)
        if (File.Exists(@"E:\agents_team\server.py")) return @"E:\agents_team\server.py";

        return null;
    }
}
