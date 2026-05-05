package main

import (
	"fmt"
	"time"

	"github.com/goccy/go-yaml"
)

type componentDescriptor struct {
	Meta      componentDescriptorMetadata  `yaml:"meta"`
	Component componentDescriptorComponent `yaml:"component"`
}

// ToYAML serializes a component desctiptor to YAML.
func (d *componentDescriptor) ToYAML() ([]byte, error) {
	return yaml.Marshal(d)
}

//nolint:tagliatelle // Defined by OCM.
type componentDescriptorMetadata struct {
	ConfiguredVersion string `yaml:"configuredSchemaVersion"`
}

//nolint:tagliatelle // Defined by OCM.
type componentDescriptorComponent struct {
	Name                string                                 `yaml:"name"`
	Version             string                                 `yaml:"version"`
	Labels              []componentDescriptorlabel             `yaml:"labels,omitempty"`
	CreationTime        string                                 `yaml:"creationTime"`
	Provider            string                                 `yaml:"provider"`
	RepositoryContexts  []componentDescriptorRepositoryContext `yaml:"repositoryContexts"`
	Sources             []componentDescriptorSource            `yaml:"sources"`
	ComponentReferences []struct{}                             `yaml:"componentReferences"`
	Resources           []componentDesciptorResource           `yaml:"resources"`
}

type componentDescriptorlabel struct {
	Name  string `yaml:"name"`
	Value any    `yaml:"value"`
}

//nolint:tagliatelle // Defined by OCM.
type componentDescriptorRepositoryContext struct {
	Type    string `yaml:"type"`
	BaseURL string `yaml:"baseUrl"`
	SubPath string `yaml:"subPath"`
}

type componentDescriptorSource struct {
	Name    string                     `yaml:"name"`
	Version string                     `yaml:"version"`
	Labels  []componentDescriptorlabel `yaml:"labels,omitempty"`
	Type    string                     `yaml:"type"`
	Access  componentDescriptorGitHub  `yaml:"access"`
}

//nolint:tagliatelle // Defined by OCM.
type componentDescriptorGitHub struct {
	Type    string `yaml:"type"`
	RepoURL string `yaml:"repoUrl"`
	Commit  string `yaml:"commit"`
}

//nolint:tagliatelle // Defined by OCM.
type componentDesciptorResource struct {
	Name          string                     `yaml:"name"`
	Version       string                     `yaml:"version"`
	Digest        *string                    `yaml:"digest"`
	SrcRefs       []string                   `yaml:"srcRefs"`
	Relation      string                     `yaml:"relation"`
	ExtraIdentity map[string]string          `yaml:"extraIdentity,omitempty"`
	Labels        []componentDescriptorlabel `yaml:"labels,omitempty"`
	Type          string                     `yaml:"type"`
	Access        componentDescriptorOCI     `yaml:"access"`
}

type componentDescriptorOCI struct {
	Type           string `yaml:"type"`
	ImageReference string `yaml:"imageReference"`
}

type image struct {
	Arch                string `yaml:"arch"`
	OSVersion           string `yaml:"os_version"`
	KernelVersion       string `yaml:"kernel_version"`
	KernelFlavor        string `yaml:"kernel_flavor"`
	NvidiaDriverVersion string `yaml:"nvidia_driver_version"`
}

func buildComponentDescriptor(images []image, version, commit, name string) (*componentDescriptor, error) {
	descriptor := &componentDescriptor{
		Meta: componentDescriptorMetadata{
			ConfiguredVersion: "v2",
		},
		Component: componentDescriptorComponent{
			Name:         nvidiaRepo,
			Version:      version,
			CreationTime: time.Now().Format(time.RFC3339),
			Provider:     componentProvider,
			RepositoryContexts: []componentDescriptorRepositoryContext{
				{
					Type:    "OCIRegistry",
					BaseURL: uploadRepo,
					SubPath: "null",
				},
			},
			Sources: []componentDescriptorSource{
				{
					Name:    "gardenlinux-nvidia-installer",
					Version: version,
					Labels: []componentDescriptorlabel{
						{
							Name: "cloud.gardener.cnudie/dso/scanning-hints/source_analysis/v1",
							Value: map[string]any{
								"policy":  "skip",
								"comment": "repo only contains build instructions",
							},
						},
					},
					Type: "git",
					Access: componentDescriptorGitHub{
						Type:    "gitHub",
						RepoURL: githubRepoURL,
						Commit:  commit,
					},
				},
			},
			ComponentReferences: []struct{}{},
		},
	}

	for _, img := range images {
		tag := fmt.Sprintf("%s-%s-gardenlinux0", img.NvidiaDriverVersion, img.KernelVersion)
		descriptor.Component.Resources = append(descriptor.Component.Resources, componentDesciptorResource{
			Name:     "gardenlinux-nvidia-installer",
			Version:  version,
			Digest:   nil,
			SrcRefs:  []string{},
			Relation: "local",
			ExtraIdentity: map[string]string{
				"architecture":          img.Arch,
				"os_version":            img.OSVersion,
				"kernel_version":        img.KernelVersion,
				"kernel_flavor":         img.KernelFlavor,
				"nvidia_driver_version": img.NvidiaDriverVersion,
			},
			Labels: []componentDescriptorlabel{
				{
					Name:  "gardener.cloud/gardenlinux-nvidia-installer/image",
					Value: img,
				},
			},
			Type: "ociImage",
			Access: componentDescriptorOCI{
				Type:           "ociRegistry",
				ImageReference: name + ":" + tag,
			},
		},
		)
	}

	return descriptor, nil
}
