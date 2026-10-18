"""Synthetic smoke tests for the no-network experimental colour ablation.

Run:
  python -m unittest discover -s Tools/AutoMetadataBench/tests -p 'test_white_balance_ablation.py'
"""
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from white_balance_ablation import (  # noqa: E402
    codex_family,
    corrected_pixels,
    estimate_illuminant_gain,
    majority_family,
)


def scene(background, foreground):
    rgb = np.empty((40, 40, 3), dtype=np.uint8)
    rgb[:, :] = background
    mask = np.zeros((40, 40), dtype=bool)
    mask[10:30, 10:30] = True
    rgb[mask] = foreground
    return rgb, mask


class WhiteBalanceAblationTests(unittest.TestCase):
    def test_cool_black_fixture_is_navy_without_correction(self):
        self.assertEqual(codex_family(0.12, 0.13, 0.17), "navy")

    def test_cool_tinted_neutral_background_can_correct_a_dark_black_fixture(self):
        rgb, mask = scene((195, 199, 225), (30, 33, 43))
        baseline = majority_family(corrected_pixels(rgb, mask, "original")[0])
        corrected, applied = corrected_pixels(rgb, mask, "gray-world")
        self.assertTrue(applied)
        self.assertEqual(baseline, "navy")
        self.assertEqual(majority_family(corrected), "black")

    def test_neutral_background_does_not_erase_truly_navy_fabric(self):
        rgb, mask = scene((210, 210, 210), (35, 42, 70))
        for method in ("gray-world", "white-patch"):
            corrected, applied = corrected_pixels(rgb, mask, method)
            self.assertTrue(applied)
            self.assertEqual(majority_family(corrected), "navy")

    def test_bright_colored_background_is_not_used_as_neutral_illuminant(self):
        rgb, mask = scene((200, 45, 30), (30, 33, 43))
        for method in ("gray-world", "white-patch"):
            self.assertIsNone(estimate_illuminant_gain(rgb, mask, method))
            corrected, applied = corrected_pixels(rgb, mask, method)
            self.assertFalse(applied)
            self.assertEqual(majority_family(corrected), "navy")

    def test_sparse_mask_abstains_instead_of_just_guessing(self):
        rgb, mask = scene((195, 199, 225), (30, 33, 43))
        mask[:] = False
        mask[0:2, 0:3] = True
        colors, applied = corrected_pixels(rgb, mask, "gray-world")
        self.assertIsNone(colors)
        self.assertFalse(applied)
        self.assertIsNone(majority_family(colors))

    def test_gain_bounds_prevent_unbounded_color_correction(self):
        rgb, mask = scene((100, 140, 150), (30, 33, 43))
        gain = estimate_illuminant_gain(rgb, mask, "gray-world")
        self.assertIsNotNone(gain)
        self.assertAlmostEqual(float(gain[0]), 1.30, places=10)
        self.assertTrue(np.all(gain >= 1 / 1.30))
        self.assertTrue(np.all(gain <= 1.30))


if __name__ == "__main__":
    unittest.main()
