# U2DIA Kanban Board E2E 테스트

서버, Supervisor 파이프라인, CLI Worker, Ollama, Flutter 빌드를 전체 검증합니다.
인자: `server` `supervisor` `cli` `ollama` `build` `deploy` 또는 빈값(전체)

아래 Bash 스크립트를 실행하세요. 실패 항목이 있으면 원인을 파악하고 수정한 뒤 해당 Phase만 재실행합니다.

```bash
cd /home/u2dia/github/U2DIA-KANBAN-BOARD
P=0; F=0

test_pass() { P=$((P+1)); }
test_fail() { F=$((F+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  U2DIA Kanban Board E2E ($(date '+%H:%M:%S'))"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\nPhase 1: 서버"
R=$(curl -s http://localhost:5555/api/teams) && echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'✅ 1-1 서버 {d[\"count\"]}팀')" && test_pass || { echo "❌ 1-1 서버"; test_fail; }
R=$(curl -s http://localhost:5555/api/projects/goals) && echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'✅ 1-2 프로젝트 {len(d.get(\"projects\",[]))}개')" && test_pass || { echo "❌ 1-2"; test_fail; }
R=$(curl -s http://localhost:5555/api/system/metrics) && echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); m=d.get('metrics',{}); print(f'✅ 1-3 CPU:{m.get(\"cpu_percent\")}% RAM:{m.get(\"memory_percent\")}%')" && test_pass || { echo "❌ 1-3"; test_fail; }

echo -e "\nPhase 2: Supervisor"
R=$(curl -s http://localhost:5555/api/supervisor/pipeline) && echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'✅ 2-1 파이프라인 {d[\"health\"]} {d[\"completion_rate\"]}%')" && test_pass || { echo "❌ 2-1"; test_fail; }
R=$(curl -s http://localhost:5555/api/supervisor/review/stats) && echo "$R" | python3 -c "import sys,json; s=json.load(sys.stdin).get('stats',{}); print(f'✅ 2-2 QA 총:{s.get(\"total_reviews\",0)} 평균:{s.get(\"avg_score\",0)}')" && test_pass || { echo "❌ 2-2"; test_fail; }
R=$(curl -s http://localhost:5555/api/agent/status) && echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'✅ 2-3 에이전트 {d.get(\"ollama_model\",\"\")}')" && test_pass || { echo "❌ 2-3"; test_fail; }
grep -q "산출물 없이 통과 시도" server.py && { echo "✅ 2-4 산출물 검증"; test_pass; } || { echo "❌ 2-4"; test_fail; }
grep -q "rework_count >= 3" server.py && { echo "✅ 2-5 재작업 3회 제한"; test_pass; } || { echo "❌ 2-5"; test_fail; }

echo -e "\nPhase 3: CLI"
R=$(curl -s http://localhost:5555/api/cli/models) && echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'✅ 3-1 모델 {len(d[\"models\"])}개')" && test_pass || { echo "❌ 3-1"; test_fail; }
R=$(curl -s http://localhost:5555/api/cli/stats) && echo "$R" | python3 -c "import sys,json; assert json.load(sys.stdin).get('ok'); print('✅ 3-2 CLI 통계')" && test_pass || { echo "❌ 3-2"; test_fail; }

echo -e "\nPhase 4: Ollama"
R=$(curl -s http://localhost:11434/api/tags) && echo "$R" | python3 -c "import sys,json; m=json.load(sys.stdin).get('models',[]); print(f'✅ 4-1 Ollama {len(m)}개')" && test_pass || { echo "❌ 4-1 Ollama 꺼짐"; test_fail; }
R=$(curl -s -X POST http://localhost:5555/api/agent/chat -H 'Content-Type: application/json' -d '{"message":"팀수","session_id":"e2e"}' --max-time 30) && echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('response'); print(f'✅ 4-2 유디 대화 {d.get(\"backend\",\"\")}')" && test_pass || { echo "❌ 4-2"; test_fail; }

echo -e "\nPhase 5: SSE"
R=$(timeout 10 curl -s -N -X POST http://localhost:5555/api/agent/chat/stream -H 'Content-Type: application/json' -d '{"message":"ping","session_id":"e2e-sse"}' 2>/dev/null | head -c 200); echo "$R" | grep -q "data:" && { echo "✅ 5-1 SSE"; test_pass; } || { echo "❌ 5-1 SSE"; test_fail; }

echo -e "\nPhase 6: 빌드"
[ -f flutter_app/build/app/outputs/bundle/release/app-release.aab ] && { echo "✅ 6-1 AAB OK"; test_pass; } || { echo "❌ 6-1 AAB 없음"; test_fail; }

echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  E2E: $P 통과 / $F 실패 / $((P+F)) 전체"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

`deploy` 인자 전달 시 추가로:
1. `pubspec.yaml` 버전 코드를 +1 올립니다
2. `flutter build appbundle --release` 실행
3. `cd flutter_app/android && fastlane internal` 실행
4. 결과를 보고합니다

실패 시 원인 파악 → 수정 → 해당 Phase 재실행. 최대 3라운드.
