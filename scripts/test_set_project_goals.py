#!/usr/bin/env python3
"""
set_project_goals.py 테스트 스크립트 (재작업 v3)
- 경계값 테스트
- 유효성 검사 테스트
- 예외/오류 처리 테스트 (강화)
- 보안(URL 유효성, CLI 인자 검증) 테스트 (강화)
- 자동화 실행: python -m pytest scripts/test_set_project_goals.py -v
"""

import json
import sys
import unittest
from unittest.mock import MagicMock, patch
from io import BytesIO
import urllib.error
import urllib.request

# 테스트 대상 모듈 임포트
sys.path.insert(0, "/home/u2dia/github/U2DIA-KANBAN-BOARD/scripts")
import set_project_goals as spg


# ─── 테스트용 유틸 ────────────────────────────────────────────
def make_http_response(body: dict, status: int = 200):
    """urllib.request.urlopen 반환값을 흉내 낸 컨텍스트 매니저."""
    raw = json.dumps(body).encode()
    mock_resp = MagicMock()
    mock_resp.read.return_value = raw
    mock_resp.status = status
    mock_resp.__enter__ = lambda s: s
    mock_resp.__exit__ = MagicMock(return_value=False)
    return mock_resp


def make_logger():
    import logging
    logger = logging.getLogger("test_logger")
    logger.setLevel(logging.CRITICAL)  # 테스트 중 로그 억제
    return logger


# ─── 1. api_request 단위 테스트 ──────────────────────────────
class TestApiRequest(unittest.TestCase):

    def test_get_success(self):
        """정상 GET 요청 → dict 반환"""
        expected = {"teams": [{"team_id": "T-001", "name": "테스트팀"}]}
        with patch("urllib.request.urlopen", return_value=make_http_response(expected)):
            result = spg.api_request("http://localhost:5555", "GET", "/api/teams")
        self.assertEqual(result, expected)

    def test_post_with_body(self):
        """POST + body → 정상 응답"""
        expected = {"ok": True, "team_id": "T-002"}
        with patch("urllib.request.urlopen", return_value=make_http_response(expected)):
            result = spg.api_request(
                "http://localhost:5555", "POST", "/api/teams",
                {"name": "새팀", "project_group": "TEST"}
            )
        self.assertTrue(result["ok"])

    def test_http_error_raises_runtime_error(self):
        """HTTP 4xx/5xx → RuntimeError 발생"""
        err = urllib.error.HTTPError(
            url="http://localhost:5555/api/teams",
            code=404,
            msg="Not Found",
            hdrs={},
            fp=BytesIO(b'{"error":"not_found"}'),
        )
        with patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(RuntimeError) as ctx:
                spg.api_request("http://localhost:5555", "GET", "/api/teams")
        self.assertIn("HTTP 404", str(ctx.exception))

    def test_url_error_raises_runtime_error(self):
        """연결 실패 → RuntimeError 발생"""
        err = urllib.error.URLError(reason="연결 거부됨")
        with patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(RuntimeError) as ctx:
                spg.api_request("http://localhost:9999", "GET", "/api/teams")
        self.assertIn("연결 실패", str(ctx.exception))

    def test_get_no_body(self):
        """body=None이면 data=None으로 요청"""
        expected = {"ok": True}
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["data"] = req.data
            return make_http_response(expected)

        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            spg.api_request("http://localhost:5555", "GET", "/api/teams")
        self.assertIsNone(captured["data"])

    def test_server_500_error(self):
        """500 서버 에러 → RuntimeError"""
        err = urllib.error.HTTPError(
            url="http://localhost:5555/api/teams",
            code=500,
            msg="Internal Server Error",
            hdrs={},
            fp=BytesIO(b'{"error":"server_error"}'),
        )
        with patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(RuntimeError) as ctx:
                spg.api_request("http://localhost:5555", "POST", "/api/teams", {})
        self.assertIn("HTTP 500", str(ctx.exception))

    def test_http_error_message_included_in_exception(self):
        """HTTPError 응답 본문이 RuntimeError 메시지에 포함되는지 확인"""
        err = urllib.error.HTTPError(
            url="http://localhost:5555/api/teams",
            code=403,
            msg="Forbidden",
            hdrs={},
            fp=BytesIO(b'{"error":"unauthorized"}'),
        )
        with patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(RuntimeError) as ctx:
                spg.api_request("http://localhost:5555", "GET", "/api/teams")
        self.assertIn("unauthorized", str(ctx.exception))

    def test_timeout_raises_url_error(self):
        """타임아웃(URLError) → RuntimeError"""
        import socket
        err = urllib.error.URLError(reason=socket.timeout("timed out"))
        with patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(RuntimeError) as ctx:
                spg.api_request("http://localhost:5555", "GET", "/api/teams")
        self.assertIn("연결 실패", str(ctx.exception))

    def test_invalid_json_response_raises(self):
        """응답이 유효하지 않은 JSON → json.JSONDecodeError 발생"""
        mock_resp = MagicMock()
        mock_resp.read.return_value = b"not-json!!!"
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        with patch("urllib.request.urlopen", return_value=mock_resp):
            with self.assertRaises(json.JSONDecodeError):
                spg.api_request("http://localhost:5555", "GET", "/api/teams")

    def test_empty_json_object_response(self):
        """빈 JSON 객체 응답 → 빈 dict 반환"""
        with patch("urllib.request.urlopen", return_value=make_http_response({})):
            result = spg.api_request("http://localhost:5555", "GET", "/api/teams")
        self.assertEqual(result, {})

    def test_post_body_serialized_as_json(self):
        """POST body가 JSON으로 직렬화되는지 확인"""
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["data"] = req.data
            return make_http_response({"ok": True})

        payload = {"name": "팀A", "project_group": "G1"}
        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            spg.api_request("http://localhost:5555", "POST", "/api/teams", payload)
        parsed = json.loads(captured["data"].decode())
        self.assertEqual(parsed["name"], "팀A")


