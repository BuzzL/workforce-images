"""Fail if a workflow job reads AGENT_APP_PRIVATE_KEY without `environment: agent-app`.

A repo-level secret is readable by any same-repo PR workflow; an environment
secret is limited to the branches the environment allows (main only).
Usage: python3 scripts/check_app_key_env.py [workflow.yml ...]
"""

import pathlib
import re
import sys

SECRET = "AGENT_APP_PRIVATE_KEY"
ENVIRONMENT = "agent-app"
JOB_START = re.compile(r"^  [\w-]+:\s*$")
ENV_LINE = re.compile(rf"^    environment:\s*{ENVIRONMENT}\s*$")


def violations(text):
    """Return the job ids that use the secret without the environment."""
    bad, job, lines = [], None, []

    def flush():
        if job and any(SECRET in l for l in lines) and not any(ENV_LINE.match(l) for l in lines):
            bad.append(job)

    in_jobs = False
    for line in text.splitlines():
        if re.match(r"^\S", line):
            flush()
            job, lines = None, []
            in_jobs = line.startswith("jobs:")
        elif in_jobs and JOB_START.match(line):
            flush()
            job, lines = line.strip().rstrip(":"), []
        else:
            lines.append(line)
    flush()
    return bad


def main(paths):
    failed = False
    for path in paths or sorted(pathlib.Path(".github/workflows").glob("*.yml")):
        for job in violations(pathlib.Path(path).read_text()):
            print(f"{path}: job '{job}' uses {SECRET} without 'environment: {ENVIRONMENT}'")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
