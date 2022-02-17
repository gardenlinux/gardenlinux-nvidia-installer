# Changelog - system-services/nvidia-installer


## [1.5.7](https://github.wdf.sap.corp/ICN-ML/aicore/compare/rel/system-services/nvidia-installer/1.5.6...rel/system-services/nvidia-installer/1.5.7)
### other
* nvidia-installer: use foss_images nvidia-gpu-device-plugin and pause images ([#3792](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3792)) ([`60bdaeb`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/60bdaeb245c2ce45749ab7f464dd90b23978bdb5))

### chore
* **ci:** sending jobs to devops dashboard ([#3781](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3781)) ([`77bf0e7`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/77bf0e75be1ef45430e8a0be626349b3ec9884c2))
* **ci:** move to toolkit protecode scan ([#3732](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3732)) ([`bb4dbb0`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/bb4dbb039c18c1d227cbc7e4b7d56cc3f05c37f6))


## [1.5.6](https://github.wdf.sap.corp/ICN-ML/aicore/compare/rel/system-services/nvidia-installer/1.5.5...rel/system-services/nvidia-installer/1.5.6)
### fix
* **nvidia-installer:** Node readiness taint can be removed even if it doesn't exist ([#3702](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3702)) ([`0f3a9e1`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/0f3a9e1f5aa3a71e2bcee6ec75613d5e980be089))


## [1.5.5](https://github.wdf.sap.corp/ICN-ML/aicore/compare/rel/system-services/nvidia-installer/1.5.4...rel/system-services/nvidia-installer/1.5.5)
### chore
* **nvidia-installer:** Update documentation to be a bit clearer ([#3696](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3696)) ([`a1dcf03`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/a1dcf03781c887f940997a0489cf2bfde98f4a5d))


## [1.5.4](https://github.wdf.sap.corp/ICN-ML/aicore/compare/rel/system-services/nvidia-installer/1.5.3...rel/system-services/nvidia-installer/1.5.4)
### other
* Fix the cluster still having eu-central-1 to the new eu-west-1 ([#3579](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3579)) ([`dbfe90d`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/dbfe90d3b93c3fb62a5a3ae446d05af516eb059f))
* nvidia-installer fix: update Helm chart to avoid docker secret name conflict ([#3551](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3551)) ([`69e5e99`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/69e5e997bd00cfa040bf31b06563529ef18e49bc))


## [1.5.3](https://github.wdf.sap.corp/ICN-ML/aicore/compare/rel/system-services/nvidia-installer/1.5.2...rel/system-services/nvidia-installer/1.5.3)
### other
* nvidia-installer feature: add Garden Linux 576.1 support ([#3533](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3533)) ([`b6420eb`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/b6420eb56d71022b9b8094120423b15a292aef4f))
* Dynamically create multiple Xmake builds from a single variant ([#3481](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3481)) ([`bb67a54`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/bb67a54feee79d0c1712e5524114800a77829bb4))

### chore
* **ci:** change piper version to allow deprecated xmake trigger ([#3497](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3497)) ([`ed0005f`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/ed0005f260bac2bc4ae959d910e34f06244660df))
* **ci:** migrate to ops-jenkins ([#3427](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3427)) ([`a6a0ca0`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/a6a0ca0917c985e50c81de72a44f0f22d5d2ebf1))


## [1.5.2](https://github.wdf.sap.corp/ICN-ML/aicore/compare/rel/system-services/nvidia-installer/1.5.1...rel/system-services/nvidia-installer/1.5.2)
### other
* Another attempt to fix the nvidia image scans ([#3474](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3474)) ([`4ac0697`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/4ac0697d6a1fb986c41ded02f9f05e9b31ef3d7f))


## [1.5.1](https://github.wdf.sap.corp/ICN-ML/aicore/compare/rel/system-services/nvidia-installer/1.5.0...rel/system-services/nvidia-installer/1.5.1)
### other
* Fix image scans for nvidia-installer ([#3468](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3468)) ([`c5032fe`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/c5032fe6a9a913c696173a11307f0c1da4092505))


## 1.5.0
### chore
* **all:** docker.wdf.sap.corp:50000 to public.int.repositories.cloud.sap ([#3465](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3465)) ([`2f8554d`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/2f8554d82ae24522f35758d47e7046c21e4ff013))
* nvidia-installer release for Garden Linux 184.0 (3rd time lucky) ([#3341](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3341)) ([`a762eaf`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/a762eaf843585ffa0061394bf5f1f578c620f1bf))
* nvidia-installer release for Garden Linux 184.0 (fix) ([#3339](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3339)) ([`c45dd0a`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/c45dd0a38d1e850f0eb75006eb5004763b7132ba))
* nvidia-installer release for Garden Linux 184.0 ([#3336](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3336)) ([`daad7a9`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/daad7a92e8c3789ccb9adebda5f463912b04887e))

### other
* Fold gardenlinux-dev image into nvidia-installer ([#3467](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3467)) ([`24a25a4`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/24a25a4a88b377f7cc58ba863f283105d27b5dc8))
* Refactor nvidia installer ([#3456](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3456)) ([`b970c64`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/b970c64566a0ce82eb623226ab26208214db85bf))
* Fix nvidia-installer "push helm chart" stage ([#3445](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3445)) ([`2e0c265`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/2e0c265550ce59d03950b7f955f8e1170cafa273))
* Create nvidia-installer images per driver version ([#3423](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3423)) ([`677dd3c`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/677dd3c445c2e740c1d5f3c8dd224dd440188170))
* remove unwanted line ([#3381](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3381)) ([`0a9b2d3`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/0a9b2d3f5aa8f9c165339a105d709dc51549806f))
* add protecode scan for nvidia installer ([#3240](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3240)) ([`7b328c1`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/7b328c1261901be669ab7aa26aaff5b7ad6d3d65))
* Fix nvidia-installer image name to fix whitesource ([#3310](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3310)) ([`2c2971a`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/2c2971aba1d60277524377619a4b5fb0918b1f5b))
* Generate the correct image name & tag in nvidia-installer chart ([#3306](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3306)) ([`2a6a00a`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/2a6a00ad52d48a470d26cb2a7ebb73ba0c4577ca))
* Add static tests for nvidia-installer ([#3302](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3302)) ([`410cca3`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/410cca392f26e07931df51c76a13e4cd15d17888))

### feature
* **mono:** automatic releases ([#3377](https://github.wdf.sap.corp/ICN-ML/aicore/pull/3377)) ([`5ea517a`](https://github.wdf.sap.corp/ICN-ML/aicore/commit/5ea517ae9a987811e08664b2a3d20abe1efb138f))

