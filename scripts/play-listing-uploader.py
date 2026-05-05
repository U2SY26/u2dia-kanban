#!/usr/bin/env python3
"""play-listing-uploader.py — 스토어 등록정보(설명/이미지) 자동 업로드 + production track release.

사용 시나리오: 첫 production publish를 자동화하려면 store listing(짧은 설명, 긴 설명, 이미지)이
완성되어야 한다. 이 스크립트가 한 번의 edit 트랜잭션으로 모두 처리한다.

Usage:
    python3 scripts/play-listing-uploader.py [--dry-run] [--track production|internal]
"""
import argparse
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
VERSION_CODE = int(os.environ.get("PLAY_VERSION_CODE", "133"))

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


def _img_path(rel):
    return ASSETS / rel


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--track", default="production",
                        choices=["internal", "alpha", "beta", "production"])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--credentials",
                        default=os.environ.get("GOOGLE_APPLICATION_CREDENTIALS",
                                                str(DEFAULT_CRED)))
    parser.add_argument("--release-status",
                        default="draft",
                        choices=["draft", "inProgress", "halted", "completed"])
    parser.add_argument("--skip-bundle", action="store_true",
                        help="AAB 업로드 건너뜀 (이미 v133이 업로드되었음)")
    parser.add_argument("--bundle-path", default=None)
    args = parser.parse_args()

    cred = Path(args.credentials)
    if not cred.is_file():
        sys.exit(f"❌ 자격증명 없음: {cred}")

    print(f"📱 Package: {PACKAGE}")
    print(f"🚀 Track: {args.track}  Status: {args.release_status}")
    print(f"📦 VersionCode: {VERSION_CODE}")
    print(f"🌐 Lang: {LANG}\n")

    creds = service_account.Credentials.from_service_account_file(str(cred), scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    if args.dry_run:
        print("[DRY RUN] 실제 변경 없음")
        return

    # 1. edits.insert
    edit = service.edits().insert(packageName=PACKAGE, body={}).execute()
    edit_id = edit["id"]
    print(f"✅ Edit 시작: {edit_id}")

    # 2. listings.update — 짧은 설명 + 긴 설명 (앱 이름은 사용자가 지정한 'UDI' 유지)
    try:
        cur = service.edits().listings().get(
            packageName=PACKAGE, editId=edit_id, language=LANG).execute()
        title = cur.get("title", "UDI")
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
    print(f"✅ Listing 업데이트 (title={title}, short={len(SHORT_DESCRIPTION)}자, full={len(FULL_DESCRIPTION)}자)")

    # 3. images — 기존 삭제 후 신규 업로드
    image_uploads = [
        ("icon", [_img_path("icons/icon-512.png")]),
        ("featureGraphic", [_img_path("feature/feature-1024x500.png")]),
        ("phoneScreenshots", sorted(_img_path("screenshots-phone").glob("*.png"))),
        ("sevenInchScreenshots", sorted(_img_path("screenshots-tab7").glob("*.png"))),
        ("tenInchScreenshots", sorted(_img_path("screenshots-tab10").glob("*.png"))),
    ]

    for image_type, files in image_uploads:
        # 기존 모두 삭제
        try:
            service.edits().images().deleteall(
                packageName=PACKAGE, editId=edit_id,
                language=LANG, imageType=image_type,
            ).execute()
        except HttpError as e:
            print(f"  (deleteall {image_type}: {e.resp.status})")

        for f in files:
            if not f.is_file():
                print(f"⚠️ 누락 {image_type}: {f}", file=sys.stderr)
                continue
            media = MediaFileUpload(str(f), mimetype="image/png", resumable=False)
            try:
                service.edits().images().upload(
                    packageName=PACKAGE, editId=edit_id,
                    language=LANG, imageType=image_type,
                    media_body=media,
                ).execute()
                print(f"✅ {image_type}: {f.name}")
            except HttpError as e:
                print(f"❌ {image_type} {f.name}: {e}", file=sys.stderr)

    # 4. AAB 업로드 (옵션)
    version_for_release = VERSION_CODE
    if not args.skip_bundle:
        if not args.bundle_path:
            sys.exit("❌ --bundle-path 필요 (또는 --skip-bundle)")
        media = MediaFileUpload(args.bundle_path, mimetype="application/octet-stream", resumable=True)
        try:
            bundle = service.edits().bundles().upload(
                packageName=PACKAGE, editId=edit_id, media_body=media,
            ).execute()
            version_for_release = bundle["versionCode"]
            print(f"✅ AAB 업로드: versionCode={version_for_release}")
        except HttpError as e:
            err_text = e.content.decode("utf-8") if e.content else ""
            if "already been used" in err_text.lower() or "duplicate" in err_text.lower():
                print(f"ℹ️ versionCode {VERSION_CODE} 이미 업로드됨 — 트랙 release만 추가")
            else:
                sys.exit(f"❌ AAB 업로드 실패: {e}\n{err_text}")

    # 5. tracks.update — production 트랙 release
    release = {
        "name": f"v{version_for_release}",
        "versionCodes": [str(version_for_release)],
        "status": args.release_status,
    }
    try:
        service.edits().tracks().update(
            packageName=PACKAGE, editId=edit_id,
            track=args.track,
            body={"track": args.track, "releases": [release]},
        ).execute()
        print(f"✅ Track '{args.track}' 업데이트 (status={args.release_status})")
    except HttpError as e:
        err_text = e.content.decode("utf-8") if e.content else ""
        print(f"⚠️ Track update 실패: {e}\n{err_text}", file=sys.stderr)

    # 6. commit
    try:
        committed = service.edits().commit(
            packageName=PACKAGE, editId=edit_id,
            changesNotSentForReview=False,
        ).execute()
        print(f"\n🎉 커밋 성공: editId={committed.get('id')}")
        print(f"Play Console: https://play.google.com/console/u/0/developers/-/app/-/main-store-listing")
    except HttpError as e:
        err_text = e.content.decode("utf-8") if e.content else ""
        sys.exit(f"❌ 커밋 실패: {e}\n{err_text}")


if __name__ == "__main__":
    main()
