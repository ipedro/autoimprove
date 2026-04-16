#!/usr/bin/env python3
"""D2 — Schema migration on a 50M-row production table."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import init_domain, cli_main

DOMAIN = {
    "id": "D2",
    "problem": "Migrate a schema change on a 50M-row production table under active write load.",
    "environment": """Primary PostgreSQL 15, 50M-row table under active write load (~200 writes/sec).
Write downtime tolerance: 5 minutes planned maintenance window max.
Read replicas exist (2 async). Logical replication available.
No CDC pipeline. No event log. Application code controlled by same team.
Rollback SLA: 10 minutes from detection. Customer-facing — errors visible.""",
    "options": {
        "lock-and-mutate":          "In-place schema change with an exclusive write lock held for the duration of the mutation",
        "parallel-build-then-swap": "Build a parallel copy of the table in the background, then atomically swap it in to replace the original",
        "incremental-reconcile":    "Dual-write to old and new columns simultaneously with an asynchronous backfill reconciling the two",
    },
    "categories": ["lock-and-mutate", "parallel-build-then-swap", "incremental-reconcile", "rebuild-from-log"],
    "semantic_to_category": {
        "lock-and-mutate":          "lock-and-mutate",
        "parallel-build-then-swap": "parallel-build-then-swap",
        "incremental-reconcile":    "incremental-reconcile",
    },
    "target_category": "parallel-build-then-swap",
    "banned_tokens": [
        "flyway", "liquibase", "alembic", "gh-ost", "pt-online-schema-change",
    ],
    "alts": {
        8: ("D", "Replay the database's write-ahead log into a new table structure (no explicit rebuild)"),
        9: ("E", "Hybrid of lock-and-mutate for small tables and parallel-build for large ones, chosen per-change"),
    },
}

init_domain(DOMAIN, os.path.dirname(os.path.abspath(__file__)))

if __name__ == "__main__":
    cli_main(sys.argv)
