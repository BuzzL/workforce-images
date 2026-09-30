"""Offline unit tests for check_app_key_env.py: python3 -m unittest discover -s scripts"""

import unittest

import check_app_key_env as c

GOOD = """name: x
on: push
jobs:
  bump:
    runs-on: ubuntu-latest
    environment: agent-app
    steps:
      - with:
          private-key: ${{ secrets.AGENT_APP_PRIVATE_KEY }}
"""


class CheckTest(unittest.TestCase):
    def test_environment_present(self):
        self.assertEqual(c.violations(GOOD), [])

    def test_missing_environment(self):
        self.assertEqual(c.violations(GOOD.replace("    environment: agent-app\n", "")), ["bump"])

    def test_wrong_environment(self):
        self.assertEqual(c.violations(GOOD.replace("agent-app\n", "other\n")), ["bump"])

    def test_environment_of_another_job_does_not_count(self):
        text = GOOD.replace("    environment: agent-app\n", "") + "  other:\n    environment: agent-app\n"
        self.assertEqual(c.violations(text), ["bump"])

    def test_job_without_secret_is_fine(self):
        self.assertEqual(c.violations("jobs:\n  a:\n    runs-on: x\n"), [])

    def test_column_zero_comment_does_not_end_jobs(self):
        text = "jobs:\n  a:\n    runs-on: x\n# note\n  b:\n    run: ${{ secrets.AGENT_APP_PRIVATE_KEY }}\n"
        self.assertEqual(c.violations(text), ["b"])

    def test_four_space_indentation(self):
        text = GOOD.replace("\n  bump:", "\n    bump:")
        text = "\n".join(("  " + l if i > 3 else l) for i, l in enumerate(text.splitlines())) + "\n"
        self.assertEqual(c.violations(text), [])
        self.assertEqual(c.violations(text.replace("      environment: agent-app\n", "")), ["bump"])

    def test_secret_name_is_case_insensitive(self):
        text = GOOD.replace("    environment: agent-app\n", "").replace("AGENT_APP_PRIVATE_KEY", "agent_app_private_key")
        self.assertEqual(c.violations(text), ["bump"])

    def test_key_outside_a_job(self):
        self.assertEqual(c.violations("env:\n  K: ${{ secrets.AGENT_APP_PRIVATE_KEY }}\njobs:\n  a:\n    runs-on: x\n"), [c.OUTSIDE_JOB])

    def test_broad_secret_access(self):
        for snippet in ("secrets: inherit", "${{ toJSON(secrets) }}", "${{ secrets['X'] }}"):
            self.assertEqual(len(c.violations(f"jobs:\n  a:\n    x: {snippet}\n")), 1, snippet)

    def test_real_workflows_pass_and_yaml_extension_is_scanned(self):
        self.assertEqual(c.main([]), 0)
        import pathlib, tempfile
        with tempfile.TemporaryDirectory() as d:
            f = pathlib.Path(d) / "x.yaml"
            f.write_text(GOOD.replace("    environment: agent-app\n", ""))
            self.assertEqual(c.main([str(f)]), 1)


if __name__ == "__main__":
    unittest.main()
