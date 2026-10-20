"""Regression tests: local AuthorizationBridge never becomes a public signing API."""
import unittest
import authorization_bridge as bridge


class LocalBridgeAccessTests(unittest.TestCase):
    def setUp(self):
        self.client = bridge.app.test_client()

    def test_bridge_binds_only_to_loopback(self):
        self.assertEqual("127.0.0.1", bridge.HOST)

    def test_external_origin_cannot_get_session(self):
        r = self.client.get("/session", headers={"Origin": "https://evil.example"})
        self.assertEqual(403, r.status_code)

    def test_missing_origin_cannot_get_session(self):
        r = self.client.get("/session")
        self.assertEqual(403, r.status_code)

    def test_missing_origin_cannot_sign_even_with_token(self):
        r = self.client.post("/sign-batch-test", headers={
            "X-20-20-Session": bridge._SESSION_TOKEN,
        })
        self.assertEqual(403, r.status_code)

    def test_untrusted_origin_cannot_sign_even_with_token(self):
        r = self.client.post("/sign-batch-test", headers={
            "Origin": "https://evil.example",
            "X-20-20-Session": bridge._SESSION_TOKEN,
        })
        self.assertEqual(403, r.status_code)

    def test_status_native_healthcheck_works(self):
        r = self.client.get("/status")
        self.assertEqual(200, r.status_code)


if __name__ == "__main__":
    unittest.main()
