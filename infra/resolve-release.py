import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


RELEASE_EVENTS = ("push", "workflow_dispatch")


def github_api(path):
    return json.loads(subprocess.check_output(["gh", "api", path]))


def main():
    repository = os.environ["GITHUB_REPOSITORY"]
    run_id = os.environ["CI_RUN_ID"]
    if not re.fullmatch(r"[0-9]+", run_id):
        raise SystemExit("Provide a numeric CI run ID")

    run = github_api(f"repos/{repository}/actions/runs/{run_id}")
    if not (
        run["path"] == ".github/workflows/ci.yml"
        and run["head_repository"]["full_name"] == repository
        and run["head_branch"] == "main"
        and run["event"] in RELEASE_EVENTS
        and run["conclusion"] == "success"
    ):
        raise SystemExit("The release must come from a successful CI publication on this repository's main branch")

    for event in RELEASE_EVENTS:
        latest = github_api(
            f"repos/{repository}/actions/workflows/ci.yml/runs"
            f"?branch=main&status=success&event={event}&per_page=1"
        )["workflow_runs"]
        if latest and latest[0]["run_number"] > run["run_number"]:
            raise SystemExit(f"A newer successful CI run exists: {latest[0]['id']}")

    with tempfile.TemporaryDirectory() as directory:
        subprocess.run([
            "gh", "run", "download", run_id, "--repo", repository,
            "--name", "release-manifest", "--dir", directory,
        ], check=True)
        release = json.loads((Path(directory) / "release.json").read_text())

    commit = run["head_sha"]
    if release["commit"] != commit or set(release["images"]) != {"backend", "frontend"}:
        raise SystemExit("The manifest must contain both images from the validated CI commit")

    images = {}
    for component, record in release["images"].items():
        image = record["image"]
        if not (
            record["component"] == component
            and record["commit"] == commit
            and re.fullmatch(rf"[a-z0-9_-]+/bookstore-{component}@sha256:[0-9a-f]{{64}}", image)
        ):
            raise SystemExit(f"Invalid {component} image in the release manifest")
        images[component] = image

    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as outputs:
        print(f"release_images={json.dumps(images, separators=(',', ':'))}", file=outputs)
    print(f"Selected CI run {run_id} and release {commit}")


if __name__ == "__main__":
    main()
