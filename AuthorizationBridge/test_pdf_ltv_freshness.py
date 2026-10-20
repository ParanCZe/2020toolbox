"""Regression tests for PAdES-LT revocation evidence freshness.

These tests only validate the structural freshness guard. Cryptographic
authenticity, responder authorisation and trust remain the validator's job.
"""
import unittest
from datetime import datetime, timedelta, timezone

from pdf_ltv import _evidence_window_ok


class RevocationFreshnessTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 20, 10, 0, tzinfo=timezone.utc)

    def test_current_evidence(self):
        self.assertTrue(_evidence_window_ok(
            self.now - timedelta(hours=1),
            self.now + timedelta(hours=1), at_time=self.now))

    def test_expired_evidence(self):
        self.assertFalse(_evidence_window_ok(
            self.now - timedelta(days=2),
            self.now - timedelta(days=1), at_time=self.now))

    def test_future_dated_evidence(self):
        self.assertFalse(_evidence_window_ok(
            self.now + timedelta(days=1),
            self.now + timedelta(days=2), at_time=self.now))

    def test_missing_next_update_fails_closed(self):
        self.assertFalse(_evidence_window_ok(
            self.now - timedelta(minutes=1), None, at_time=self.now))

    def test_invalid_reverse_window(self):
        self.assertFalse(_evidence_window_ok(
            self.now + timedelta(minutes=2),
            self.now - timedelta(minutes=2), at_time=self.now))

    def test_small_clock_skew(self):
        self.assertTrue(_evidence_window_ok(
            self.now + timedelta(minutes=3),
            self.now + timedelta(days=1), at_time=self.now))


if __name__ == "__main__":
    unittest.main()
