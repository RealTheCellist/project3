import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app.services.whisper_stt import get_stt_runtime_config


class STTRuntimeConfigTests(unittest.TestCase):
    def test_uses_recommendation_file_when_env_profile_absent(self):
        with tempfile.TemporaryDirectory() as td:
            rec_path = Path(td) / "stt_recommendation.json"
            rec_path.write_text(
                json.dumps({"recommended_profile": "fast"}, ensure_ascii=False),
                encoding="utf-8",
            )
            with patch.dict(
                "os.environ",
                {
                    "STT_PROFILE": "",
                    "STT_RECOMMENDATION_FILE": str(rec_path),
                },
                clear=False,
            ):
                cfg = get_stt_runtime_config()
                self.assertEqual(cfg.profile, "fast")

    def test_env_profile_has_priority_over_recommendation_file(self):
        with tempfile.TemporaryDirectory() as td:
            rec_path = Path(td) / "stt_recommendation.json"
            rec_path.write_text(
                json.dumps({"recommended_profile": "fast"}, ensure_ascii=False),
                encoding="utf-8",
            )
            with patch.dict(
                "os.environ",
                {
                    "STT_PROFILE": "accurate",
                    "STT_RECOMMENDATION_FILE": str(rec_path),
                },
                clear=False,
            ):
                cfg = get_stt_runtime_config()
                self.assertEqual(cfg.profile, "accurate")

    def test_auto_profile_uses_rules_and_review_override(self):
        with tempfile.TemporaryDirectory() as td:
            rules_path = Path(td) / "stt_autoselect_rules.json"
            review_path = Path(td) / "stt_profile_review.json"
            rules_path.write_text(
                json.dumps(
                    {
                        "preferred_default": "balanced",
                        "network_rules": {"poor": "fast", "normal": "balanced", "good": "accurate"},
                        "fallback_rate_override_threshold": 20.0,
                        "latency_override_threshold_ms": 2200.0,
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            review_path.write_text(
                json.dumps(
                    {
                        "recommended_profile": "fast",
                        "profiles": {
                            "accurate": {"fallback_rate": 35.0, "avg_latency_ms": 2600.0}
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            with patch.dict(
                "os.environ",
                {
                    "STT_PROFILE": "",
                    "STT_AUTOSELECT_RULES_FILE": str(rules_path),
                    "STT_PROFILE_REVIEW_FILE": str(review_path),
                },
                clear=False,
            ):
                cfg = get_stt_runtime_config(profile_override="auto", network_quality="good")
                self.assertEqual(cfg.profile, "fast")

    def test_auto_profile_falls_back_to_balanced_without_files(self):
        with patch.dict(
            "os.environ",
            {
                "STT_PROFILE": "",
                "STT_AUTOSELECT_RULES_FILE": "data/does_not_exist_rules.json",
                "STT_PROFILE_REVIEW_FILE": "data/does_not_exist_review.json",
            },
            clear=False,
        ):
            cfg = get_stt_runtime_config(profile_override="auto", network_quality="normal")
            self.assertEqual(cfg.profile, "balanced")


if __name__ == "__main__":
    unittest.main()
