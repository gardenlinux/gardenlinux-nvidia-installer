# Test on Gardener Cluster
This document explains how to run test for nvidia installer
## Prerequisities
Gardener cluster running gpu operator 
## Run Tests
```bash
 helm install gpu-test ./tests -n gpu-test
 helm test gpu-test -n gpu-test --timeout 3m
```

## Example output

```bash
  NAME: gpu-test
  LAST DEPLOYED: Tue Nov  4 09:32:49 2025
  NAMESPACE: gpu-test
  STATUS: deployed
  REVISION: 1
  TEST SUITE:     gpu-driver-test-driver-version
  Last Started:   Tue Nov  4 09:32:59 2025
  Last Completed: Tue Nov  4 09:33:02 2025
  Phase:          Succeeded
  TEST SUITE:     gpu-driver-test-gpu-operator
  Last Started:   Tue Nov  4 09:33:02 2025
  Last Completed: Tue Nov  4 09:33:05 2025
  Phase:          Succeeded
```
