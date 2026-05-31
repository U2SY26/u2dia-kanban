# verification_queue.py — 칸반 검증 큐 워커

## 핵심 알고리즘

```
[수집] 모든 활성팀 Review 티켓 → 우선순위 큐 (Critical→High→Medium→Low + 생성시각 ASC)
   ↓
[병렬 N개 워커] 각 티켓을 독립 처리
   ↓
[디바운스] 같은 티켓 5분 내 재검수 금지 (LLM 노이즈 흡수)
   ↓
[체인 한도] parent_ticket_id 체인 누적 재작업 ≥ 3 → 즉시 Blocked (재 티켓 발행 불가)
   ↓
[supervisor 호출] 1회 검수 → 점수 메모리 누적
   ↓
[평균 fallback]
   - 평균 ≥ 3.0 AND 산출물 1+ → Done 강제 (LLM 변동 흡수)
   - 평균 < 2.5 AND 시도 ≥ 3 → Blocked
   - 그 외 → supervisor 결정 그대로 (passthrough)
```

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `KANBAN_API` | `http://localhost:5555` | 칸반 서버 주소 |
| `VQ_DEBOUNCE` | `300` | 같은 티켓 재검수 최소 간격(초) |
| `VQ_PASS_AVG` | `3.0` | 평균 통과 점수 (이상 → Done) |
| `VQ_BLOCK_AVG` | `2.5` | 평균 미달 임계 (미만 + 3회 → Blocked) |
| `VQ_MAX_REWORK` | `3` | 체인 누적 재작업 한도 |
| `VQ_LOG` | `/tmp/verification_queue.log` | 로그 파일 |

## 실행

### 1회 (테스트)
```bash
python3 verification_queue.py --once --workers 3
```

### 데몬 (운영)
```bash
nohup python3 verification_queue.py --cycle 300 --workers 5 > /tmp/vq.log 2>&1 &
echo $! > /tmp/vq.pid
```

### systemd (권장)
```ini
# /etc/systemd/system/kanban-verification.service
[Unit]
Description=Kanban Verification Queue
After=network.target

[Service]
Type=simple
User=u2dia
WorkingDirectory=/home/u2dia/github/U2DIA-KANBAN-BOARD/scripts
ExecStart=/usr/bin/python3 verification_queue.py --cycle 300 --workers 5
Restart=on-failure
Environment=VQ_PASS_AVG=3.0
Environment=VQ_BLOCK_AVG=2.5
Environment=VQ_MAX_REWORK=3

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now kanban-verification
```

## 검증된 동작

- ✅ 점수 추출: supervisor 응답 `actions_executed` 의 "(\\d)점" 패턴 정상 파싱
- ✅ 메모리 누적: 1시간 sliding window
- ✅ 디바운스: 1s < 300s 발동 확인
- ✅ 체인 폴백: title 의 `[재작업 N/3]` / `[REWORK]` 패턴 인식 (parent_ticket_id 누락 워크어라운드)
- ✅ 병렬 처리: ThreadPoolExecutor 3 워커, 동시 처리 정상

## 알려진 결함 (server.py 측)

`_chat_supervisor_respond()` 가 발행하는 재작업 티켓은 `parent_ticket_id` 와 `description` 의 "원본:" 모두 누락됨. verification_queue 는 title 패턴으로 폴백하지만, 본 결함은 server.py 측에서 수정해야 정식 체인 추적이 가능함. 별도 티켓으로 추적 권장.

## 동작 시나리오

### 시나리오 A — supervisor 평가 변동 (4→3→3 점)
1. 1차 호출: 4점 → 메모리 [4]
2. 디바운스로 5분 차단 → 자동 사이클 호출 무시
3. 5분 후 2차: 3점 → 메모리 [4, 3] 평균 3.5
4. 평균 ≥ 3.0 + 산출물 → **Done 강제** (LLM 노이즈 흡수)

### 시나리오 B — 진짜 결함 (1→2→2 점)
1. 1차: 1점 → 메모리 [1]
2. 5분+ 후 2차: 2점 → [1, 2] 평균 1.5
3. 5분+ 후 3차: 2점 → [1, 2, 2] 평균 1.67, 시도 3회
4. 평균 < 2.5 + 시도 ≥ 3 → **Blocked** (사람 개입)

### 시나리오 C — 무한 재작업 방지
1. 원본 T-A 재작업 → T-B (chain 1)
2. T-B 재작업 → T-C (chain 2)
3. T-C 재작업 → T-D (chain 3)
4. T-D Review 진입 시 chain ≥ 3 검출 → **즉시 Blocked, 재 티켓 발행 차단**
