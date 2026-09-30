"""Lint: fail if a workflow job reads AGENT_APP_PRIVATE_KEY without `environment: agent-app`.

A repo-level secret is readable by any same-repo PR workflow; an environment
secret is limited to the branches the environment allows (main only). This is
a line-based lint against accidental regressions, not enforcement: the real
control is the environment's branch policy plus maintainer review of workflow
changes. Block-style YAML only; anything it cannot place in a job fails closed.
Usage: python3 scripts/check_app_key_env.py [workflow.yml ...]
"""

import pathlib
import re
import sys

SECRET = re.compile("AGENT_APP_PRIVATE_KEY", re.IGNORECASE)  # secret names are case-insensitive
ENV_LINE = re.compile(r"^\s+environment:\s*[\"']?agent-app[\"']?\s*(#.*)?$")
BLANK_OR_COMMENT = re.compile(r"^\s*(#.*)?$")
# Ways to reach every secret without naming the key.
BROAD_ACCESS = [re.compile(p) for p in (r"secrets:\s*inherit", r"toJSON\(\s*secrets\s*\)", r"secrets\[")]
OUTSIDE_JOB = "<outside a job>"


def violations(text):
    """Return the job ids (or patterns) that could expose the key outside agent-app."""
    bad, job, lines, job_indent, job_key_indent = [], OUTSIDE_JOB, [], None, None
    in_jobs = False

    def flush():
        if not any(SECRET.search(l) for l in lines):
            return
        scoped = job != OUTSIDE_JOB and any(
            ENV_LINE.match(l) and len(l) - len(l.lstrip()) == job_key_indent for l in lines
        )
        if not scoped:
            bad.append(job)

    for line in text.splitlines():
        if BLANK_OR_COMMENT.match(line):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            flush()
            job, lines, job_indent, job_key_indent = OUTSIDE_JOB, [line], None, None
            in_jobs = line.startswith("jobs:")
        elif in_jobs and job_indent is None:
            job_indent = indent  # first key under jobs: fixes the job-id indent
            job, lines, job_key_indent = line.strip().split(":")[0], [], None
        elif in_jobs and indent == job_indent and re.match(r"^\s*[\w-]+:\s*(#.*)?$", line):
            flush()
            job, lines, job_key_indent = line.strip().split(":")[0], [], None
        else:
            if in_jobs and job_key_indent is None:
                job_key_indent = indent
            lines.append(line)
    flush()
    bad.extend(p.pattern for p in BROAD_ACCESS if p.search(text))
    return bad


def main(paths):
    failed = False
    files = paths or sorted(pathlib.Path(".github/workflows").glob("*.y*ml"))
    if not files:
        print("no workflow files found")
        return 1
    for path in files:
        for job in violations(pathlib.Path(path).read_text()):
            print(f"{path}: '{job}' can read {SECRET.pattern} outside 'environment: agent-app'")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
