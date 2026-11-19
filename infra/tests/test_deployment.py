import json
import os
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, call, patch


INFRA = Path(__file__).resolve().parents[1]
REPO = "example/books-store-cicd"
COMMIT = "a" * 40


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.resolve = runpy.run_path(str(INFRA / "resolve-release.py"))["main"]
        self.run_info = {
            "path": ".github/workflows/ci.yml", "head_repository": {"full_name": REPO},
            "head_branch": "main", "event": "push", "conclusion": "success",
            "head_sha": COMMIT, "run_number": 5,
        }
        self.latest = {"workflow_runs": []}
        self.images = {name: f"publisher/bookstore-{name}@sha256:{'a' * 64}"
                       for name in ("backend", "frontend")}
        self.manifest = {"commit": COMMIT, "images": {
            name: {"component": name, "commit": COMMIT, "image": image}
            for name, image in self.images.items()
        }}
        self.api_responses = []

    def call_resolver(self, run_id="5"):
        def download(command, *, check):
            self.assertTrue(check)
            self.assertEqual(command[command.index("--name") + 1], "release-manifest")
            Path(command[-1], "release.json").write_text(json.dumps(self.manifest))

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory, "output")
            with patch.dict(os.environ, {"GITHUB_REPOSITORY": REPO, "CI_RUN_ID": run_id,
                                        "GITHUB_OUTPUT": str(output)}), \
                    patch("subprocess.check_output", side_effect=map(json.dumps, self.api_responses)), \
                    patch("subprocess.run", side_effect=download):
                self.resolve()
            key, images = output.read_text().strip().split("=", 1)
            self.assertEqual(key, "release_images")
            return json.loads(images)

    def test_resolves_one_release(self):
        self.api_responses = [self.run_info, {"workflow_runs": [{"run_number": 5}]}, self.latest]
        self.assertEqual(self.call_resolver(), self.images)

    def test_rejects_non_numeric_run_id(self):
        with self.assertRaisesRegex(SystemExit, "numeric CI run ID"):
            self.call_resolver("bad")

    def test_rejects_pull_request_run(self):
        self.api_responses = [{**self.run_info, "event": "pull_request"}]
        with self.assertRaisesRegex(SystemExit, "publication"):
            self.call_resolver()

    def test_rejects_stale_run(self):
        self.api_responses = [self.run_info, {"workflow_runs": [{"run_number": 6, "id": 601}]}]
        with self.assertRaisesRegex(SystemExit, "newer successful CI run"):
            self.call_resolver()

    def test_rejects_incomplete_release(self):
        self.manifest["images"].pop("frontend")
        self.api_responses = [self.run_info, self.latest, self.latest]
        with self.assertRaisesRegex(SystemExit, "both images"):
            self.call_resolver()

    def test_rejects_mutable_image_tag(self):
        self.manifest["images"]["backend"]["image"] = "publisher/bookstore-backend:latest"
        self.api_responses = [self.run_info, self.latest, self.latest]
        with self.assertRaisesRegex(SystemExit, "Invalid backend image"):
            self.call_resolver()


class ApplyTests(unittest.TestCase):
    def test_reuses_existing_parameters_and_generates_missing_values(self):
        apply = runpy.run_path(str(INFRA / "apply-release.py"))["main"]
        existing = {"Parameters": [{"Name": "/bookstore/staging/db/admin-password", "Value": "example-admin"}]}
        with patch.dict(os.environ, {"TF_WORKSPACE": "staging", "GITHUB_ACTIONS": "true"}), \
                patch("subprocess.check_output", return_value=json.dumps(existing)) as lookup, \
                patch("subprocess.run") as terraform, patch("builtins.print") as log, \
                patch("secrets.token_urlsafe", side_effect=lambda size: f"example-{size}"):
            apply()
        self.assertIn("--with-decryption", lookup.call_args.args[0])
        self.assertIn("apply", terraform.call_args.args[0])
        env = terraform.call_args.kwargs["env"]
        self.assertEqual(env["TF_VAR_db_admin_password"], "example-admin")
        self.assertEqual(env["TF_VAR_db_app_password"], "example-32")
        self.assertEqual(env["TF_VAR_auth_jwt_secret"], "example-48")
        log.assert_any_call("::add-mask::example-admin", flush=True)

    def test_rejects_default_workspace(self):
        apply = runpy.run_path(str(INFRA / "apply-release.py"))["main"]
        with patch.dict(os.environ, {"TF_WORKSPACE": "default"}), \
                self.assertRaisesRegex(SystemExit, "staging or production"):
            apply()


class SmokeTests(unittest.TestCase):
    def setUp(self):
        self.smoke = runpy.run_path(str(INFRA / "smoke-test.py"))["main"]
        self.globals = self.smoke.__globals__
        self.base_url = "http://example.test"

    def test_accepts_storefront_and_catalog(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 200
        response.headers.get_content_type.side_effect = ["text/html", "application/json"]
        response.read.side_effect = [b"<title>MyBookStore</title>", b'[{"isbn":"123","title":"Book"}]']
        fetch = Mock(return_value=response)
        with patch.dict(self.globals, {"urlopen": fetch}), \
                patch.object(sys, "argv", ["smoke-test.py", self.base_url + "/"]):
            self.smoke()
        self.assertEqual(fetch.call_args_list, [
            call(f"{self.base_url}/", timeout=10),
            call(f"{self.base_url}/api/books?limit=1", timeout=10),
        ])

    def test_rejects_unexpected_storefront_and_catalog(self):
        scenarios = [
            ("check_storefront", "text/html", b"<title>Other app</title>", "BookStore HTML"),
            ("check_catalog", "text/html", b"[]", "did not return JSON"),
            ("check_catalog", "application/json", b"[]", "one seeded book"),
        ]
        for check, content_type, body, message in scenarios:
            with self.subTest(check=check, body=body), \
                    patch.dict(self.globals, {"read_response": Mock(return_value=(content_type, body))}), \
                    self.assertRaisesRegex(ValueError, message):
                self.globals[check](self.base_url)

    def test_retries_and_reports_http_failure(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 503
        with patch.dict(self.globals, {"urlopen": Mock(return_value=response)}), \
                patch.object(sys, "argv", ["smoke-test.py", self.base_url]), \
                patch("time.sleep") as sleep, self.assertRaisesRegex(SystemExit, "HTTP 503"):
            self.smoke()
        self.assertEqual(sleep.call_count, 4)
