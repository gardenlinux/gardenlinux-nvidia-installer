# Cluster-native, component-free observability for the driver cache

The Driver Cache ships no monitoring components of its own in v1. It emits good signals and leaves scraping and alerting wiring to whoever operates the cluster, documented as runbook hooks. No `ServiceMonitor`, `PodMonitor`, or `PrometheusRule` is part of the Helm chart.

The one signal shipped is the **Cache-decision Log Signal**: a single structured, greppable log line emitted by `load_install_gpu_driver.sh` at each cache-decision outcome — Cache Hit, Cache Miss → compiled, Compile-failure Fallback → hit, Compile-failure Fallback → timeout — with the Cache Key stamped in. This is guaranteed to exist via `kubectl logs` regardless of what monitoring stack (if any) the cluster runs, and answers the primary field question ("was this driver pulled or compiled?") on its own.

`distribution`'s Prometheus metrics port `:5001` is **not exposed as a Service** in v1. This amends [ADR 0001 / issue #407](https://github.com/gardenlinux/gardenlinux-nvidia-installer/issues/407), which had the port exposed. A plain-HTTP `:5001` is the same kind of exposure that drove mutual TLS on `:5000` ([ADR 0003](0003-mtls-for-driver-cache.md)); under the no-plain-HTTP compliance rule it would invite a finding for a consumer that does not exist in v1. TLS-ing it would require a server cert *and* a client cert for a scraper we do not ship. The listener is left unexposed; the Cache-decision Log Signal carries v1 observability.

A full PVC remains graceful degradation (Write-back is non-fatal — nodes still compile and run), but the operator must be alerted so they can run the manual GC runbook ([#408](https://github.com/gardenlinux/gardenlinux-nvidia-installer/issues/408)) or expand the PVC. The recommended signal is the kubelet-native `kubelet_volume_stats_available_bytes` / `kubelet_volume_stats_used_bytes` metric — present for every PVC, needing no `:5001` — with a documented ~85%-full alert expression. This is shipped as a runbook note, not a `PrometheusRule`.

This posture is consistent with the effort's standing line against new components ([ADR 0002](0002-all-compile-last-write-wins.md); the rejected eviction component in #408) and avoids betting on a prometheus-operator stack we do not own — Gardener's shoot Prometheus targets control-plane and system components, not arbitrary user-namespace services.

## Considered options

- **Ship `ServiceMonitor` + `PrometheusRule` in the chart**: rejected — assumes a prometheus-operator stack present in the target cluster, which we cannot count on; adds components the effort has consistently avoided.
- **Pod-emitted Prometheus metric or Kubernetes Event for hit/miss**: rejected — marginal gain over a structured log line; a metric needs a scrape path we do not ship, an Event adds API-server writes and RBAC.
- **Expose `:5001` plain-HTTP inside the NetworkPolicy boundary**: rejected — a compliance exposure for a consumer that does not exist in v1.
- **TLS `:5001`**: rejected for v1 — needs a server cert and a client cert for an absent scraper; deferred as documented future work.
- **distribution's own storage metric for the PVC alert**: rejected — needs `:5001`, which is unexposed; the kubelet volume metric measures the volume directly and exists regardless.
- **Cluster-native log signal + documented runbook hooks**: adopted.
