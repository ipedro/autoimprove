#!/usr/bin/env python3
"""D1 — Caching strategy for a read-heavy web service."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import init_domain, cli_main

DOMAIN = {
    "id": "D1",
    "problem": "Design a caching strategy for a read-heavy web service to reduce primary database load.",
    "environment": """Service runs as 8 stateless replicas behind a load balancer on Kubernetes.
PostgreSQL primary is the system of record (4 vCPU, 16GB, read IOPS at 60% ceiling).
Prometheus + Grafana for metrics. Service mesh (Istio) provides mTLS and retries.
No existing cache infrastructure. Network latency within cluster <1ms p99.
Deploy pipeline rolls replicas 1-at-a-time; no blue/green.""",
    "options": {
        # semantic keys are the MEE category per-option — preserved exactly
        "in-process-private":     "In-process LRU cache per instance (each replica holds its own copy, no coordination)",
        "out-of-process-shared":  "Shared out-of-process caching cluster accessed over the network (coordinated across replicas)",
        "source-replica":         "Read-replica database with connection pooling (read path hits a replica of the system of record)",
    },
    # MEE categories per §2.1 — maps semantic keys directly to the 4-category taxonomy
    "categories": ["in-process-private", "out-of-process-shared", "source-replica", "recompute-on-demand"],
    "semantic_to_category": {
        "in-process-private":    "in-process-private",
        "out-of-process-shared": "out-of-process-shared",
        "source-replica":        "source-replica",
    },
    "target_category": "out-of-process-shared",
    "banned_tokens": [
        "redis", "memcached", "lru", "cdn", "cache", "ttl", "eviction",
        "invalidation", "hazelcast", "ignite",
    ],
    "alts": {
        8: ("D", "Recompute on demand for every request (no cached state)"),
        9: ("E", "Hierarchical tiered storage combining per-replica local copies with a coordinating upstream store"),
    },
}

init_domain(DOMAIN, os.path.dirname(os.path.abspath(__file__)))

if __name__ == "__main__":
    cli_main(sys.argv)
