#!/usr/bin/env python3
"""play-listing-only.py — 스토어 등록정보(설명/이미지)만 업로드 + commit.

draft app 상태에서 production 트랙 release는 Google API가 막지만,
listing/assets 만 별도 트랜잭션으로 저장하면 Play Console UI 에서
사용자가 한 번 "Submit for review" 만 누르면 production 라이브 가능.
"""
import os
import sys
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CRED = Path.home() / ".config" / "play-store" / "service-account.json"
PACKAGE = os.environ.get("PLAY_PACKAGE_NAME", "com.u2dia.kanban")
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
ASSETS = ROOT / "play-assets"
LANG = "ko-KR"

SHORT_DESCRIPTION = "AI 에이전트 팀의 병렬 개발을 실시간으로 모니터링하는 칸반보드"
FULL_DESCRIPTION = """U2DIA AI 칸반보드 — 멀티 에이전트 협업 플랫폼

🤖 AI 에이전트 팀의 작업을 실시간으로 추적하고 조율하세요.

【 주요 기능 】

✅ 실시간 칸반보드
- 팀 단위 보드 + 티켓 라이프사이클 (Backlog → InProgress → Review → Done)
- SSE 실시간 푸시 (Server-Sent Events)
- 에이전트 간 메시지 + 산출물 공유

✅ 멀티 에이전트 협업
- 프로젝트별 전문 에이전트 스폰 (server-expert, qa-expert 등)
- 역할 기반 티켓 자동 분배
- 의존성 그래프 + 블로킹 자동 감지

✅ Sprint 관리 (gstack 패턴)
- 7단계 워크플로우: Think → Plan → Build → Review → Test → Ship → Reflect
- 5가지 품질 게이트 (review/qa/security/design/performance)
- 번다운 차트 + 벨로시티 추세

✅ Supervisor QA 자동 검수
- Ollama 로컬 LLM 기반 자동 품질 점수 (1~5점)
- 미통과 시 재작업 자동 발행 (최대 3회)

✅ Remote CLI Mirror
- 모바일에서 PC 터미널(tmux) 실시간 미러링
- Multi-session 전환 + 단축키 패널

✅ Mobile VSCode Workspace
- 폰/태블릿에서 풀 편집 가능 VSCode (code-server)
- 다중 워크스페이스 동시 spawn
- 새 세션 즉시 시작

✅ 토큰 사용량 모니터링
- 팀별/티켓별 LLM 토큰 사용량 추적
- 시간대별 활동 히트맵

✅ Cross-Model 코드 리뷰
- Claude + Gemini + Ollama 다중 모델 합의 리뷰

【 기술 】
- Python 3.8+ (server.py, 외부 의존성 0)
- SQLite WAL (동시 접근)
- MCP (Model Context Protocol) 27개 도구
- Vanilla JS/CSS SPA (외부 CDN 0)
- Flutter 모바일 (이 앱)
- Electron 데스크톱 (Server Manager + Frontend)

【 적합 사용자 】
- AI 에이전트 팀(Claude Code 등)을 운영하는 개발자
- 멀티 프로젝트를 병렬로 진행하는 1인 개발자
- Sprint·QA 게이트가 필요한 소규모 팀

문의: U2DIA"""


def main():
    cred = Path(os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", str(DEFAULT_CRED)))
    if not cred.is_file():
        sys.exit(f"❌ 자격증명 없음: {cred}")

    creds = service_account.Credentials.from_service_account_file(str(cred), scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    edit = service.edits().insert(packageName=PACKAGE, body={}).execute()
    edit_id = edit["id"]
    print(f"✅ Edit 시작: {edit_id}")

    # 현재 title 유지
    try:
        cur = service.edits().listings().get(
            packageName=PACKAGE, editId=edit_id, language=LANG).execute()
        title = cur.get("title") or "UDI"
    except HttpError:
        title = "UDI"

    listing_body = {
        "language": LANG,
        "title": title,
        "shortDescription": SHORT_DESCRIPTION,
        "fullDescription": FULL_DESCRIPTION,
    }
    service.edits().listings().update(
        packageName=PACKAGE, editId=edit_id,
        language=LANG, body=listing_body,
    ).execute()
    print(f"✅ Listing: title='{title}' short={len(SHORT_DESCRIPTION)}자 full={len(FULL_DESCRIPTION)}자")

    image_uploads = [
        ("icon", [ASSETS / "icons/icon-512.png"]),
        ("featureGraphic", [ASSETS / "feature/feature-1024x500.png"]),
        ("phoneScreenshots", sorted((ASSETS / "screenshots-phone").glob("*.png"))),
        ("sevenInchScreenshots", sorted((ASSETS / "screenshots-tab7").glob("*.png"))),
        ("tenInchScreenshots", sorted((ASSETS / "screenshots-tab10").glob("*.png"))),
    ]
    for image_type, files in image_uploads:
        try:
            service.edits().images().deleteall(
                packageName=PACKAGE, editId=edit_id,
                language=LANG, imageType=image_type,
            ).execute()
        except HttpError:
            pass
        for f in files:
            if not f.is_file():
                continue
            try:
                service.edits().images().upload(
                    packageName=PACKAGE, editId=edit_id,
                    language=LANG, imageType=image_type,
                    media_body=MediaFileUpload(str(f), mimetype="image/png", resumable=False),
                ).execute()
                print(f"  + {image_type}: {f.name}")
            except HttpError as e:
                print(f"  ❌ {image_type}/{f.name}: {e}", file=sys.stderr)

    # commit (track release 없이)
    try:
        committed = service.edits().commit(packageName=PACKAGE, editId=edit_id).execute()
        print(f"\n🎉 Commit OK: editId={committed.get('id')}")
    except HttpError as e:
        sys.exit(f"❌ Commit 실패: {e}\n{e.content.decode('utf-8') if e.content else ''}")


if __name__ == "__main__":
    main()
