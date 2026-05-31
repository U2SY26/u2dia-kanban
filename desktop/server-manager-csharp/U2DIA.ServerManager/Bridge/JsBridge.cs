using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using U2DIA.ServerManager.Services;

namespace U2DIA.ServerManager.Bridge;

[ClassInterface(ClassInterfaceType.AutoDual)]
[ComVisible(true)]
public class JsBridge
{
    private readonly PythonServerManager _server;
    private readonly SettingsService _settings;
    private readonly MainWindow _window;
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(5) };

    public JsBridge(PythonServerManager server, SettingsService settings, MainWindow window)
    {
        _server = server;
        _settings = settings;
        _window = window;
    }

    // --- Server ---
    public string ServerStart()
    {
        try { _server.StartAsync().Wait(); }
        catch (Exception ex) { return Error(ex.Message); }
        return _server.ToJson();
    }

    public string ServerStop()
    {
        try { _server.StopAsync().Wait(); }
        catch (Exception ex) { return Error(ex.Message); }
        return _server.ToJson();
    }

    public string ServerRestart()
    {
        try { _server.RestartAsync().Wait(); }
        catch (Exception ex) { return Error(ex.Message); }
        return _server.ToJson();
    }

    public string ServerStatus() => _server.ToJson();

    // --- Settings ---
    public string GetSettings() => _settings.GetAllJson();

    public string SetSettings(string json)
    {
        try
        {
            var values = JsonSerializer.Deserialize<Dictionary<string, object>>(json);
            if (values != null) _settings.SetMultiple(values);
            return Ok();
        }
        catch (Exception ex) { return Error(ex.Message); }
    }

    // --- Window ---
    public void WindowMinimize() =>
        _window.Dispatcher.Invoke(() => _window.WindowState = System.Windows.WindowState.Minimized);

    public void WindowMaximize() =>
        _window.Dispatcher.Invoke(() =>
            _window.WindowState = _window.WindowState == System.Windows.WindowState.Maximized
                ? System.Windows.WindowState.Normal
                : System.Windows.WindowState.Maximized);

    public void WindowClose() =>
        _window.Dispatcher.Invoke(() => _window.Close());

    // --- Startup ---
    public bool GetStartWithWindows() => StartupService.IsRegistered();

    public string SetStartWithWindows(bool enabled)
    {
        try
        {
            StartupService.Apply(enabled);
            _settings.Set("startWithWindows", enabled);
            return Ok();
        }
        catch (Exception ex) { return Error(ex.Message); }
    }

    // --- API Proxy (tokens, metrics, clients) ---
    public string ApiCall(string path, string method = "GET", string? body = null)
    {
        try
        {
            var port = _settings.Get<int>("port", 5555);
            var url = $"http://127.0.0.1:{port}{path}";
            var request = new HttpRequestMessage(new HttpMethod(method), url);
            if (body != null)
                request.Content = new StringContent(body, Encoding.UTF8, "application/json");

            var response = _http.Send(request);
            using var reader = new StreamReader(response.Content.ReadAsStream());
            return reader.ReadToEnd();
        }
        catch (Exception ex) { return Error(ex.Message); }
    }

    private static string Ok() => "{\"ok\":true}";
    private static string Error(string msg) => $"{{\"ok\":false,\"error\":\"{Escape(msg)}\"}}";
    private static string Escape(string s) => s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n");
}
