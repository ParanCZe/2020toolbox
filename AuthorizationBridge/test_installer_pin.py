"""Guard the production installer against stale payload hashes or version pins."""
import hashlib
import re
import unittest
from pathlib import Path

BASE = Path(__file__).resolve().parent
INSTALLER = BASE / "INSTALL_AND_START.bat"


class InstallerPinTests(unittest.TestCase):
    def test_installer_pins_exact_local_payload_hashes(self):
        script = INSTALLER.read_text(encoding="utf-8-sig")
        actual = {}
        for line in script.splitlines():
            if "Get-FileHash" not in line:
                continue
            file_match = re.search(r"%STAGE%\\([\w.\-]+)", line)
            hash_match = re.search(r"-ne '([0-9a-f]{64})'", line, flags=re.IGNORECASE)
            self.assertIsNotNone(file_match, line)
            self.assertIsNotNone(hash_match, line)
            filename = file_match.group(1)
            self.assertNotIn(filename, actual)
            actual[filename] = hash_match.group(1).lower()

        expected = {
            "authorization_bridge.py",
            "pdf_validator_engine.py",
            "eu_dss_validator.py",
            "INSTALL_EU_DSS.ps1",
            "qualified_tsa_check.py",
            "requirements.txt",
            "find_python.ps1",
            "restart_bridge.ps1",
        }
        self.assertEqual(expected, set(actual))
        for name, recorded_hash in actual.items():
            with self.subTest(file=name):
                calculated = hashlib.sha256((BASE / name).read_bytes()).hexdigest()
                self.assertEqual(recorded_hash, calculated)

    def test_installer_version_and_commit_pin(self):
        script = INSTALLER.read_text(encoding="utf-8-sig")
        version_match = re.search(r'APP_VERSION\s*=\s*"([^"]+)"', (BASE / "authorization_bridge.py").read_text(encoding="utf-8"))
        self.assertIsNotNone(version_match)
        version = version_match.group(1)
        self.assertIn("ExpectedVersion \"" + version + "\"", script)
        self.assertIn("AuthorizationBridge " + version, script)
        pin = re.search(r'set "PAYLOAD_REF=([0-9a-f]{40})"', script)
        self.assertIsNotNone(pin)


if __name__ == "__main__":
    unittest.main()
