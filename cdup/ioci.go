package main

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/Masterminds/semver/v3"
	"github.com/goccy/go-yaml"
)

type IndexComponentDescriptor struct {
	Component indexComponentDescriptorComponent `yaml:"component"`
}

// ToYAML serializes a component desctiptor to YAML.
func (d *IndexComponentDescriptor) ToYAML() ([]byte, error) {
	return yaml.Marshal(d)
}

//nolint:tagliatelle // Defined by OCM.
type indexComponentDescriptorComponent struct {
	Name                string                              `yaml:"name"`
	Version             string                              `yaml:"version"`
	Sources             []struct{}                          `yaml:"sources"`
	ComponentReferences []indexComponentDescriptorReference `yaml:"componentReferences"`
	Resources           []struct{}                          `yaml:"resources"`
}

//nolint:tagliatelle // Defined by OCM.
type indexComponentDescriptorReference struct {
	Name          string `yaml:"name"`
	Version       string `yaml:"version"`
	ComponentName string `yaml:"componentName"`
}

// GetLatestTag fetches all tags from the repository and returns the latest semantic version tag
func (p *oci) GetLatestTag(ctx context.Context) (string, error) {
	if !p.isConfigured() {
		return "", errors.New("config not set")
	}
	repo := p.clients()
	var tags []string
	err := repo.Tags(ctx, "", func(t []string) error {
		tags = append(tags, t...)
		return nil
	})
	if err != nil {
		return "", fmt.Errorf("cannot list tags: %w", err)
	}

	if len(tags) == 0 {
		return "", errors.New("no tags found in repository")
	}
	// Parse and sort semantic versions
	var versions []*semver.Version
	for _, tag := range tags {
		v, err := semver.NewVersion(tag)
		if err != nil {
			// Skip non-semver tags
			continue
		}
		versions = append(versions, v)
	}

	if len(versions) == 0 {
		// If no semver tags, return the first tag (or implement your own logic)
		return tags[0], nil
	}

	sort.Sort(semver.Collection(versions))
	return versions[len(versions)-1].Original(), nil
}

func bumpPatch(version string) (string, error) {
	parts := strings.Split(version, ".")
	if len(parts) != 3 {
		return "", fmt.Errorf("invalid version format")
	}

	patch, err := strconv.Atoi(parts[2])
	if err != nil {
		return "", err
	}

	patch++

	return fmt.Sprintf("%s.%s.%d", parts[0], parts[1], patch), nil
}

func (p *oci) BuildIndexComponentDescriptor(version string, newVersion string) (*IndexComponentDescriptor, error) {
	descriptor := &IndexComponentDescriptor{
		Component: indexComponentDescriptorComponent{
			Name:      "github.com/gardenlinux/gardenlinux-nvidia-installer-idx",
			Version:   newVersion,
			Resources: []struct{}{},
			Sources:   []struct{}{},
			ComponentReferences: []indexComponentDescriptorReference{
				{
					Name:          "nvidia-installer",
					ComponentName: "github.com/gardenlinux/gardenlinux-nvidia-installer",
					Version:       version,
				},
			},
		},
	}
	return descriptor, nil
}
