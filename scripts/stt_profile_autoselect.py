from __future__ import annotations

import argparse
import json
from pathlib import Path


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def choose_profile(
    *,
    network: str,
    rules: dict,
    review: dict,
) -> dict:
    net_rules = rules.get("network_rules", {})
    selected = str(net_rules.get(network, rules.get("preferred_default", "balanced")))
    reason = [f"network={network} -> {selected}"]

    profiles = review.get("profiles", {})
    if selected in profiles:
        selected_stats = profiles[selected]
        fallback_rate = float(selected_stats.get("fallback_rate", 0.0))
        latency = float(selected_stats.get("avg_latency_ms", 0.0))
        fb_threshold = float(rules.get("fallback_rate_override_threshold", 20.0))
        lat_threshold = float(rules.get("latency_override_threshold_ms", 2200.0))
        if fallback_rate > fb_threshold or latency > lat_threshold:
            recommended = str(review.get("recommended_profile", selected))
            if recommended != selected:
                reason.append(
                    f"override: selected profile fallback/latency exceeded threshold "
                    f"({fallback_rate:.2f}%/{latency:.2f}ms), using recommended={recommended}"
                )
                selected = recommended

    return {"profile": selected, "reason": "; ".join(reason)}


def main() -> None:
    parser = argparse.ArgumentParser(description="Auto-select STT profile from network + review data.")
    parser.add_argument("--network", required=True, choices=["poor", "normal", "good"])
    parser.add_argument("--rules", default="data/stt_autoselect_rules.json")
    parser.add_argument("--review-json", required=True)
    parser.add_argument("--output", default="data/stt_autoselect_result.json")
    args = parser.parse_args()

    rules = _load_json(Path(args.rules))
    review = _load_json(Path(args.review_json))
    result = choose_profile(network=args.network, rules=rules, review=review)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

