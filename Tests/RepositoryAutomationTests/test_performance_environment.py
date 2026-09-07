import importlib.util
import json
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/performance_environment.py"
SPEC = importlib.util.spec_from_file_location("performance_environment", SCRIPT)
ENVIRONMENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENVIRONMENT)


class PerformanceEnvironmentTests(unittest.TestCase):
    def testOnlyPowerConditionsAreRetained(self):
        raw = ("Now drawing from 'AC Power'\n"
               " -InternalBattery-0 (id=987654321)\t98%; charging; 0:12 remaining present: true\n"
               " -Private UPS Name (id=123456789) 80%; discharging; 1:00 remaining")
        result = ENVIRONMENT.power_summary(raw)
        self.assertEqual(result, {"source": "AC Power", "batteryPercent": 98,
                                  "batteryState": "charging"})
        encoded = json.dumps(result)
        for private in ["987654321", "123456789", "Private UPS Name", "remaining"]:
            self.assertNotIn(private, encoded)

    def testDesktopAndUnknownFormatsDoNotCopyRawData(self):
        self.assertEqual(ENVIRONMENT.power_summary("Now drawing from 'AC Power'"),
                         {"source": "AC Power", "batteryPercent": None, "batteryState": None})
        self.assertEqual(ENVIRONMENT.power_summary("Private Device Name: unexpected data"),
                         {"source": None, "batteryPercent": None, "batteryState": None})

    def testInvalidPercentAndUnknownChargingStateRemainUnknown(self):
        result = ENVIRONMENT.power_summary(
            "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=5) 101%; future state;")
        self.assertEqual(result, {"source": "Battery Power", "batteryPercent": None,
                                  "batteryState": None})


if __name__ == "__main__":
    unittest.main()
