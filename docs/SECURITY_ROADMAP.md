# 보안 강화 로드맵 — Electron → C# + WebView2 전환

**Version**: 1.0.0
**Last Updated**: 2026-03-16
**Status**: PLANNING

---

## 배경

현재 데스크톱 앱 (Server Manager, Frontend)은 Electron 기반이며, 다음 보안 한계가 있음:
- JS 소스 완전 노출 (asar 해제 시 즉시 확인 가능)
- DevTools 비활성화해도 우회 가능
- 메모리에서 라이선스 키 스크래핑 가능
- 코드 서명 없이 SmartScreen 경고 발생
- 앱 크기 ~150MB (Chromium 번들)

**목표**: C# (WPF + WebView2) 네이티브 앱으로 전환하여 보안 수준을 엔터프라이즈급으로 격상

---

## 현재 Electron 아키텍처

```
desktop/
├── server-manager-app/     # Electron 앱 1: 서버 관리
│   ├── main.js             # 메인 프로세스 (서버 시작/중지, 트레이, IPC)
│   ├── preload.js          # 컨텍스트 브릿지
│   └── renderer/           # HTML/CSS/JS UI (서버/토큰/클라이언트/메트릭/설정)
├── frontend/               # Electron 앱 2: 칸반보드 뷰어
│   ├── main.js             # 메인 프로세스 (서버 연결)
│   ├── preload.js          # 컨텍스트 브릿지
│   └── renderer/           # HTML/CSS/JS UI
└── shared/                 # 공유 모듈
    ├── settings-store.js   # JSON 파일 기반 설정 관리
    ├── server-manager.js   # Python 서버 프로세스 관리
    └── notification-manager.js  # SSE 기반 Windows 알림
```

## 목표 C# 아키텍처

```
desktop-csharp/
├── U2DIA.ServerManager/           # WPF + WebView2 앱
│   ├── App.xaml                   # 앱 엔트리
│   ├── MainWindow.xaml            # WebView2 호스트 + 커스텀 타이틀바
│   ├── Services/
│   │   ├── PythonServerManager.cs # Process 관리 (server.py 시작/중지)
│   │   ├── SettingsService.cs     # 설정 (DPAPI 암호화 지원)
│   │   ├── NotificationService.cs # SSE + Windows ToastNotification
│   │   └── LicenseService.cs      # SecureString + DPAPI 보호
│   ├── Bridge/
│   │   └── JsBridge.cs            # WebView2 ↔ C# 통신 (IPC 대체)
│   └── Assets/
│       └── icon.ico
├── U2DIA.ServerManager.Tests/     # 유닛 테스트
└── build/
    ├── ConfuserEx.crproj          # 난독화 설정
    └── codesign.ps1               # EV 서명 스크립트
```

---

## 보안 강화 5단계

### Phase 1: EV Code Signing (우선순위 1)

| 항목 | 내용 |
|------|------|
| **비용** | ~$300/년 (DigiCert, Sectigo 등) |
| **효과** | SmartScreen 즉시 통과, 기업 배포 신뢰도 |
| **적용 대상** | `.exe`, `.dll` 모든 바이너리 |
| **구현** | `signtool.exe sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f cert.pfx` |

**티켓 분해:**
- T1-1: EV 인증서 구매 및 HSM/토큰 설정
- T1-2: CI/CD 서명 파이프라인 구축 (`build/codesign.ps1`)
- T1-3: 서명 검증 테스트 (Windows Defender, SmartScreen)

---

### Phase 2: C# 난독화 — ConfuserEx (우선순위 2)

| 항목 | 내용 |
|------|------|
| **비용** | 무료 (오픈소스) |
| **효과** | ILSpy/dnSpy 디컴파일 방지 |
| **수준** | Maximum (Control Flow + Rename + Constants + Anti-Tamper) |

**ConfuserEx 설정 (`build/ConfuserEx.crproj`):**
```xml
<project baseDir="..\bin\Release\net8.0-windows">
  <rule pattern="true">
    <protection id="anti ildasm" />
    <protection id="anti tamper" />
    <protection id="constants" />
    <protection id="ctrl flow" />
    <protection id="rename" />
    <protection id="ref proxy" />
  </rule>
</project>
```

