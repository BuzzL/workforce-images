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


if __name__ == "__main__":
    unittest.main()
