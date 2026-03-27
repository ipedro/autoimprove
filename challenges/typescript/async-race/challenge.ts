// TypeScript Challenge: Async Race Conditions
// Fix the race conditions in this async caching layer.
// Assumes `fetch` is available as a global (browser or Node 18+).

const cache = new Map<string, { value: unknown; expiresAt: number }>();

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${url}`);
  return res.json() as Promise<T>;
}

// BUG: TOCTOU race — cache check and cache write are separated by `await fetchJson(url)`.
// Two concurrent calls for the same URL both miss the cache, both call fetchJson,
// and both write to the cache. The second write silently overwrites the first.
async function cachedFetch<T>(url: string, ttlMs: number): Promise<T> {
  const entry = cache.get(url);
  if (entry && entry.expiresAt > Date.now()) {
    return entry.value as T;
  }

  const value = await fetchJson<T>(url); // BUG: TOCTOU race — another call may fetch concurrently
  cache.set(url, { value, expiresAt: Date.now() + ttlMs });
  return value;
}

// BUG: mutating Map during iteration — deleting entries inside forEach while iterating.
// In JavaScript, Map.prototype.forEach is defined to visit all entries present at the
// start of iteration, but deleting during iteration can cause unexpected behavior in
// some engine implementations and is considered unsafe practice.
function purgeExpired(): number {
  const now = Date.now();
  let purged = 0;
  cache.forEach((entry, key) => {
    if (entry.expiresAt <= now) {
      cache.delete(key); // BUG: mutating Map during iteration
      purged++;
    }
  });
  return purged;
}

// CORRECT: batch fetch with deduplication using a pending-promise map.
const inflight = new Map<string, Promise<unknown>>();

async function batchFetch<T>(urls: string[], ttlMs: number): Promise<T[]> {
  return Promise.all(
    urls.map((url) => {
      const entry = cache.get(url);
      if (entry && entry.expiresAt > Date.now()) {
        return entry.value as T;
      }
      if (!inflight.has(url)) {
        const p = fetchJson<T>(url).then((value) => {
          cache.set(url, { value, expiresAt: Date.now() + ttlMs });
          inflight.delete(url);
          return value;
        });
        inflight.set(url, p);
      }
      return inflight.get(url) as Promise<T>;
    })
  );
}

// CORRECT: read-only stats — no mutation.
function getCacheStats(): { size: number; expired: number; live: number } {
  const now = Date.now();
  let expired = 0;
  cache.forEach((entry) => {
    if (entry.expiresAt <= now) expired++;
  });
  return { size: cache.size, expired, live: cache.size - expired };
}
