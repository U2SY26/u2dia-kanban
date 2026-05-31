# 신규 레포 칸반 연결 가이드

**버전**: 1.0  
**작성일**: 2026-03-22  
**대상**: U2DIA AI 칸반보드(http://localhost:5555)에 새 레포를 연결하는 방법

---

## 1단계: 토큰 발급

서버에 신규 레포 전용 인증 토큰을 발급한다.

```python
import urllib.request, json

req = urllib.request.Request(
    'http://localhost:5555/api/tokens',
    data=json.dumps({'name': 'REPO_NAME', 'permissions': 'agent'}).encode(),
    headers={'Content-Type': 'application/json'},
    method='POST'
)
with urllib.request.urlopen(req) as r:
    result = json.loads(r.read())

token = result.get('token_key')
print(f"발급된 토큰: {token}")
```

또는 curl로:
```bash
curl -s -X POST http://localhost:5555/api/tokens \
  -H 'Content-Type: application/json' \
  -d '{"name": "REPO_NAME", "permissions": "agent"}'
```

---

## 2단계: .mcp.json 생성

레포 루트에 `.mcp.json` 파일을 생성한다.

```json
{
  "mcpServers": {
    "kanban": {
      "type": "url",
      "url": "http://localhost:5555/mcp",
      "headers": {
        "Authorization": "Bearer 발급된_토큰값"
      }
    }
  }
}
```

기존 .mcp.json이 있으면 `mcpServers` 아래에 `"kanban"` 항목만 추가:
```bash
# 파이썬으로 안전하게 추가
python3 << 'EOF'
import json

with open('/path/to/repo/.mcp.json', 'r') as f:
    mcp = json.load(f)

mcp.setdefault('mcpServers', {})['kanban'] = {
    "type": "url",
    "url": "http://localhost:5555/mcp",
    "headers": {"Authorization": "Bearer 발급된_토큰값"}
}

with open('/path/to/repo/.mcp.json', 'w') as f:
    json.dump(mcp, f, indent=4, ensure_ascii=False)
EOF
```

---

## 3단계: .claude/settings.json 설정

`.claude/settings.json`에 MCP 자동 활성화 옵션을 추가한다.

```bash
mkdir -p /path/to/repo/.claude

python3 << 'EOF'
import json, os

settings_file = '/path/to/repo/.claude/settings.json'
settings = {}
if os.path.exists(settings_file):
    with open(settings_file) as f:
        settings = json.load(f)

settings['enableAllProjectMcpServers'] = True

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
print("완료!")
EOF
```

---

## 4단계: 별명 등록 (2글자 단축어)

칸반 서버에 프로젝트 별명을 등록해서 텔레그램 구어체 명령에서 사용 가능하게 한다.

```python
import urllib.request, json

data = {
    'alias': '별명',          # 2글자 한국어 권장 (예: "링코")
    'name': 'REPO_NAME',      # 디렉토리 이름 (예: "LINKO")
    'path': '/home/u2dia/github/REPO_NAME'
}

req = urllib.request.Request(
    'http://localhost:5555/api/projects',
    data=json.dumps(data).encode(),
    headers={'Content-Type': 'application/json'},
    method='POST'
)
with urllib.request.urlopen(req) as r:
    print(json.loads(r.read()))
```

또는 텔레그램 봇에서:
```
/alias 별명|REPO_NAME|/home/u2dia/github/REPO_NAME
```

---

## 5단계: CLAUDE.md에 MCP 설정 섹션 추가

`.claude/CLAUDE.md` (또는 프로젝트 루트 `CLAUDE.md`)에 다음 섹션을 추가한다:

```markdown
## 칸반보드 연동

이 프로젝트는 U2DIA 칸반보드와 MCP로 연결되어 있습니다.

- 칸반 서버: http://localhost:5555
- MCP 도구 17개 사용 가능 (kanban_ticket_create, kanban_board_get 등)
- 모든 작업 시작 전 `kanban_ticket_claim`으로 티켓 클레임 필수

### 에이전트 헌법 4원칙
1. 투명성: 모든 작업은 칸반보드에 기록
2. 원자적 완결성: 하나의 티켓 = 하나의 에이전트 = 하나의 세션  
3. 의존성 무결성: 선행 작업 미완료 시 착수 불가
4. 협업적 자율성: 방법론은 에이전트의 자유
```

---

## 6단계: 검증

```bash
# 서버 연결 확인
curl -s http://localhost:5555/api/health

# 토큰 인증 확인
curl -s http://localhost:5555/mcp \
  -H 'Authorization: Bearer 발급된_토큰값' \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

# 프로젝트 목록에 등록됐는지 확인
curl -s http://localhost:5555/api/projects | python3 -m json.tool
```

---

## 텔레그램 봇 구어체 사용 예시

레포가 등록되면 텔레그램 봇에서 별명으로 바로 대화할 수 있다:

```
"링코 어때?"
→ LINKO 프로젝트 상태 자동 조회

"글로에 로그인 기능 추가해줘"
→ PMI-LINK-GLOBAL에 티켓 자동 생성 후 에이전트 배치

"헥사 진행 상황 보고해"
→ Hexacotest 팀 진행률 보고

"이커 에이전트 깨워"
→ e-commerceAI 프로젝트 에이전트 스폰 및 클레임

"칸반 서버 상태"
→ U2DIA-KANBAN-BOARD 프로젝트 현황 + 전체 서버 상태
```

---

## 현재 등록된 레포 및 별명

| 별명 | 레포명 | 경로 |
|------|--------|------|
| 성경 | Bible | /home/u2dia/github/Bible |
| 계약 | CLM2 | /home/u2dia/github/CLM2 |
| 3웹 | 3dweb | /home/u2dia/github/3dweb |
| 견적 | Estimate | /home/u2dia/github/Estimate |
| 팔십 | Followship | /home/u2dia/github/Followship |
| 헥사 | Hexacotest | /home/u2dia/github/Hexacotest |
| 이박 | LEEPARK | /home/u2dia/github/LEEPARK |
| 링코 | LINKO | /home/u2dia/github/LINKO |
| 링콘 | LINKON | /home/u2dia/github/LINKON |
| 엠씨 | MCS | /home/u2dia/github/MCS |
| AI피 | PMI-AIP | /home/u2dia/github/PMI-AIP |
| 글로 | PMI-LINK-GLOBAL | /home/u2dia/github/PMI-LINK-GLOBAL |
| 피링 | PMI_Link | /home/u2dia/github/PMI_Link |
| 칸반 | U2DIA-KANBAN-BOARD | /home/u2dia/github/U2DIA-KANBAN-BOARD |
| U홈 | U2DIA_HOME | /home/u2dia/github/U2DIA_HOME |
| 메타 | U2DIA_METAVERS | /home/u2dia/github/U2DIA_METAVERS |
| 하네 | advanced-harness | /home/u2dia/github/advanced-harness |
| 크롬 | chrome-devtools-mcp | /home/u2dia/github/chrome-devtools-mcp |
| 쿠팡 | cupang_api | /home/u2dia/github/cupang_api |
| 이커 | e-commerceAI | /home/u2dia/github/e-commerceAI |
| 라이 | life | /home/u2dia/github/life |
| 오클 | openclaw | /home/u2dia/github/openclaw |
| 플너 | planner | /home/u2dia/github/planner |
| 사랩 | science-lab-flutter | /home/u2dia/github/science-lab-flutter |

---

## 빠른 스크립트 (원클릭 연결)

새 레포를 단번에 칸반에 연결하는 스크립트:

```bash
#!/bin/bash
# usage: ./connect_kanban.sh REPO_NAME 별명
REPO=$1
ALIAS=$2
REPO_PATH="/home/u2dia/github/$REPO"

if [ ! -d "$REPO_PATH" ]; then
  echo "레포 경로가 없습니다: $REPO_PATH"
  exit 1
fi

# 1. 토큰 발급
TOKEN=$(python3 -c "
import urllib.request, json
req = urllib.request.Request('http://localhost:5555/api/tokens',
    data=json.dumps({'name': '$REPO', 'permissions': 'agent'}).encode(),
    headers={'Content-Type': 'application/json'}, method='POST')
with urllib.request.urlopen(req) as r:
    result = json.loads(r.read())
print(result.get('token_key', ''))
")

echo "토큰: $TOKEN"

# 2. .mcp.json 생성
python3 -c "
import json
mcp = {'mcpServers': {'kanban': {'type': 'url', 'url': 'http://localhost:5555/mcp', 'headers': {'Authorization': 'Bearer $TOKEN'}}}}
with open('$REPO_PATH/.mcp.json', 'w') as f:
    json.dump(mcp, f, indent=4)
print('.mcp.json 생성 완료')
"

# 3. .claude/settings.json 설정
mkdir -p "$REPO_PATH/.claude"
python3 -c "
import json, os
sf = '$REPO_PATH/.claude/settings.json'
s = {}
if os.path.exists(sf):
    with open(sf) as f: s = json.load(f)
s['enableAllProjectMcpServers'] = True
with open(sf, 'w') as f: json.dump(s, f, indent=2)
print('settings.json 완료')
"

# 4. 별명 등록
python3 -c "
import urllib.request, json
data = {'alias': '$ALIAS', 'name': '$REPO', 'path': '$REPO_PATH'}
req = urllib.request.Request('http://localhost:5555/api/projects',
    data=json.dumps(data).encode(), headers={'Content-Type': 'application/json'}, method='POST')
with urllib.request.urlopen(req) as r:
    print('별명 등록:', json.loads(r.read()))
"

echo "✓ $REPO ($ALIAS) 칸반 연결 완료!"
```

사용 예:
```bash
chmod +x connect_kanban.sh
./connect_kanban.sh MyNewRepo 새프
```