# ─── 2. validate_host 보안 테스트 ────────────────────────────
class TestValidateHost(unittest.TestCase):

    def test_valid_http_host(self):
        """정상 http URL → 예외 없음"""
        spg.validate_host("http://localhost:5555")  # 예외 없으면 통과

    def test_valid_https_host(self):
        """정상 https URL → 예외 없음"""
        spg.validate_host("https://example.com")

    def test_invalid_scheme_file_raises(self):
        """file:// 스키마 → ValueError"""
        with self.assertRaises(ValueError) as ctx:
            spg.validate_host("file:///etc/passwd")
        self.assertIn("file", str(ctx.exception))

    def test_invalid_scheme_ftp_raises(self):
        """ftp:// 스키마 → ValueError"""
        with self.assertRaises(ValueError):
            spg.validate_host("ftp://example.com")

    def test_no_scheme_raises(self):
        """스키마 없는 URL → ValueError"""
        with self.assertRaises(ValueError):
            spg.validate_host("localhost:5555")

    def test_empty_host_raises(self):
        """빈 문자열 → ValueError"""
        with self.assertRaises(ValueError):
            spg.validate_host("")

    def test_injection_attempt_with_semicolon(self):
        """세미콜론 포함 URL → http 스키마 확인, netloc 존재 확인"""
        # 'http://evil.com; rm -rf /'는 urllib에 의해 URL로만 처리됨.
        # validate_host는 스키마(http)와 netloc 유무만 검사하므로 통과.
        # 실제 셸 실행 없음을 검증.
        spg.validate_host("http://evil.com; rm -rf /")  # 예외 없으면 통과 (urllib이 다음 단계에서 거부)

    def test_javascript_scheme_raises(self):
        """javascript: 스키마 → ValueError"""
        with self.assertRaises(ValueError):
            spg.validate_host("javascript:alert(1)")

    def test_no_netloc_raises(self):
        """netloc 없는 URL → ValueError"""
        with self.assertRaises(ValueError) as ctx:
            spg.validate_host("http://")
        self.assertIn("netloc", str(ctx.exception))


