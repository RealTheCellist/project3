import unittest

from fastapi.testclient import TestClient

from app.main import app


class ApiFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    def test_analyze_and_history(self):
        res = self.client.post(
            "/analyze-checkin",
            json={
                "transcript": "불안 피곤 압박",
                "self_report_stress": 4,
                "baseline_days": 8,
                "trend_delta": 0.2,
            },
        )
        self.assertEqual(res.status_code, 200)

        history = self.client.get("/checkins?limit=5")
        self.assertEqual(history.status_code, 200)
        data = history.json()
        self.assertIn("items", data)
        self.assertGreaterEqual(len(data["items"]), 1)
        self.assertIn("recovery_score", data["items"][0])

    def test_report_summary(self):
        for transcript in ["오늘은 조금 지침", "그래도 회복하려고 노력함"]:
            res = self.client.post(
                "/analyze-checkin",
                json={
                    "transcript": transcript,
                    "self_report_stress": 3,
                    "baseline_days": 7,
                    "trend_delta": 0.1,
                },
            )
            self.assertEqual(res.status_code, 200)

        summary = self.client.get("/report/summary?days=30&limit=100")
        self.assertEqual(summary.status_code, 200)
        payload = summary.json()
        self.assertEqual(payload["days"], 30)
        self.assertIn("total_checkins", payload)
        self.assertIn("avg_recovery_score", payload)
        self.assertIn("avg_risk_score", payload)
        self.assertIn("avg_confidence", payload)
        self.assertIn("confidence_buckets", payload)
        self.assertIn("top_tags", payload)
        self.assertIn("daily_recovery", payload)

    def test_report_export_pdf(self):
        res = self.client.post(
            "/analyze-checkin",
            json={
                "transcript": "PDF export test checkin",
                "self_report_stress": 3,
                "baseline_days": 7,
                "trend_delta": 0.0,
            },
        )
        self.assertEqual(res.status_code, 200)

        export = self.client.get("/report/export-pdf?days=7&limit=100")
        self.assertEqual(export.status_code, 200)
        self.assertEqual(export.headers.get("content-type"), "application/pdf")
        self.assertIn("attachment;", export.headers.get("content-disposition", ""))
        self.assertTrue(export.content.startswith(b"%PDF-1.4"))


if __name__ == "__main__":
    unittest.main()
