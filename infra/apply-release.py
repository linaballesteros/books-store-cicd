import json
import os
from pathlib import Path
import secrets
import subprocess


def main():
    workspace = os.environ["TF_WORKSPACE"]
    if workspace not in {"staging", "production"}:
        raise SystemExit("Select the staging or production workspace")

    parameters = {
        f"/bookstore/{workspace}/db/admin-password": ("db_admin_password", 32),
        f"/bookstore/{workspace}/db/app-password": ("db_app_password", 32),
        f"/bookstore/{workspace}/db/ingest-password": ("db_ingest_password", 32),
        f"/bookstore/{workspace}/auth/jwt-secret": ("auth_jwt_secret", 48),
    }
    response = json.loads(subprocess.check_output([
        "aws", "ssm", "get-parameters", "--no-cli-pager", "--output", "json",
        "--with-decryption", "--names", *parameters,
    ]))
    existing = {parameter["Name"]: parameter["Value"] for parameter in response["Parameters"]}
    env = os.environ.copy()
    for path, (variable, size) in parameters.items():
        value = existing[path] if path in existing else secrets.token_urlsafe(size)
        if env.get("GITHUB_ACTIONS") == "true":
            masked = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::add-mask::{masked}", flush=True)
        env[f"TF_VAR_{variable}"] = value

    infra_dir = Path(__file__).resolve().parent
    subprocess.run([
        "terraform", f"-chdir={infra_dir}", "apply", "-input=false", "-no-color", "-auto-approve",
    ], env=env, check=True)


if __name__ == "__main__":
    main()
