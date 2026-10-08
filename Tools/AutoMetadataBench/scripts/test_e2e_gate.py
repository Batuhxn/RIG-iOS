import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from e2e import summarize


class E2EGateTests(unittest.TestCase):
    def run_gate(self, mode):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            expected = {"category": "top", "subtype": "shirt"}
            fixtures = [{"id": str(i), "expected": expected, "set": "catalog"} for i in range(3)]
            reference = {f["id"]: expected for f in fixtures}
            obs = [{"id": f["id"], "expected": expected, "predicted": expected,
                    "cold": i == 0, "milliseconds": 1, "semanticStatus": "suggested"}
                   for i, f in enumerate(fixtures)]
            if mode == "partial": obs.pop()
            if mode == "duplicate": obs[-1] = obs[1]
            if mode == "empty": obs = []
            if mode == "abstain":
                for o in obs: o["predicted"] = {}; o["semanticStatus"] = "abstained"
            if mode == "truth": obs[0] = {**obs[0], "expected": {}}
            if mode == "unavailable": obs[0]["semanticStatus"] = "unavailable"
            for name, data in (("manifest", fixtures), ("python_coreml_reference", reference), ("observations", obs)):
                (out / (name + ".json")).write_text(json.dumps(data))
            with contextlib.redirect_stdout(io.StringIO()):
                summarize(out)

    def test_complete(self):
        with self.assertRaises(SystemExit) as result: self.run_gate("complete")
        self.assertEqual(result.exception.code, 0)

    def test_missing_duplicate_empty_truth_and_unavailable_rejected(self):
        for mode in ("partial", "duplicate", "empty", "truth", "unavailable"):
            with self.subTest(mode=mode), self.assertRaises(ValueError): self.run_gate(mode)

    def test_total_abstention_fails_precision_gate(self):
        with self.assertRaises(SystemExit) as result: self.run_gate("abstain")
        self.assertEqual(result.exception.code, 1)


if __name__ == "__main__": unittest.main()