**티켓 분해:**
- T2-1: ConfuserEx 빌드 통합 (MSBuild post-build event)
- T2-2: 난독화 전/후 기능 테스트
- T2-3: Anti-Tamper 검증 (바이너리 변조 감지)

---

### Phase 3: WebView2 DevTools 비활성화 (우선순위 3)

| 항목 | 내용 |
|------|------|
| **비용** | 코드 1줄 |
| **효과** | F12, Ctrl+Shift+I로 UI 소스 추출 차단 |

**구현:**
```csharp
webView.CoreWebView2.Settings.AreBrowserAcceleratorKeysEnabled = false;
webView.CoreWebView2.Settings.AreDevToolsEnabled = false;
```

**추가 보호:**
```csharp
// 컨텍스트 메뉴 비활성화
webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
// 소스 보기 차단
webView.CoreWebView2.Settings.IsGeneralAutofillEnabled = false;
```

**티켓 분해:**
- T3-1: WebView2 보안 설정 적용
- T3-2: 키보드 단축키 후킹 (Ctrl+U 등 차단)

---

### Phase 4: 메모리 보호 — 라이선스 키 (우선순위 4)

| 항목 | 내용 |
|------|------|
| **비용** | 중 (개발 시간) |
| **효과** | 메모리 덤프에서 키 추출 방지 |

**구현 전략:**
```csharp
// 1. SecureString으로 메모리 내 암호화
SecureString licenseKey = new SecureString();
foreach (char c in rawKey) licenseKey.AppendChar(c);
licenseKey.MakeReadOnly();

// 2. DPAPI로 디스크 저장 시 암호화
byte[] encrypted = ProtectedData.Protect(
    Encoding.UTF8.GetBytes(rawKey),
    entropy,
    DataProtectionScope.CurrentUser
);

// 3. 사용 후 즉시 메모리 제로화
Array.Clear(rawKeyBytes, 0, rawKeyBytes.Length);
GC.Collect();
```

**티켓 분해:**
- T4-1: `LicenseService.cs` — SecureString + DPAPI 구현
- T4-2: 설정 파일 암호화 마이그레이션 (JSON → encrypted)
- T4-3: 메모리 스크래핑 테스트 (Process Hacker 검증)

---

### Phase 5: SOC 2 Type II (우선순위 5)

| 항목 | 내용 |
|------|------|
| **비용** | $15K+ |
| **효과** | 대기업 계약 필수 조건 충족 |
| **기간** | 6~12개월 |

**준비 항목:**
- 접근 제어 로그 (누가 언제 어떤 데이터에 접근)
- 변경 관리 프로세스 (코드 리뷰, 승인 흐름)
- 인시던트 대응 절차
- 암호화 정책 (전송 중 + 저장 시)
- 정기 보안 감사

**티켓 분해:**
- T5-1: 감사 로그 시스템 구현 (server.py)
- T5-2: 보안 정책 문서화
- T5-3: 외부 감사 업체 선정 및 계약

---

## Electron → C# 마이그레이션 매핑

| Electron (현재) | C# + WebView2 (목표) | 비고 |
|-----------------|---------------------|------|
| `main.js` BrowserWindow | `MainWindow.xaml` + WebView2 | 커스텀 타이틀바 유지 |
| `preload.js` contextBridge | `JsBridge.cs` AddHostObjectToScript | 동일한 API 시그니처 |
| `ipcMain.handle()` | `webView.CoreWebView2.WebMessageReceived` | JSON 메시지 기반 |
| `shared/server-manager.js` | `PythonServerManager.cs` Process 관리 | 동일 로직 |
| `shared/settings-store.js` | `SettingsService.cs` + DPAPI | 암호화 추가 |
| `shared/notification-manager.js` | `NotificationService.cs` ToastNotification | Windows 네이티브 |
| `electron-builder` NSIS | MSBuild + MSIX/WiX | 스토어 배포 가능 |
| `node_modules` ~150MB | .NET 8 self-contained ~30MB | 5배 축소 |

### JsBridge 통신 설계

