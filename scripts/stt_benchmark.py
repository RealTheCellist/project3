from __future__ import annotations

import argparse
import csv
import statistics
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List

import httpx


DEFAULT_PROFILES = ("fast", "balanced", "accurate")


@dataclass
class Sample:
    audio_path: Path
    reference: str
    language: str


def load_manifest(path: Path) -> List[Sample]:
    samples: List[Sample] = []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        required = {"audio_path"}
        if not required.issubset(set(reader.fieldnames or [])):
            raise ValueError("Manifest must include 'audio_path' column")

        for row in reader:
            audio_path = Path(str(row.get("audio_path", "")).strip())
            if not audio_path:
                continue
            reference = str(row.get("reference", "") or "").strip()
            language = str(row.get("language", "") or "ko").strip() or "ko"
            samples.append(
                Sample(audio_path=audio_path, reference=reference, language=language)
            )
    return samples


def _levenshtein(a: List[str], b: List[str]) -> int:
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, token_a in enumerate(a, start=1):
        curr = [i]
        for j, token_b in enumerate(b, start=1):
            cost = 0 if token_a == token_b else 1
            curr.append(
                min(
                    prev[j] + 1,  # deletion
                    curr[j - 1] + 1,  # insertion
                    prev[j - 1] + cost,  # substitution
                )
            )
        prev = curr
    return prev[-1]


def word_error_rate(reference: str, hypothesis: str) -> float | None:
    ref_tokens = reference.strip().split()
    hyp_tokens = hypothesis.strip().split()
    if not ref_tokens:
        return None
    distance = _levenshtein(ref_tokens, hyp_tokens)
    return distance / len(ref_tokens)


def run_benchmark(
    base_url: str,
    samples: Iterable[Sample],
    profiles: Iterable[str],
    output_csv: Path,
    timeout_s: float,
) -> None:
    rows: List[Dict[str, object]] = []
    with httpx.Client(timeout=timeout_s) as client:
        for sample in samples:
            if not sample.audio_path.exists():
                rows.append(
                    {
                        "audio_path": str(sample.audio_path),
                        "profile": "",
                        "language": sample.language,
                        "status": "missing_file",
                        "http_status": "",
                        "latency_ms": "",
                        "stt_duration_ms": "",
                        "wer": "",
                        "provider": "",
                        "model_name": "",
                        "transcript": "",
                        "error": "file_not_found",
                    }
                )
                continue

            for profile in profiles:
                started = time.perf_counter()
                try:
                    with sample.audio_path.open("rb") as f:
                        res = client.post(
                            f"{base_url.rstrip('/')}/stt",
                            params={"language": sample.language, "profile": profile},
                            files={
                                "file": (
                                    sample.audio_path.name,
                                    f,
                                    "audio/wav",
                                )
                            },
                        )
                    latency_ms = int((time.perf_counter() - started) * 1000)

                    if res.status_code >= 400:
                        rows.append(
                            {
                                "audio_path": str(sample.audio_path),
                                "profile": profile,
                                "language": sample.language,
                                "status": "error",
                                "http_status": res.status_code,
                                "latency_ms": latency_ms,
                                "stt_duration_ms": "",
                                "wer": "",
                                "provider": "",
                                "model_name": "",
                                "transcript": "",
                                "error": res.text.strip(),
                            }
                        )
                        continue

                    body = res.json()
                    transcript = str(body.get("transcript", "")).strip()
                    wer = word_error_rate(sample.reference, transcript)

                    rows.append(
                        {
                            "audio_path": str(sample.audio_path),
                            "profile": profile,
                            "language": sample.language,
                            "status": "ok",
                            "http_status": res.status_code,
                            "latency_ms": latency_ms,
                            "stt_duration_ms": body.get("duration_ms", ""),
                            "wer": "" if wer is None else round(wer, 4),
                            "provider": body.get("provider", ""),
                            "model_name": body.get("model_name", ""),
                            "transcript": transcript,
                            "error": "",
                        }
                    )
                except Exception as err:
                    latency_ms = int((time.perf_counter() - started) * 1000)
                    rows.append(
                        {
                            "audio_path": str(sample.audio_path),
                            "profile": profile,
                            "language": sample.language,
                            "status": "exception",
                            "http_status": "",
                            "latency_ms": latency_ms,
                            "stt_duration_ms": "",
                            "wer": "",
                            "provider": "",
                            "model_name": "",
                            "transcript": "",
                            "error": str(err),
                        }
                    )

    output_csv.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "audio_path",
        "profile",
        "language",
        "status",
        "http_status",
        "latency_ms",
        "stt_duration_ms",
        "wer",
        "provider",
        "model_name",
        "transcript",
        "error",
    ]
    with output_csv.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    print(f"[done] wrote benchmark rows: {output_csv}")
    print_summary(rows)


def print_summary(rows: List[Dict[str, object]]) -> None:
    grouped: Dict[str, List[Dict[str, object]]] = {}
    for row in rows:
        profile = str(row.get("profile", "") or "")
        if not profile:
            continue
        grouped.setdefault(profile, []).append(row)

    if not grouped:
        print("[summary] no profile rows")
        return

    print("[summary]")
    for profile, items in grouped.items():
        ok_items = [r for r in items if r.get("status") == "ok"]
        err_items = [r for r in items if r.get("status") != "ok"]
        latencies = [int(r["latency_ms"]) for r in ok_items if str(r["latency_ms"])]
        wers = [
            float(r["wer"])
            for r in ok_items
            if str(r.get("wer", "")).strip() not in {"", "None"}
        ]

        avg_latency = round(statistics.mean(latencies), 1) if latencies else None
        avg_wer = round(statistics.mean(wers), 4) if wers else None
        print(
            f"- {profile}: ok={len(ok_items)} err={len(err_items)} "
            f"avg_latency_ms={avg_latency} avg_wer={avg_wer}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Benchmark /stt by profile and optional reference WER."
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
        help="CSV file with columns: audio_path,reference(optional),language(optional).",
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8000",
        help="FastAPI base url.",
    )
    parser.add_argument(
        "--profiles",
        default=",".join(DEFAULT_PROFILES),
        help="Comma-separated profiles, e.g. fast,balanced,accurate",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/stt_benchmark_results.csv"),
        help="Output CSV path.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=120.0,
        help="HTTP timeout seconds.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    samples = load_manifest(args.manifest)
    if not samples:
        raise SystemExit("No samples found in manifest.")

    profiles = [p.strip() for p in args.profiles.split(",") if p.strip()]
    if not profiles:
        raise SystemExit("No profiles provided.")

    run_benchmark(
        base_url=args.base_url,
        samples=samples,
        profiles=profiles,
        output_csv=args.output,
        timeout_s=args.timeout,
    )


if __name__ == "__main__":
    main()
