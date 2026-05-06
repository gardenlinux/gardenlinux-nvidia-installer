package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/goccy/go-yaml"
	"github.com/mitchellh/mapstructure"
	"github.com/spf13/cobra"
)

var version string
var commit string

const (
	uploadRepo        = "europe-docker.pkg.dev/sap-se-gcp-gardenlinux/releases"
	nvidiaRepo        = "github.com/gardenlinux/gardenlinux-nvidia-installer"
	nvidiaRepoIdx     = "github.com/gardenlinux/gardenlinux-nvidia-installer-idx"
	componentProvider = "SAP SE"
	githubRepoURL     = "https://" + nvidiaRepo
	repoSuffix        = "/component-descriptors/" + nvidiaRepo
	repoSuffixIdx     = "/component-descriptors/" + nvidiaRepoIdx
	imagePath         = "ghcr.io/gardenlinux/gardenlinux-nvidia-installer"
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

// VersionsConfig represents the structure of versions.yaml
type VersionsConfig struct {
	OSVersions    []string `yaml:"os_versions"`
	KernelFlavors []string `yaml:"kernel_flavour"`
	CPUArch       []string `yaml:"cpu_arch"`
	NvidiaDrivers []string `yaml:"nvidia_drivers"`
}

// loadVersionsConfig reads and parses the versions.yaml file
func loadVersionsConfig(path string) (*VersionsConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read versions.yaml: %w", err)
	}

	var config VersionsConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse versions.yaml: %w", err)
	}

	return &config, nil
}

// buildImageList creates all combinations of images from the config
func buildImageList(config *VersionsConfig) ([]image, error) {
	var images []image

	var scriptPath = "./resources/extract_kernel_name.sh"
	for _, arch := range config.CPUArch {
		for _, osVersion := range config.OSVersions {
			for _, kernelFlavor := range config.KernelFlavors {
				kernelName, err := extractKernelName(scriptPath, arch, osVersion, kernelFlavor)
				if err != nil {
					return nil, fmt.Errorf("kernel name extraction failed: %w", err)
				}

				for _, nvidiaDriver := range config.NvidiaDrivers {
					images = append(images, image{
						Arch:                arch,
						OSVersion:           fmt.Sprintf("%v", osVersion),
						KernelVersion:       kernelName,
						KernelFlavor:        kernelFlavor,
						NvidiaDriverVersion: nvidiaDriver,
					})
				}
			}
		}
	}
	return images, nil
}

func extractKernelName(path string, targetArch, glVersion, kernelFlavor string) (string, error) {
	// Get current working directory
	pwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("failed to get working directory: %w", err)
	}

	parentDir := filepath.Dir(pwd)

	// Build the docker command
	image := fmt.Sprintf("ghcr.io/gardenlinux/gardenlinux/kmodbuild:%s-%s", targetArch, glVersion)

	cmd := exec.Command("docker", "run", "--rm",
		"-v", parentDir+":/workspace",
		"-w", "/workspace/gardenlinux-nvidia-installer",
		image,
		path,
		kernelFlavor,
	)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err = cmd.Run()
	if err != nil {
		return "", fmt.Errorf("docker command failed: %w, stderr: %s", err, stderr.String())
	}

	// Trim whitespace/newlines from output
	kernelName := strings.TrimSpace(stdout.String())
	return kernelName, nil
}

func main() {
	c := &cobra.Command{
		Use:   "cdup",
		Short: "Component descriptor publisher",
		RunE:  run,
	}

	// Define the version flag
	c.Flags().StringVarP(&version, "version", "v", "", "release version (required)")
	err := c.MarkFlagRequired("version")
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	// Define the version flag
	c.Flags().StringVarP(&version, "commit", "c", "", "Commitish (required)")
	err = c.MarkFlagRequired("commit")
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	if err := c.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func run(cmd *cobra.Command, args []string) error {

	versionsPath := filepath.Join(".", "versions.yaml")

	// Load the configuration
	config, err := loadVersionsConfig(versionsPath)
	if err != nil {
		return fmt.Errorf("version config load failed: %w", err)
	}

	// Build the image list from config
	images, err := buildImageList(config)
	if err != nil {
		return fmt.Errorf("failed to build image list: %w", err)
	}

	cd, err := buildComponentDescriptor(images, version, commit, imagePath+"/"+version+"/driver")
	if err != nil {
		return fmt.Errorf("failed to build component descriptor: %w", err)
	}

	var y []byte
	y, err = cd.ToYAML()
	if err != nil {
		return fmt.Errorf("failed to convert to yaml: %w", err)
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
		return fmt.Errorf("vault authorisation failed: %w", err)
	}
	o := &oci{}

	ociCfg := map[string]any{
		"config":     "gardenlinux",
		"repository": "europe-docker.pkg.dev/sap-se-gcp-gardenlinux/releases",
		"path":       "driver",
	}

	err = o.SetOCMConfig(context.Background(), v, ociCfg)
	if err != nil {
		return fmt.Errorf("failed to set ocm configuration: %w", err)
	}

	//err = o.PublishComponentDescriptor(context.Background(), version, y)
	//if err != nil {
	//	return fmt.Errorf("component descriptor publish failed: %w", err)
	//}

	o = &oci{}

	ociCfg = map[string]any{
		"config":     "gardenlinux",
		"repository": "europe-docker.pkg.dev/sap-se-gcp-gardenlinux/releases",
		"path":       "idx",
	}

	err = o.SetOCMConfig(context.Background(), v, ociCfg)
	if err != nil {
		return fmt.Errorf("failed to set ocm configuration: %w", err)
	}

	latestTag, err := o.GetLatestTag(context.Background())
	if err != nil {
		return fmt.Errorf("cannot get latest tag: %w", err)
	}

	fmt.Println(latestTag)

	newVersion, err := bumpPatch(latestTag)
	if err != nil {
		return fmt.Errorf("failed to bump patch: %w", err)
	}

	updatedDescriptor, err := o.BuildIndexComponentDescriptor(version, newVersion)
	if err != nil {
		return fmt.Errorf("failed to update component descriptor: %w", err)
	}

	var yml []byte
	yml, err = updatedDescriptor.ToYAML()
	if err != nil {
		return fmt.Errorf("failed to convert to yaml: %w", err)
	}
	fmt.Println(string(yml))

	//err = o.PublishComponentDescriptor(context.Background(), newVersion, yml)
	//if err != nil {
	//	return fmt.Errorf("component descriptor publish failed: %w", err)
	//}

	err = o.Close()
	if err != nil {
		return fmt.Errorf("failed to close oci registry: %w", err)
	}

	err = v.Close()
	if err != nil {
		return fmt.Errorf("failed to de-authorise vault: %w", err)
	}

	return nil
}
