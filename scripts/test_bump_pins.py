"""Offline unit tests for bump_pins.py: python3 -m unittest discover -s scripts"""

import datetime as dt
import unittest

import bump_pins as bp

DOCKERFILE = """FROM x
ARG NODE_VERSION=24.21.0
ARG NODE_SHA256_AMD64=aaa
ARG NODE_SHA256_ARM64=bbb
ARG DEV_USER=dev
RUN echo ARG NODE_VERSION=not-an-arg
"""


class ArgsTest(unittest.TestCase):
    def test_read_args(self):
        self.assertEqual(bp.read_args(DOCKERFILE)["NODE_VERSION"], "24.21.0")
        self.assertEqual(bp.read_args(DOCKERFILE)["DEV_USER"], "dev")

    def test_write_args_only_touches_given_args(self):
        out = bp.write_args(DOCKERFILE, {"NODE_VERSION": "24.22.0", "NODE_SHA256_AMD64": "ccc"})
        self.assertIn("ARG NODE_VERSION=24.22.0\n", out)
        self.assertIn("ARG NODE_SHA256_AMD64=ccc\n", out)
        self.assertIn("ARG NODE_SHA256_ARM64=bbb\n", out)
        self.assertIn("RUN echo ARG NODE_VERSION=not-an-arg\n", out)

    def test_write_args_rejects_unknown(self):
        with self.assertRaises(KeyError):
            bp.write_args(DOCKERFILE, {"MISSING_VERSION": "1"})

    def test_real_dockerfiles_have_every_managed_arg(self):
        for tool in bp.TOOLS:
            args = bp.read_args(tool.dockerfile.read_text())
            for name in [tool.version_arg, *tool.sha_args.values()]:
                self.assertIn(name, args, f"{tool.name}: {name} missing in {tool.dockerfile}")
            bp.version_key(args[tool.version_arg])
            for name in tool.sha_args.values():
                self.assertRegex(args[name], r"^[0-9a-f]{64}$")


class VersionTest(unittest.TestCase):
    def test_numeric_ordering(self):
        self.assertGreater(bp.version_key("2.10.0"), bp.version_key("2.9.9"))
        self.assertEqual(bp.version_key("24.21.0"), (24, 21, 0))

    def test_rejects_prereleases(self):
        for bad in ("1.2.0-rc1", "v1.2.3", "3.14.5rc1", ""):
            with self.assertRaises(ValueError):
                bp.version_key(bad)


class ChecksumTest(unittest.TestCase):
    SUMS = (
        "a" * 64 + "  node-v1.0.0-linux-x64.tar.xz\n"
        + "b" * 64 + "  node-v1.0.0-linux-x64.tar.xz.sig\n"
        + "c" * 64 + " *gh_1_linux_arm64.tar.gz\n"
    )

    def test_exact_filename_match(self):
        self.assertEqual(bp.checksum_for(self.SUMS, "node-v1.0.0-linux-x64.tar.xz"), "a" * 64)

    def test_binary_mode_marker(self):
        self.assertEqual(bp.checksum_for(self.SUMS, "gh_1_linux_arm64.tar.gz"), "c" * 64)

    def test_missing_or_duplicate_fails(self):
        with self.assertRaises(ValueError):
            bp.checksum_for(self.SUMS, "node-v1.0.0-linux-arm64.tar.xz")
        with self.assertRaises(ValueError):
            bp.checksum_for(self.SUMS + self.SUMS, "node-v1.0.0-linux-x64.tar.xz")

    def test_rejects_non_sha256(self):
        with self.assertRaises(ValueError):
            bp.checksum_for("abc  f.zip\n", "f.zip")


class CooldownTest(unittest.TestCase):
    NOW = dt.datetime(2026, 9, 29, tzinfo=dt.timezone.utc)

    def test_young_release_is_skipped(self):
        self.assertFalse(bp.old_enough(self.NOW - dt.timedelta(days=6, hours=23), self.NOW, 7))

    def test_old_release_passes(self):
        self.assertTrue(bp.old_enough(self.NOW - dt.timedelta(days=7), self.NOW, 7))

    def test_unknown_age_passes(self):
        self.assertTrue(bp.old_enough(None, self.NOW, 7))


if __name__ == "__main__":
    unittest.main()
