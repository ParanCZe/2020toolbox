"""Regression tests for the exact Tomcat XML corruption caused by old installer.

No Java server, network requests, or signing keys used.
"""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import xml.etree.ElementTree as ET

import eu_dss_validator as dss

EXAMPLE = b'''<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005">
  <Service name="Catalina">
    <Connector port="18080" protocol="HTTP/1.1"
               connectionTimeout="20000" / address="127.0.0.1">
  </Service>
</Server>
'''


class DssServerConfigTests(unittest.TestCase):
    def make_config(self, root, contents):
        file = root / "apache-tomcat-11.0.25" / "conf" / "server.xml"
        file.parent.mkdir(parents=True)
        file.write_bytes(contents)
        return file

    def test_known_malformed_connector_is_fixed_and_backed_up(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            config = self.make_config(root, EXAMPLE)
            self.assertTrue(dss.repair_legacy_connector_xml(root))
            fixed = config.read_bytes()
            self.assertIn(b'address="127.0.0.1" />', fixed)
            self.assertNotIn(b'/ address="127.0.0.1">', fixed)
            root_xml = ET.fromstring(fixed)
            connectors = list(root_xml.iter("Connector"))
            self.assertEqual(1, len(connectors))
            self.assertEqual("18080", connectors[0].get("port"))
            self.assertEqual("127.0.0.1", connectors[0].get("address"))
            backup = config.with_name("server.xml.before-2020-repair.bak")
            self.assertEqual(EXAMPLE, backup.read_bytes())
            self.assertFalse(dss.repair_legacy_connector_xml(root))
            self.assertEqual(EXAMPLE, backup.read_bytes())

    def test_already_valid_document_is_never_touched(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            good = EXAMPLE.replace(
                b'/ address="127.0.0.1">', b'address="127.0.0.1" />'
            )
            config = self.make_config(root, good)
            self.assertFalse(dss.repair_legacy_connector_xml(root))
            self.assertEqual(good, config.read_bytes())
            self.assertFalse(config.with_name("server.xml.before-2020-repair.bak").exists())

    def test_unknown_xml_corruption_is_never_changed(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            unknown = EXAMPLE.replace(b'port="18080"', b'port="18081"')
            config = self.make_config(root, unknown)
            self.assertFalse(dss.repair_legacy_connector_xml(root))
            self.assertEqual(unknown, config.read_bytes())

    def test_second_xml_problem_is_not_silently_rewritten(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            broken = EXAMPLE.replace(b'</Service>', b'</Broken>')
            config = self.make_config(root, broken)
            with self.assertRaises(ET.ParseError):
                dss.repair_legacy_connector_xml(root)
            self.assertEqual(broken, config.read_bytes())
            self.assertFalse(config.with_name("server.xml.before-2020-repair.bak").exists())


if __name__ == "__main__":
    unittest.main()
