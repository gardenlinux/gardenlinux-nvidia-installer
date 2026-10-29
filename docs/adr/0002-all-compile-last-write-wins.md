# All-compile last-write-wins write-back (no distributed lock)

On a scale-up where N nodes share the same cache key and the Driver Cache is cold, every node compiles independently and pushes its result. The `distribution` registry accepts idempotent pushes of identical content, so concurrent pushes of the same tag are safe. We explicitly rejected a distributed lock (ConfigMap-based or etcd annotation) despite the apparent waste of N parallel compilations.

The "waste" is bounded: it happens exactly once per (kernel-release, driver-patch-version, kernel-module-type, arch) tuple per cluster lifetime. All subsequent scale-ups on the same tuple hit the warm cache. A lock does not improve startup time for the first cold scale-up — the fastest node still blocks all others until it finishes — and it introduces failure modes (lock-holder crash, TTL misconfiguration, stuck waiters) that are operationally worse than a one-time redundant compile.

## Considered options

- **Distributed lock (ConfigMap/annotation)**: rejected — adds coordination complexity and stuck-waiter risk without improving worst-case startup time.
- **Optimistic post-compile re-check (option c)**: considered for large N; deferred — adds a test path without meaningful benefit below N≈20, and the compile-failure fallback already covers the partial-outage case more naturally.
- **All-compile, last-write-wins**: adopted.