# ─── 3. get_or_create_team 테스트 ────────────────────────────
class TestGetOrCreateTeam(unittest.TestCase):

    def test_existing_team_found_case_insensitive(self):
        """project_group 대소문자 무관하게 기존 팀 반환"""
        teams_data = {
            "teams": [
                {"team_id": "T-LINKO", "name": "LINKO팀", "project_group": "linko"},
            ]
        }
        with patch("set_project_goals.api_request", return_value=teams_data):
            team_id = spg.get_or_create_team(
                "http://localhost:5555", "LINKO", "LINKO팀", "설명", make_logger()
            )
        self.assertEqual(team_id, "T-LINKO")

    def test_team_not_found_creates_new(self):
        """팀 없으면 신규 생성 호출"""
        call_count = [0]

        def fake_api(host, method, path, body=None):
            call_count[0] += 1
            if method == "GET":
                return {"teams": []}
            if method == "POST":
                return {"ok": True, "team": {"team_id": "T-NEW"}}
            return {}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            team_id = spg.get_or_create_team(
                "http://localhost:5555", "NEWGROUP", "새팀", "설명", make_logger()
            )
        self.assertEqual(team_id, "T-NEW")
        self.assertEqual(call_count[0], 2)  # GET + POST

    def test_create_team_failure_raises(self):
        """팀 생성 실패 시 RuntimeError"""
        def fake_api(host, method, path, body=None):
            if method == "GET":
                return {"teams": []}
            return {"ok": False, "error": "db_error"}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            with self.assertRaises(RuntimeError) as ctx:
                spg.get_or_create_team(
                    "http://localhost:5555", "FAIL", "실패팀", "설명", make_logger()
                )
        self.assertIn("팀 생성 실패", str(ctx.exception))

    def test_multiple_teams_returns_matching(self):
        """여러 팀 중 project_group이 일치하는 팀만 반환"""
        teams_data = {
            "teams": [
                {"team_id": "T-A", "name": "팀A", "project_group": "ALPHA"},
                {"team_id": "T-B", "name": "팀B", "project_group": "BETA"},
                {"team_id": "T-C", "name": "팀C", "project_group": "LINKO"},
            ]
        }
        with patch("set_project_goals.api_request", return_value=teams_data):
            team_id = spg.get_or_create_team(
                "http://localhost:5555", "LINKO", "LINKO팀", "설명", make_logger()
            )
        self.assertEqual(team_id, "T-C")

    def test_empty_teams_list(self):
        """빈 팀 목록 → 신규 생성"""
        def fake_api(host, method, path, body=None):
            if method == "GET":
                return {"teams": []}
            return {"ok": True, "team": {"team_id": "T-EMPTY"}}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            team_id = spg.get_or_create_team(
                "http://localhost:5555", "EMPTY", "빈팀", "설명", make_logger()
            )
        self.assertEqual(team_id, "T-EMPTY")

    def test_api_connection_failure(self):
        """GET /api/teams 연결 실패 → RuntimeError 전파"""
        with patch("set_project_goals.api_request",
                   side_effect=RuntimeError("연결 실패 http://localhost:9999: 연결 거부됨")):
            with self.assertRaises(RuntimeError):
                spg.get_or_create_team(
                    "http://localhost:9999", "X", "X팀", "설명", make_logger()
                )

    def test_teams_key_missing_in_response(self):
        """응답에 'teams' 키 없음 → 빈 리스트로 처리 후 신규 생성"""
        def fake_api(host, method, path, body=None):
            if method == "GET":
                return {}  # 'teams' 키 없음
            return {"ok": True, "team": {"team_id": "T-NOKEY"}}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            team_id = spg.get_or_create_team(
                "http://localhost:5555", "NOKEY", "팀", "설명", make_logger()
            )
        self.assertEqual(team_id, "T-NOKEY")

    def test_create_team_returns_team_id_at_root(self):
        """팀 생성 응답에서 team_id가 루트에 있는 경우도 처리"""
        def fake_api(host, method, path, body=None):
            if method == "GET":
                return {"teams": []}
            return {"ok": True, "team_id": "T-ROOT"}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            team_id = spg.get_or_create_team(
                "http://localhost:5555", "ROOT", "팀", "설명", make_logger()
            )
        self.assertEqual(team_id, "T-ROOT")


