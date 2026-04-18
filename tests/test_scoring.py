import unittest

from app.models.schemas import CheckinRequest, VoiceFeatures
from app.services.scoring import analyze_checkin


class ScoringEngineTests(unittest.TestCase):
    def test_risk_score_formula_applies_expected_weight(self):
        req = CheckinRequest(
            transcript="불안 피곤 압박",
            self_report_stress=4,
            baseline_days=14,
            trend_delta=0.2,
            voice_features=VoiceFeatures(
                speech_rate_delta=0.0,
                silence_ratio_delta=0.0,
                energy_delta=0.0,
            ),
        )
        result = analyze_checkin(req)
        self.assertIn("component_scores", result)
        self.assertGreaterEqual(result["risk_score"], 0)
        self.assertLessEqual(result["risk_score"], 100)
        self.assertEqual(result["recovery_score"], 100 - result["risk_score"])

    def test_learning_mode_enabled_before_14_days(self):
        req = CheckinRequest(
            transcript="오늘은 평온하고 괜찮아요",
            self_report_stress=2,
            baseline_days=5,
            trend_delta=0.0,
        )
        result = analyze_checkin(req)
        self.assertTrue(result["learning_mode"])

    def test_hold_decision_when_confidence_low(self):
        req = CheckinRequest(
            transcript="힘듦",
            self_report_stress=3,
            baseline_days=0,
            trend_delta=0.0,
        )
        result = analyze_checkin(req)
        self.assertTrue(result["hold_decision"])


if __name__ == "__main__":
    unittest.main()
