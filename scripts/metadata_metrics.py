"""Summarize device-harness JSON; never substitutes synthetic data for model accuracy."""
import argparse
import json
import math
from pathlib import Path

FIELDS = ("category", "subtype", "length", "primaryColor", "secondaryColor")


def summarize(rows):
    if not rows:
        raise ValueError("A benchmark requires labelled observations")
    if any(row.get("semanticStatus") == "unavailable" for row in rows):
        raise ValueError("Model unavailable; this is not a classification benchmark")
    times = [row["milliseconds"] for row in rows]
    if any(not isinstance(t, (int, float)) or not math.isfinite(t) or t < 0 for t in times):
        raise ValueError("Latency must be finite and nonnegative")
    times.sort()
    result = {"count": len(rows), "p50_ms": times[math.ceil(.5 * len(times)) - 1],
              "p95_ms": times[math.ceil(.95 * len(times)) - 1], "fields": {}}
    warm = sorted(row["milliseconds"] for row in rows if row.get("cold") is False)
    result["cold_ms"] = [row["milliseconds"] for row in rows if row.get("cold") is True]
    result["warm_p50_ms"] = warm[math.ceil(.5 * len(warm)) - 1] if warm else None
    result["warm_p95_ms"] = warm[math.ceil(.95 * len(warm)) - 1] if warm else None
    for field in FIELDS:
        eligible = [row for row in rows if field in row["expected"]]
        suggested = [row for row in eligible if row["predicted"].get(field) is not None]
        correct = sum(row["predicted"].get(field) == row["expected"][field] for row in suggested)
        result["fields"][field] = {
            "labelled": len(eligible), "suggested": len(suggested),
            "accuracy_all": correct / len(eligible) if eligible else None,
            "accuracy_suggested": correct / len(suggested) if suggested else None,
            "coverage": len(suggested) / len(eligible) if eligible else None,
            "correction_rate": 1 - correct / len(suggested) if suggested else None,
        }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("observations", type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(json.loads(args.observations.read_text())), indent=2, allow_nan=False))