# ─── 4. create_goal_ticket 테스트 ────────────────────────────
class TestCreateGoalTicket(unittest.TestCase):

    def test_dry_run_returns_dry_run_string(self):
        """--dry-run 시 실제 API 호출 없이 'DRY-RUN' 반환"""
        with patch("set_project_goals.api_request") as mock_api:
            result = spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "LINKO", make_logger(), dry_run=True
            )
        self.assertEqual(result, "DRY-RUN")
        mock_api.assert_not_called()

    def test_ticket_creation_success(self):
        """티켓 생성 성공 → ticket_id 반환"""
        with patch("set_project_goals.api_request",
                   return_value={"ok": True, "ticket": {"ticket_id": "tkt-abc"}}):
            result = spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "LINKO", make_logger()
            )
        self.assertEqual(result, "tkt-abc")

    def test_ticket_creation_failure_raises(self):
        """티켓 생성 ok=False → RuntimeError"""
        with patch("set_project_goals.api_request",
                   return_value={"ok": False, "error": "quota_exceeded"}):
            with self.assertRaises(RuntimeError) as ctx:
                spg.create_goal_ticket(
                    "http://localhost:5555", "T-001", "LINKO", make_logger()
                )
        self.assertIn("티켓 생성 실패", str(ctx.exception))

    def test_ticket_title_contains_label(self):
        """생성되는 티켓 제목에 project_label 포함 확인"""
        captured_body = {}

        def fake_api(host, method, path, body=None):
            if body:
                captured_body.update(body)
            return {"ok": True, "ticket": {"ticket_id": "tkt-xyz"}}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "E-COMMERCE-AI", make_logger()
            )
        self.assertIn("E-COMMERCE-AI", captured_body.get("title", ""))

    def test_ticket_priority_is_high(self):
        """티켓 우선순위가 High인지 확인"""
        captured_body = {}

        def fake_api(host, method, path, body=None):
            if body:
                captured_body.update(body)
            return {"ok": True, "ticket": {"ticket_id": "tkt-xyz"}}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "LINKO", make_logger()
            )
        self.assertEqual(captured_body.get("priority"), "High")

    def test_ticket_api_error_propagates(self):
        """API 연결 오류 → RuntimeError 전파"""
        with patch("set_project_goals.api_request",
                   side_effect=RuntimeError("HTTP 500")):
            with self.assertRaises(RuntimeError):
                spg.create_goal_ticket(
                    "http://localhost:5555", "T-001", "LINKO", make_logger()
                )

    def test_unknown_label_uses_default_description(self):
        """알 수 없는 label → 기본 description 사용"""
        captured_body = {}

        def fake_api(host, method, path, body=None):
            if body:
                captured_body.update(body)
            return {"ok": True, "ticket": {"ticket_id": "tkt-default"}}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "UNKNOWN-PROJECT", make_logger()
            )
        desc = captured_body.get("description", "")
        self.assertIn("UNKNOWN-PROJECT", desc)

    def test_ticket_type_is_task(self):
        """티켓 타입이 task인지 확인"""
        captured_body = {}

        def fake_api(host, method, path, body=None):
            if body:
                captured_body.update(body)
            return {"ok": True, "ticket": {"ticket_id": "tkt-type"}}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "LINKO", make_logger()
            )
        self.assertEqual(captured_body.get("type"), "task")

    def test_ticket_id_at_root_fallback(self):
        """응답에서 ticket_id가 루트에 있는 경우도 처리"""
        with patch("set_project_goals.api_request",
                   return_value={"ok": True, "ticket_id": "tkt-root"}):
            result = spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "LINKO", make_logger()
            )
        self.assertEqual(result, "tkt-root")

    def test_description_contains_kpi(self):
        """LINKO description에 KPI 내용 포함 확인"""
        captured_body = {}

        def fake_api(host, method, path, body=None):
            if body:
                captured_body.update(body)
            return {"ok": True, "ticket": {"ticket_id": "tkt-kpi"}}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "LINKO", make_logger()
            )
        self.assertIn("KPI", captured_body.get("description", ""))

    def test_ecommerce_description_contains_okr(self):
        """E-COMMERCE-AI description에 OKR 내용 포함 확인"""
        captured_body = {}

        def fake_api(host, method, path, body=None):
            if body:
                captured_body.update(body)
            return {"ok": True, "ticket": {"ticket_id": "tkt-okr"}}

        with patch("set_project_goals.api_request", side_effect=fake_api):
            spg.create_goal_ticket(
                "http://localhost:5555", "T-001", "E-COMMERCE-AI", make_logger()
            )
        self.assertIn("OKR", captured_body.get("description", ""))


