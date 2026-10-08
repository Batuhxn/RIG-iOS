import unittest
from metadata_metrics import summarize


class MetricsTests(unittest.TestCase):
    def test_abstentions_do_not_inflate_accuracy(self):
        report = summarize([
            {"expected": {"category": "top"}, "predicted": {"category": "top"}, "milliseconds": 10},
            {"expected": {"category": "bottom"}, "predicted": {}, "milliseconds": 30},
        ])
        self.assertEqual(report["fields"]["category"]["accuracy_all"], .5)
        self.assertEqual(report["fields"]["category"]["coverage"], .5)
        self.assertEqual(report["fields"]["category"]["accuracy_suggested"], 1)

    def test_empty_dataset_is_not_a_benchmark(self):
        with self.assertRaises(ValueError):
            summarize([])

    def test_inapplicable_length_is_excluded(self):
        report = summarize([{"expected": {"category": "shoes"}, "predicted": {}, "milliseconds": 10}])
        self.assertIsNone(report["fields"]["length"]["accuracy_all"])

    def test_negative_latency_is_rejected(self):
        with self.assertRaises(ValueError):
            summarize([{"expected": {}, "predicted": {}, "milliseconds": -1}])

    def test_missing_model_cannot_be_reported_as_benchmark(self):
        with self.assertRaises(ValueError):
            summarize([{"expected": {}, "predicted": {}, "milliseconds": 5, "semanticStatus": "unavailable"}])

    def test_cold_and_warm_measurements_are_separate(self):
        rows = [{"expected": {}, "predicted": {}, "milliseconds": t, "cold": cold}
                for t, cold in [(1000, True), (10, False), (20, False)]]
        report = summarize(rows)
        self.assertEqual(report["cold_ms"], [1000])
        self.assertEqual(report["warm_p95_ms"], 20)


if __name__ == "__main__":
    unittest.main()
