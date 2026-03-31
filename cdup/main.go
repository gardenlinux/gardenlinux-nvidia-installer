package main

import (
	"context"
	"fmt"
	"os"

	"github.com/mitchellh/mapstructure"
)

const (
	uploadRepo        = "europe-docker.pkg.dev/gardener-project/releases"
	nvidiaRepo        = "github.com/gardenlinux/gardenlinux-nvidia-installer"
	componentProvider = "SAP SE"
	githubRepoURL     = "https://" + nvidiaRepo
	repoSuffix        = "/component-descriptors/" + nvidiaRepo
)

func parseConfig[CONFIG any](cfg map[string]any, config *CONFIG) error {
	err := mapstructure.Decode(cfg, &config)
	if err != nil {
		return fmt.Errorf("invalid configuration: %w", err)
	}

	return nil
}

func parseCredentials[CREDS any](rawCreds map[string]any, creds *CREDS) error {
	err := mapstructure.Decode(rawCreds, creds)
	if err != nil {
		return fmt.Errorf("invalid credentials: %w", err)
	}

	return nil
}

func main() {
	cd, err := buildComponentDescriptor([]image{
		{
			Arch:                "amd64",
			OSVersion:           "1877.13",
			KernelVersion:       "6.12.74",
			KernelFlavor:        "cloud",
			NvidiaDriverVersion: "590.48.01",
		},
	}, "1.2.1", "f5d498f1e4311e83c08834c5e906540661d8bb1b", "ghcr.io/gardenlinux/gardenlinux-nvidia-installer/1.2.1/driver")
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	var y []byte
	y, err = cd.ToYAML()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	fmt.Println(string(y))

	v := &vault{
		activeCreds:   make(map[credsID]vaultCreds),
		activeSecrets: make(map[string]vaultSecret),
		events:        make(chan vaultWatchEvent),
		closeCh:       make(chan struct{}),
		errCh:         make(chan struct{}),
	}
	err = v.SetCredsConfig(context.Background(), map[string]any{
		"server":    "https://vault.tools.sap",
		"namespace": "gardnlinux",
		"token":     os.Getenv("VAULT_TOKEN"),
	})
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	o := &oci{}

	ociCfg := map[string]any{
		"config":     "gardenlinux",
		"repository": "europe-docker.pkg.dev/sap-se-gcp-gardenlinux/tests",
	}
	// ociCfg := map[string]any{
	// 	"config": "gardener",
	// 	"repository": "europe-docker.pkg.dev/gardener-project/releases",
	// }

	err = o.SetOCMConfig(context.Background(), v, ociCfg)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	err = o.PublishComponentDescriptor(context.Background(), "1.2.1", y)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	err = o.Close()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	err = v.Close()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
