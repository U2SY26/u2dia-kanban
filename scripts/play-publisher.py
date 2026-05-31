#!/usr/bin/env python3
"""play-publisher.py — Google Play Developer API로 AAB 업로드.

fastlane(Ruby) 의존성 없이 Python google-api-python-client 로 직접 publish.
service-account.json 으로 인증, edits 트랜잭션 패턴.

Usage:
    python3 scripts/play-publisher.py <track> <aab_path> [--release-status STATUS]

Examples:
    python3 scripts/play-publisher.py internal flutter_app/build/.../app-release.aab
    python3 scripts/play-publisher.py production flutter_app/build/.../app-release.aab

Env:
    GOOGLE_APPLICATION_CREDENTIALS  service-account.json 경로
                                    (기본: ~/.config/play-store/service-account.json)
    PLAY_PACKAGE_NAME              패키지명 (기본: com.u2dia.kanban)
"""
import argparse
import os
import sys
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

DEFAULT_CRED = Path.home() / ".config" / "play-store" / "service-account.json"
DEFAULT_PACKAGE = "com.u2dia.kanban"
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]


def main():
    parser = argparse.ArgumentParser(description="Google Play AAB 업로드")
    parser.add_argument("track", choices=["internal", "alpha", "beta", "production"],
                        help="릴리즈 트랙")
    parser.add_argument("aab", help="AAB 파일 경로")
    parser.add_argument("--release-status", default=None,
                        help="draft|inProgress|halted|completed (기본: production=completed, 그 외=completed)")
    parser.add_argument("--package", default=os.environ.get("PLAY_PACKAGE_NAME", DEFAULT_PACKAGE))
    parser.add_argument("--credentials", default=os.environ.get("GOOGLE_APPLICATION_CREDENTIALS",
                                                                str(DEFAULT_CRED)))
    parser.add_argument("--rollout-fraction", type=float, default=None,
                        help="userFraction for inProgress (e.g. 0.1 = 10%%)")
    parser.add_argument("--release-name", default=None,
                        help="릴리즈 표시명 (기본: versionCode 사용)")
    args = parser.parse_args()

    aab = Path(args.aab).resolve()
    if not aab.is_file():
        sys.exit(f"❌ AAB 없음: {aab}")
    cred = Path(args.credentials)
    if not cred.is_file():
        sys.exit(f"❌ 자격증명 없음: {cred}")

    print(f"📦 AAB: {aab}  ({aab.stat().st_size // 1024} KB)")
    print(f"📱 Package: {args.package}")
    print(f"🚀 Track: {args.track}")
    print(f"🔑 Credentials: {cred}")

    creds = service_account.Credentials.from_service_account_file(str(cred), scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    # 1. edits.insert — 새 editId 시작
    try:
        edit = service.edits().insert(packageName=args.package, body={}).execute()
    except HttpError as e:
        sys.exit(f"❌ edits.insert 실패: {e}")
    edit_id = edit["id"]
    print(f"✅ Edit 시작: {edit_id}")

    # 2. bundles.upload — AAB 업로드
    try:
        media = MediaFileUpload(str(aab), mimetype="application/octet-stream", resumable=True)
        bundle = service.edits().bundles().upload(
            packageName=args.package,
            editId=edit_id,
            media_body=media,
        ).execute()
    except HttpError as e:
        sys.exit(f"❌ bundles.upload 실패: {e}")
    version_code = bundle["versionCode"]
    print(f"✅ AAB 업로드 완료: versionCode={version_code} sha1={bundle.get('sha1','-')[:12]}")

    # 3. tracks.update — 트랙에 release 추가
    release_status = args.release_status
    if not release_status:
        release_status = "completed"  # 기본 — 즉시 출시 가능 (기업 계정)

    release = {
        "name": args.release_name or f"v{version_code}",
        "versionCodes": [str(version_code)],
        "status": release_status,
    }
    if args.rollout_fraction is not None and release_status == "inProgress":
        release["userFraction"] = args.rollout_fraction

    try:
        service.edits().tracks().update(
            packageName=args.package,
            editId=edit_id,
            track=args.track,
            body={"track": args.track, "releases": [release]},
        ).execute()
    except HttpError as e:
        sys.exit(f"❌ tracks.update 실패: {e}\n응답: {e.content.decode('utf-8') if e.content else ''}")
    print(f"✅ Track '{args.track}' 업데이트: status={release_status}")

    # 4. edits.commit — 커밋 (changesNotSentForReview=True 로 자동 review 비활성)
    try:
        committed = service.edits().commit(
            packageName=args.package, editId=edit_id,
            changesNotSentForReview=True,
        ).execute()
    except HttpError as e:
        sys.exit(f"❌ edits.commit 실패: {e}\n응답: {e.content.decode('utf-8') if e.content else ''}")
    print(f"🎉 커밋 완료: editId={committed.get('id')}")
    print(f"\n출시 완료 — Play Console 에서 확인: https://play.google.com/console/u/0/developers/-/app/-/releases")


if __name__ == "__main__":
    main()