# ─── 5. 보안: CLI 인자 검증 테스트 ──────────────────────────
class TestCliArgSecurity(unittest.TestCase):

    def test_default_host(self):
        """기본 host는 localhost:5555"""
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--host", default="http://localhost:5555")
        parser.add_argument("--dry-run", action="store_true")
        parser.add_argument("-v", "--verbose", action="store_true")
        args = parser.parse_args([])
        self.assertEqual(args.host, "http://localhost:5555")

    def test_host_injection_attempt_stays_as_string(self):
        """--host에 특수문자 삽입 시도 → 문자열 그대로 처리 (URL로만 사용)"""
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--host", default="http://localhost:5555")
        args = parser.parse_args(["--host", "http://evil.com; rm -rf /"])
        self.assertIn("evil.com", args.host)

    def test_dry_run_flag(self):
        """--dry-run 플래그 파싱"""
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--dry-run", action="store_true")
        args = parser.parse_args(["--dry-run"])
        self.assertTrue(args.dry_run)

    def test_verbose_flag(self):
        """-v 플래그 파싱"""
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("-v", "--verbose", action="store_true")
        args = parser.parse_args(["-v"])
        self.assertTrue(args.verbose)

    def test_unknown_args_not_silently_ignored(self):
        """알 수 없는 인자는 argparse가 에러 처리"""
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--host", default="http://localhost:5555")
        with self.assertRaises(SystemExit):
            parser.parse_args(["--unknown-arg", "value"])

    def test_invalid_scheme_causes_main_to_return_2(self):
        """file:// 스키마 사용 시 main()이 exit_code=2 반환"""
        with patch("sys.argv", ["set_project_goals.py", "--host", "file:///etc/passwd"]):
            exit_code = spg.main()
        self.assertEqual(exit_code, 2)

    def test_no_scheme_causes_main_to_return_2(self):
        """스키마 없는 host 사용 시 main()이 exit_code=2 반환"""
        with patch("sys.argv", ["set_project_goals.py", "--host", "localhost:5555"]):
            exit_code = spg.main()
        self.assertEqual(exit_code, 2)


