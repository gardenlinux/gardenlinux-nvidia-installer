package main

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"

	"github.com/opencontainers/go-digest"
	specv1 "github.com/opencontainers/image-spec/specs-go/v1"
	"oras.land/oras-go/v2"
	orasfile "oras.land/oras-go/v2/content/file"
	"oras.land/oras-go/v2/registry/remote"
	"oras.land/oras-go/v2/registry/remote/auth"
	"oras.land/oras-go/v2/registry/remote/retry"
)

func (*oci) Type() string {
	return "OCI"
}

type oci struct {
	ociCfg      ociOCMConfig
	credsSource *vault
	clientsMtx  sync.RWMutex
	repo        *remote.Repository
}

type ociOCMConfig struct {
	Config     string `mapstructure:"config"`
	Repository string `mapstructure:"repository"`
	Path       string `mapstructure:"path"`
}

func (p *oci) isConfigured() bool {
	return p.repo != nil
}

func (p *oci) SetOCMConfig(ctx context.Context, credsSource *vault, cfg map[string]any) error {
	p.credsSource = credsSource

	err := parseConfig(cfg, &p.ociCfg)
	if err != nil {
		return err
	}

	switch {
	case p.ociCfg.Config == "":
		return errors.New("missing config")
	case p.ociCfg.Repository == "":
		return errors.New("missing repository")
	case p.ociCfg.Path == "":
		return errors.New("missing path")
	}

	err = credsSource.AcquireCreds(ctx, credsID{
		Type:   fmt.Sprintf("%s_%s", p.Type(), p.credsType()),
		Config: p.ociCfg.Config,
		Role:   "oci",
	}, p.createClients)
	if err != nil {
		return fmt.Errorf("cannot acquire credentials for config %s: %w", p.ociCfg.Config, err)
	}

	return nil
}

type ociCredentials struct {
	Username string `mapstructure:"username"`
	Password string `mapstructure:"password"`
}

type ociGCPCredentials struct {
	Token string `mapstructure:"token"`
}

func (p *oci) credsType() string {
	switch {
	case strings.HasPrefix(p.ociCfg.Repository, "europe-docker.pkg.dev/"):
		return "GCP"
	default:
		return "userpass"
	}
}

func (p *oci) createClients(_ context.Context, rawCreds map[string]any) error {
	var creds ociCredentials
	var err error
	switch p.credsType() {
	case "GCP":
		var gcpCreds ociGCPCredentials
		err = parseCredentials(rawCreds, &gcpCreds)
		creds.Username = "oauth2accesstoken"
		creds.Password = gcpCreds.Token
	case "userpass":
		fallthrough
	default:
		err = parseCredentials(rawCreds, &creds)
	}
	if err != nil {
		return err
	}

	p.clientsMtx.Lock()
	defer p.clientsMtx.Unlock()

	var fullRepositoryPath string
	fullRepositoryPath = p.ociCfg.Repository + repoSuffix
	if p.ociCfg.Path == "idx" {
		fullRepositoryPath = p.ociCfg.Repository + repoSuffixIdx
	}

	p.repo, err = remote.NewRepository(fullRepositoryPath)
	if err != nil {
		return fmt.Errorf("invalid OCI repository %s: %w", fullRepositoryPath, err)
	}

	p.repo.Client = &auth.Client{
		Client: retry.DefaultClient,
		Cache:  auth.NewCache(),
		Credential: auth.StaticCredential(p.repo.Reference.Registry, auth.Credential{
			Username: creds.Username,
			Password: creds.Password,
		}),
	}

	return nil
}

func (p *oci) clients() *remote.Repository {
	p.clientsMtx.RLock()
	defer p.clientsMtx.RUnlock()

	return p.repo
}

func (*oci) OCMType() string {
	return "OCIRegistry"
}

func (p *oci) OCMRepositoryBase() string {
	return p.ociCfg.Repository
}

