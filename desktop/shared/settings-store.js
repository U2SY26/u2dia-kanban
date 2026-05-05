const fs = require('fs');
const path = require('path');

class SettingsStore {
  constructor(userDataPath) {
    this.filePath = path.join(userDataPath, 'settings.json');
    this.data = this._defaults();
    this._load();
  }

  _defaults() {
    return {
      port: 5555,
      host: '127.0.0.1',
      pythonPath: 'python',
      autoStart: true,
      minimizeToTray: true,
      startWithWindows: false,
      notifications: true,
      windowBounds: null,
      lastView: 'board',
      allowRemoteAccess: false,
    };
  }

  _load() {
    try {
      if (fs.existsSync(this.filePath)) {
        const saved = JSON.parse(fs.readFileSync(this.filePath, 'utf-8'));
        this.data = { ...this.data, ...saved };
      }
    } catch (_) { /* keep defaults */ }
  }

  _save() {
    try {
      const dir = path.dirname(this.filePath);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(this.filePath, JSON.stringify(this.data, null, 2), 'utf-8');
    } catch (e) {
      console.error('Settings save failed:', e);
    }
  }

  get(key) { return this.data[key]; }

  set(key, value) {
    this.data[key] = value;
    this._save();
  }

  getAll() { return { ...this.data }; }

  setMultiple(obj) {
    Object.assign(this.data, obj);
    this._save();
  }
}

module.exports = SettingsStore;