**현재 Electron (preload.js):**
```javascript
contextBridge.exposeInMainWorld('api', {
  startServer: () => ipcRenderer.invoke('server:start'),
  getSettings: () => ipcRenderer.invoke('settings:get'),
  // ...
});
```

**목표 C# (JsBridge.cs):**
```csharp
[ClassInterface(ClassInterfaceType.AutoDual)]
[ComVisible(true)]
public class JsBridge {
    public string StartServer() => _serverManager.Start().Result.ToJson();
    public string GetSettings() => _settingsService.GetAll().ToJson();
    // 동일한 API → renderer JS 수정 최소화
}

// WebView2에 등록
webView.CoreWebView2.AddHostObjectToScript("api", new JsBridge());
```

**Renderer JS (변경 없음):**
```javascript
// Electron: window.api.startServer()
// C#: window.chrome.webview.hostObjects.api.StartServer()
// → 얇은 어댑터 레이어로 호환
```

---

## 실행 계획

### 칸반보드 팀 구성

**팀명**: `TEAM-SECURITY-NATIVE`
**project_group**: `agents_team`

| 티켓 | 제목 | 우선순위 | 의존성 | 예상 시간 |
|------|------|----------|--------|-----------|
| T-01 | C# WPF + WebView2 프로젝트 스캐폴딩 | Critical | — | 2h |
| T-02 | PythonServerManager.cs — 서버 프로세스 관리 | High | T-01 | 3h |
| T-03 | SettingsService.cs — 설정 관리 + DPAPI | High | T-01 | 2h |
| T-04 | JsBridge.cs — WebView2 ↔ C# 통신 | High | T-01 | 3h |
| T-05 | MainWindow.xaml — 커스텀 타이틀바 + WebView2 | High | T-04 | 2h |
| T-06 | NotificationService.cs — SSE + Toast | Medium | T-02 | 2h |
| T-07 | WebView2 보안 설정 (DevTools 차단) | Medium | T-05 | 30m |
| T-08 | LicenseService.cs — SecureString + DPAPI | Medium | T-03 | 3h |
| T-09 | ConfuserEx 난독화 빌드 파이프라인 | Medium | T-01 | 2h |
| T-10 | MSIX/WiX 인스톨러 + EV 서명 | Low | T-09 | 3h |
| T-11 | 통합 테스트 + Electron 기능 패리티 확인 | Low | T-02~T-08 | 4h |
| T-12 | 감사 로그 시스템 (SOC 2 준비) | Low | T-02 | 3h |

**병렬 실행 그룹:**
- **Group A** (T-02, T-03 병렬): 서버 관리 + 설정 — T-01 완료 후 동시 시작
- **Group B** (T-04 → T-05 → T-07): 브릿지 → UI → 보안 — 순차
- **Group C** (T-06, T-08 병렬): 알림 + 라이선스 — Group A 완료 후
- **Group D** (T-09 → T-10): 난독화 → 서명 — 독립 진행 가능
- **Group E** (T-11, T-12): 최종 검증 — 모든 그룹 완료 후

```
T-01 ─┬─ T-02 ──┬── T-06 ──┐
      │         │           │
      ├─ T-03 ──┼── T-08 ──┼── T-11
      │         │           │
      └─ T-04 ──┴── T-05 ──┴── T-07
                                │
T-09 ──── T-10 ────────────────┘
                                │
                            T-12
```

---

## 리스크 및 완화

| 리스크 | 영향 | 완화 |
|--------|------|------|
| WebView2 미설치 PC | 앱 실행 불가 | Evergreen Bootstrapper 내장 |
| renderer JS 호환성 | UI 깨짐 | 어댑터 레이어 + E2E 테스트 |
| .NET 8 런타임 의존 | 설치 필요 | self-contained 배포 |
| ConfuserEx .NET 8 호환 | 난독화 실패 | .NET Framework fallback 또는 Babel 대안 |

---

## 성공 지표

- [ ] SmartScreen 경고 없이 설치 완료
- [ ] ILSpy로 코드 디컴파일 불가
- [ ] F12/DevTools 완전 차단
- [ ] Process Hacker에서 라이선스 키 미노출
- [ ] Electron 대비 앱 크기 80% 감소 (150MB → 30MB)
- [ ] 기존 모든 기능 100% 동작 (패리티)
