using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace U2DIA.ServerManager.Services;

public class SettingsService
{
    private readonly string _filePath;
    private JsonObject _data;

    private static readonly JsonObject Defaults = new()
    {
        ["port"] = 5555,
        ["host"] = "127.0.0.1",
        ["startWithWindows"] = false,
        ["minimizeToTray"] = true,
        ["notifications"] = true
    };

    public SettingsService()
    {
        var appData = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "U2DIA.ServerManager");
        Directory.CreateDirectory(appData);
        _filePath = Path.Combine(appData, "settings.json");

        _data = Load();
    }

    public T Get<T>(string key, T defaultValue)
    {
        if (_data.TryGetPropertyValue(key, out var node) && node != null)
        {
            try { return node.GetValue<T>(); }
            catch { return defaultValue; }
        }

        if (Defaults.TryGetPropertyValue(key, out var defNode) && defNode != null)
        {
            try { return defNode.GetValue<T>(); }
            catch { return defaultValue; }
        }

        return defaultValue;
    }

    public void Set(string key, object value)
    {
        _data[key] = JsonSerializer.SerializeToNode(value);
        Save();
    }

    public string GetAllJson()
    {
        // Defaults 위에 사용자 설정 머지
        var merged = JsonNode.Parse(Defaults.ToJsonString())!.AsObject();
        foreach (var kv in _data)
        {
            merged[kv.Key] = kv.Value?.DeepClone();
        }
        return merged.ToJsonString();
    }

    public void SetMultiple(Dictionary<string, object> values)
    {
        foreach (var kv in values)
            _data[kv.Key] = JsonSerializer.SerializeToNode(kv.Value);
        Save();
    }

    private JsonObject Load()
    {
        try
        {
            if (File.Exists(_filePath))
            {
                var json = File.ReadAllText(_filePath);
                return JsonNode.Parse(json)?.AsObject() ?? new JsonObject();
            }
        }
        catch { }
        return new JsonObject();
    }

    private void Save()
    {
        var opts = new JsonSerializerOptions { WriteIndented = true };
        File.WriteAllText(_filePath, _data.ToJsonString(opts));
    }
}