func (p *oci) PublishComponentDescriptor(ctx context.Context, version string, descriptor []byte) error {
	if !p.isConfigured() {
		return errors.New("config not set")
	}
	var tarBuf bytes.Buffer
	tarball := tar.NewWriter(&tarBuf)
	defer func() {
		_ = tarball.Close()
	}()

	err := tarball.WriteHeader(&tar.Header{
		Typeflag: tar.TypeReg,
		Name:     "component-descriptor.yaml",
		Size:     int64(len(descriptor)),
		Mode:     0o644,
		Format:   tar.FormatPAX,
	})
	if err != nil {
		return fmt.Errorf("cannot write tar header: %w", err)
	}

	_, err = tarball.Write(descriptor)
	if err != nil {
		return fmt.Errorf("cannot write tar contents: %w", err)
	}

	err = tarball.Close()
	if err != nil {
		return fmt.Errorf("cannot close tar: %w", err)
	}

	var tmpDir string
	tmpDir, err = os.MkdirTemp("", "")
	if err != nil {
		return fmt.Errorf("cannot create temporary directory: %w", err)
	}
	defer func() {
		_ = os.RemoveAll(tmpDir)
	}()

	var fs *orasfile.Store
	fs, err = orasfile.New(tmpDir)
	if err != nil {
		return fmt.Errorf("cannot create local OCI store in %s: %w", tmpDir, err)
	}
	defer func() {
		_ = fs.Close()
	}()

	tarDescriptor := specv1.Descriptor{
		MediaType: "application/vnd.gardener.cloud.cnudie.component-descriptor.v2+yaml+tar",
		Digest:    digest.FromBytes(tarBuf.Bytes()),
		Size:      int64(tarBuf.Len()),
	}
	err = fs.Push(ctx, tarDescriptor, &tarBuf)
	if err != nil {
		return fmt.Errorf("cannot add OCI manifest config to local OCI store: %w", err)
	}

	var configJSON []byte
	configJSON, err = json.Marshal(map[string]map[string]any{
		"componentDescriptorLayer": {
			"digest":    tarDescriptor.Digest.String(),
			"mediaType": tarDescriptor.MediaType,
			"size":      tarDescriptor.Size,
		},
	})
	if err != nil {
		return fmt.Errorf("invalid artifact config: %w", err)
	}

	configDescriptor := specv1.Descriptor{
		MediaType: "application/vnd.gardener.cloud.cnudie.component.config.v1+json",
		Digest:    digest.FromBytes(configJSON),
		Size:      int64(len(configJSON)),
	}
	err = fs.Push(ctx, configDescriptor, bytes.NewReader(configJSON))
	if err != nil {
		return fmt.Errorf("cannot add OCI manifest config to local OCI store: %w", err)
	}

	var manifestDescriptor specv1.Descriptor
	manifestDescriptor, err = oras.PackManifest(ctx, fs, oras.PackManifestVersion1_1, tarDescriptor.MediaType, oras.PackManifestOptions{
		Layers: []specv1.Descriptor{
			tarDescriptor,
		},
		ManifestAnnotations: map[string]string{
			specv1.AnnotationCreated: "1970-01-01T00:00:00Z",
		},
		ConfigDescriptor: &configDescriptor,
	})
	if err != nil {
		return fmt.Errorf("cannot add OCI manifest to local OCI store: %w", err)
	}

	err = fs.Tag(ctx, manifestDescriptor, version)
	if err != nil {
		return fmt.Errorf("cannot tag OCI manifest: %w", err)
	}

	repo := p.clients()

	_, err = oras.Copy(ctx, fs, version, repo, version, oras.DefaultCopyOptions)
	if err != nil {
		return fmt.Errorf("cannot upload OCI artifact: %w", err)
	}

	err = fs.Close()
	if err != nil {
		return fmt.Errorf("cannot close local OCI store: %w", err)
	}

	err = os.RemoveAll(tmpDir)
	if err != nil {
		return fmt.Errorf("cannot remove temporary directory %s: %w", tmpDir, err)
	}

	return nil
}

func (p *oci) Close() error {
	if p.ociCfg.Config != "" {
		p.credsSource.ReleaseCreds(credsID{
			Type:   fmt.Sprintf("%s_%s", p.Type(), p.credsType()),
			Config: p.ociCfg.Config,
			Role:   "oci",
		})
	}

	return nil
}
