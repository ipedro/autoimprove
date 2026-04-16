#!/usr/bin/env python3
"""D3 — Retry strategy for a flaky external API."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import init_domain, cli_main

DOMAIN = {
    "id": "D3",
    "problem": "Design a retry strategy for a flaky external API with periodic failure-rate spikes.",
    "environment": """API consumed: third-party payment processor. p99 latency 500ms, failure rate
spikes to 30% during their deploys (weekly, unannounced). No webhook/callback
from them. Our service processes 50 req/sec peak. Idempotency keys are supported.
Redis available for shared state. Ops team on-call 24/7 for P1; P2 batched.
User-facing latency budget 1.5s p95. Failed request cost: blocked checkout.""",
    "options": {
        "time-only":           "Exponentially-increasing delay between retry attempts with random variation added (decision driven by elapsed time only)",
        "failure-rate-state":  "Stateful controller that stops attempts when the aggregate failure rate crosses a threshold and periodically probes to test if the downstream is healthy again",
        "deferred-delegation": "On failure, enqueue to a persistent queue for later manual or batch replay (the retry decision is deferred to a human or separate job)",
    },
    "categories": ["time-only", "failure-rate-state", "deferred-delegation", "parallel-fallback"],
    "semantic_to_category": {
        "time-only":           "time-only",
        "failure-rate-state":  "failure-rate-state",
        "deferred-delegation": "deferred-delegation",
    },
    "target_category": "failure-rate-state",
    "banned_tokens": [
        "tenacity", "retry", "backoff", "circuit", "hystrix", "resilience4j",
        "polly", "jitter",
    ],
    "alts": {
        8: ("D", "Fan out the request to multiple providers concurrently and use the fastest non-error response"),
        9: ("E", "Adaptive hybrid combining stateful threshold detection with time-based backoff between attempts"),
    },
}

init_domain(DOMAIN, os.path.dirname(os.path.abspath(__file__)))

if __name__ == "__main__":
    cli_main(sys.argv)
