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


if __name__ == "__main__":
    unittest.main()
