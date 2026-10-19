"""Rebuild Resources/Models/RIGGarmentPrompts.json for the pinned encoder without re-exporting it.

The manifest's modelID must equal the encoder's rigModelID (the classifier refuses a
mismatch), so it is copied from MODEL_LOCK.json. promptsID versions the prompt set, so a
prompt change ships as a small text diff instead of a new 89 MB model release.
Text vectors come from the same pinned FashionCLIP revision as the encoder.
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from bench import ENSEMBLE, LENGTH_ENSEMBLE, PROMPTS_ID, TEMPLATES, Encoder, ensemble_groups  # noqa: E402
from color_embed import color_groups  # noqa: E402

REPO = HERE.parents[2]

if __name__ == "__main__":
    lock = json.loads((REPO / "Resources/Models/MODEL_LOCK.json").read_text())
    enc = Encoder("fashion-clip")
    groups = ensemble_groups()
    g = {name: [{"label": k, "vector": [round(float(x), 7) for x in enc.text(v)]} for k, v in groups[name].items()]
         for name in ("flat", "length.bottom", "length.dress")}
    g["color"] = [{"label": k, "vector": [round(float(x), 7) for x in enc.text(v)]} for k, v in color_groups()["color"].items()]
    digest = hashlib.sha256(json.dumps({"templates": TEMPLATES, "ensemble": ENSEMBLE, "length": LENGTH_ENSEMBLE,
                                        "color": color_groups()}, sort_keys=True).encode()).hexdigest()[:16]
    manifest = {"version": 2, "modelID": lock["modelID"], "promptsID": f"{PROMPTS_ID}:{digest}",
                "logitScale": 100.0, "threshold": 0.7, "groups": g}
    out = REPO / "Resources/Models/RIGGarmentPrompts.json"
    out.write_text(json.dumps(manifest, separators=(",", ":")))
    print(manifest["modelID"], manifest["promptsID"], out.stat().st_size, "bytes")
