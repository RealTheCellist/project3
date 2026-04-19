import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.whisper_stt import STTResult, STTServiceError


class STTEndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    @patch("app.main.transcribe_audio_file")
    def test_stt_success(self, mock_transcribe):
        mock_transcribe.return_value = STTResult(
            transcript="테스트 전사 결과",
            provider="faster_whisper",
            profile="fast",
            model_name="tiny",
            device="cpu",
            compute_type="int8",
            duration_ms=123,
        )
        files = {"file": ("sample.wav", b"fake-audio-bytes", "audio/wav")}

        res = self.client.post("/stt?language=ko&profile=fast", files=files)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["transcript"], "테스트 전사 결과")
        self.assertEqual(data["provider"], "faster_whisper")
        self.assertEqual(data["profile"], "fast")
        self.assertEqual(data["model_name"], "tiny")
        self.assertIn("duration_ms", data)

    def test_stt_empty_file(self):
        files = {"file": ("empty.wav", b"", "audio/wav")}
        res = self.client.post("/stt?language=ko", files=files)
        self.assertEqual(res.status_code, 400)

    @patch("app.main.transcribe_audio_file")
    def test_stt_error_code_payload(self, mock_transcribe):
        mock_transcribe.side_effect = STTServiceError(
            "transcription_failed", "mock fail"
        )
        files = {"file": ("sample.wav", b"fake-audio-bytes", "audio/wav")}
        res = self.client.post("/stt?language=ko", files=files)
        self.assertEqual(res.status_code, 503)
        detail = res.json().get("detail", {})
        self.assertEqual(detail.get("code"), "transcription_failed")
        self.assertEqual(detail.get("message"), "mock fail")

    def test_stt_config_endpoint(self):
        res = self.client.get("/stt/config?profile=balanced")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("provider", data)
        self.assertEqual(data["profile"], "balanced")
        self.assertIn("beam_size", data)

    @patch("app.main.transcribe_audio_file")
    def test_stt_auto_profile_with_network(self, mock_transcribe):
        mock_transcribe.return_value = STTResult(
            transcript="auto profile transcript",
            provider="faster_whisper",
            profile="balanced",
            model_name="small",
            device="cpu",
            compute_type="int8",
            duration_ms=99,
        )
        files = {"file": ("sample.wav", b"fake-audio-bytes", "audio/wav")}

        res = self.client.post("/stt?language=ko&profile=auto&network=good", files=files)
        self.assertEqual(res.status_code, 200)
        mock_transcribe.assert_called_once()
        kwargs = mock_transcribe.call_args.kwargs
        self.assertEqual(kwargs["profile"], "auto")
        self.assertEqual(kwargs["network_quality"], "good")

    def test_stt_profiles_endpoint(self):
        res = self.client.get("/stt/profiles")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("profiles", data)
        self.assertIn("fast", data["profiles"])
        self.assertIn("balanced", data["profiles"])
        self.assertIn("accurate", data["profiles"])


if __name__ == "__main__":
    unittest.main()
