import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

INFRA = Path(__file__).resolve().parents[1]
ENDPOINT = "https://abc123.execute-api.us-east-1.amazonaws.com"
BASE = "arn:aws:ecs:us-east-1:123456789012:task-definition/bookstore-staging-app:"
FIRST, SECOND = BASE + "1", BASE + "2"

AWS_STUB = """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

state_file = Path(os.environ["TEST_STATE"])
state = json.loads(state_file.read_text())
service, operation, *args = sys.argv[1:]
if (service, operation) == ("ssm", "get-parameters"):
    print(state["history"] or "None")
elif (service, operation) == ("ssm", "put-parameter"):
    state["history"] = args[args.index("--value") + 1]
elif (service, operation) == ("ecs", "describe-services"):
    print(state["active"])
elif (service, operation) == ("ecs", "update-service"):
    state["active"] = args[args.index("--task-definition") + 1]
    state["updates"].append(state["active"])
elif (service, operation) == ("apigatewayv2", "get-apis"):
    print(state["endpoint"])
elif (service, operation) != ("ecs", "wait"):
    raise SystemExit(f"Unexpected command: {sys.argv[1:]}")
state_file.write_text(json.dumps(state))
"""

SMOKE_STUB = """
import json
import os
from pathlib import Path
import sys

state_file = Path(os.environ["TEST_STATE"])
state = json.loads(state_file.read_text())
state["checks"].append([state["active"], sys.argv[1]])
state_file.write_text(json.dumps(state))
raise SystemExit(int(state["active"] == state["unhealthy"]))
"""


class ReleaseHealthTests(unittest.TestCase):
    def run_health(self, *args, active, history="", unhealthy="", endpoint=ENDPOINT):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for script in ("release-health.sh", "ecs-service.sh"):
                shutil.copyfile(INFRA / script, path / script)
            (path / "smoke-test.py").write_text(SMOKE_STUB)
            aws = path / "aws"
            aws.write_text(AWS_STUB)
            aws.chmod(0o755)
            state = path / "state.json"
            state.write_text(json.dumps(dict(active=active, history=history, unhealthy=unhealthy,
                                             endpoint=endpoint, updates=[], checks=[])))
            env = dict(os.environ, PATH=f"{path}:{os.environ['PATH']}", TF_WORKSPACE="staging",
                       TEST_STATE=str(state), APPLICATION_URL="")
            result = subprocess.run(
                ["bash", str(path / "release-health.sh"), *args],
                env=env, text=True, capture_output=True, check=False,
            )
            return result, json.loads(state.read_text())

    def test_success_records_candidate_and_keeps_previous(self):
        result, state = self.run_health("verify", SECOND, active=SECOND, history=FIRST)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["history"], f"{SECOND},{FIRST}")
        self.assertEqual(state["updates"], [])

    def test_retesting_a_validated_revision_preserves_history(self):
        result, state = self.run_health("verify", SECOND, active=SECOND, history=f"{SECOND},{FIRST}")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["history"], f"{SECOND},{FIRST}")

    def test_failed_candidate_restores_baseline_and_keeps_job_red(self):
        result, state = self.run_health("verify", SECOND, active=SECOND, history=FIRST, unhealthy=SECOND)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(state["updates"], [FIRST])
        self.assertEqual(state["checks"], [[SECOND, ENDPOINT], [FIRST, ENDPOINT]])
        self.assertEqual(state["history"], FIRST)

    def test_first_failed_deployment_reports_no_baseline(self):
        result, state = self.run_health("verify", FIRST, active=FIRST, unhealthy=FIRST)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no different validated revision", result.stderr)
        self.assertEqual(state["updates"], [])

    def test_failed_recheck_falls_back_to_previous_validated_revision(self):
        result, state = self.run_health("verify", SECOND, active=SECOND, history=f"{SECOND},{FIRST}",
                                        unhealthy=SECOND)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(state["updates"], [FIRST])
        self.assertEqual(state["history"], FIRST)

    def test_manual_rollback_chooses_previous_if_active_was_validated(self):
        result, state = self.run_health("rollback", active=SECOND, history=f"{SECOND},{FIRST}")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["updates"], [FIRST])
        self.assertEqual(state["history"], FIRST)

    def test_manual_rollback_chooses_last_validated_if_active_is_unverified(self):
        result, state = self.run_health("rollback", active=SECOND, history=FIRST)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["updates"], [FIRST])

    def test_revision_mismatch_cannot_be_marked_validated(self):
        result, state = self.run_health("verify", SECOND, active=FIRST)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(state["checks"], [])
