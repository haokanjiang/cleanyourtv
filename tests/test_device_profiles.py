import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILES = ROOT / "launcher" / "app" / "src" / "main" / "assets" / "device-profiles"
COMPONENT = re.compile(r"^[A-Za-z0-9_.]+/(?:\.[A-Za-z0-9_.$]+|[A-Za-z0-9_.$]+)$")


class DeviceProfileTest(unittest.TestCase):
    def test_profiles_are_well_formed(self):
        ids = set()
        files = sorted(PROFILES.glob("*.json"))
        self.assertTrue(files, "at least one device profile is expected")

        for path in files:
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(1, data.get("schema_version"), path)
            profile_id = data.get("id")
            self.assertIsInstance(profile_id, str, path)
            self.assertTrue(profile_id, path)
            self.assertNotIn(profile_id, ids, f"duplicate device profile id {profile_id}")
            ids.add(profile_id)

            match = data.get("match", {})
            self.assertTrue(any(match.get(k) for k in ("manufacturer", "model", "device")),
                            f"{path}: profile must identify a device")

            hidden = data.get("hidden_packages", [])
            self.assertEqual(len(hidden), len(set(hidden)), f"{path}: duplicate hidden package")

            input_ids = set()
            for item in data.get("inputs", []):
                self.assertTrue(item.get("id"), f"{path}: input id is required")
                self.assertNotIn(item["id"], input_ids, f"{path}: duplicate input id {item['id']}")
                input_ids.add(item["id"])
                self.assertTrue(item.get("label"), f"{path}: input label is required")
                self.assertTrue(item.get("action") or item.get("component"),
                                f"{path}: input needs an action or component")
                if item.get("component"):
                    self.assertRegex(item["component"], COMPONENT, f"{path}: bad component")

            settings = data.get("settings", {})
            for name, target in settings.items():
                self.assertTrue(target.get("action") or target.get("component"),
                                f"{path}: settings target {name} is empty")
                if target.get("component"):
                    self.assertRegex(target["component"], COMPONENT, f"{path}: bad settings component")


if __name__ == "__main__":
    unittest.main()