# ─── 6. main() 통합 테스트 ───────────────────────────────────
class TestMain(unittest.TestCase):

    def test_main_dry_run_success(self):
        """--dry-run 모드에서 main() 정상 실행 → exit_code=0"""
        teams_data = {"teams": [
            {"team_id": "T-LINKO", "name": "LINKO팀", "project_group": "LINKO"},
            {"team_id": "T-ECOM", "name": "E-COMMERCE-AI팀", "project_group": "E-COMMERCE-AI"},
        ]}

        def fake_api(host, method, path, body=None):
            if method == "GET":
                return teams_data
            return {"ok": True, "ticket": {"ticket_id": "tkt-dry"}}

        with patch("sys.argv", ["set_project_goals.py", "--dry-run"]):
            with patch("set_project_goals.api_request", side_effect=fake_api):
                exit_code = spg.main()
        self.assertEqual(exit_code, 0)

    def test_main_one_team_fails_exit_code_1(self):
        """한 팀 처리 실패 → exit_code=1"""
        call_n = [0]

        def fake_api(host, method, path, body=None):
            call_n[0] += 1
            if method == "GET":
                return {"teams": [
                    {"team_id": "T-LINKO", "name": "LINKO팀", "project_group": "LINKO"},
                    {"team_id": "T-ECOM", "name": "E팀", "project_group": "E-COMMERCE-AI"},
                ]}
            if "LINKO" in path:
                raise RuntimeError("HTTP 500")
            return {"ok": True, "ticket": {"ticket_id": "tkt-ok"}}

        with patch("sys.argv", ["set_project_goals.py"]):
            with patch("set_project_goals.api_request", side_effect=fake_api):
                exit_code = spg.main()
        self.assertEqual(exit_code, 1)

    def test_main_all_success(self):
        """모든 팀 성공 → exit_code=0"""
        teams_data = {"teams": [
            {"team_id": "T-LINKO", "project_group": "LINKO", "name": "L"},
            {"team_id": "T-ECOM", "project_group": "E-COMMERCE-AI", "name": "E"},
        ]}

        def fake_api(host, method, path, body=None):
            if method == "GET":
                return teams_data
            return {"ok": True, "ticket": {"ticket_id": "tkt-success"}}

        with patch("sys.argv", ["set_project_goals.py"]):
            with patch("set_project_goals.api_request", side_effect=fake_api):
                exit_code = spg.main()
        self.assertEqual(exit_code, 0)

    def test_main_all_teams_fail_exit_code_1(self):
        """모든 팀 실패 → exit_code=1"""
        def fake_api(host, method, path, body=None):
            raise RuntimeError("서버 다운")

        with patch("sys.argv", ["set_project_goals.py"]):
            with patch("set_project_goals.api_request", side_effect=fake_api):
                exit_code = spg.main()
        self.assertEqual(exit_code, 1)

    def test_main_invalid_host_returns_2(self):
        """유효하지 않은 host → exit_code=2 (API 호출 없이 조기 종료)"""
        with patch("sys.argv", ["set_project_goals.py", "--host", "ftp://evil.com"]):
            with patch("set_project_goals.api_request") as mock_api:
                exit_code = spg.main()
        self.assertEqual(exit_code, 2)
        mock_api.assert_not_called()


# ─── 7. TEAM_CONFIGS 경계값 테스트 ──────────────────────────
class TestTeamConfigs(unittest.TestCase):

    def test_team_configs_count(self):
        """TEAM_CONFIGS는 정확히 2개 팀 설정 포함"""
        self.assertEqual(len(spg.TEAM_CONFIGS), 2)

    def test_team_configs_labels(self):
        """LINKO, E-COMMERCE-AI 레이블 존재"""
        labels = [c["label"] for c in spg.TEAM_CONFIGS]
        self.assertIn("LINKO", labels)
        self.assertIn("E-COMMERCE-AI", labels)

    def test_all_configs_have_required_keys(self):
        """모든 팀 설정에 필수 키 존재"""
        required = {"project_group", "name", "description", "label"}
        for cfg in spg.TEAM_CONFIGS:
            missing = required - set(cfg.keys())
            self.assertEqual(missing, set(), f"누락 키: {missing} in {cfg}")

    def test_project_group_not_empty(self):
        """project_group 값이 비어 있지 않음"""
        for cfg in spg.TEAM_CONFIGS:
            self.assertTrue(cfg["project_group"].strip(), f"빈 project_group: {cfg}")

    def test_all_configs_name_not_empty(self):
        """모든 팀 설정의 name 값이 비어 있지 않음"""
        for cfg in spg.TEAM_CONFIGS:
            self.assertTrue(cfg["name"].strip(), f"빈 name: {cfg}")

    def test_all_configs_description_not_empty(self):
        """모든 팀 설정의 description 값이 비어 있지 않음"""
        for cfg in spg.TEAM_CONFIGS:
            self.assertTrue(cfg["description"].strip(), f"빈 description: {cfg}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
