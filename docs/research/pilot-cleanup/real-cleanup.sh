#!/bin/bash
# real-cleanup.sh — wrapper that invokes the production cleanup script
#
# The fixture harness runs the implementation in a temp repo, so we need
# to invoke the real script by absolute path.

SCRIPT_DIR="/Users/pedro/Developer/autoimprove/scripts"
bash "$SCRIPT_DIR/cleanup-worktrees.sh"
