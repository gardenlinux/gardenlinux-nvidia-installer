"""Tests for generate_matrix.py gVisor matrix generation.

These tests run generate_matrix.py as a subprocess with a fixture versions.yaml
so they are independent of the live data and do not require network access.
"""
import itertools
import json
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

import pytest

SCRIPT = Path(__file__).parent.parent / "generate_matrix.py"

# Expiry far in the future so deprecated versions are always included in tests
FUTURE_EXPIRY = (date.today() + timedelta(days=365)).isoformat()
PAST_EXPIRY = (date.today() - timedelta(days=1)).isoformat()

FIXTURE_YAML = f"""\
os_versions:
- 2150.4.0
- '1877.10'
deprecated_os_versions:
- version: 2150.3.0
  expires: '{FUTURE_EXPIRY}'
- version: '1877.9'
  expires: '{FUTURE_EXPIRY}'
kernel_flavour:
- cloud
- metal
cpu_arch:
- amd64
nvidia_drivers:
- 590.48.01
- 570.211.01
gvisor_driver_pins:
  590.48.01: 590.48.01
  570.211.01: 570.195.03
"""

FIXTURE_OS_VERSIONS = ["2150.4.0", "1877.10", "2150.3.0", "1877.9"]
FIXTURE_ACTIVE_OS_VERSIONS = ["2150.4.0", "1877.10"]
FIXTURE_KERNEL_FLAVOURS = ["cloud", "metal"]
FIXTURE_CPU_ARCHES = ["amd64"]
FIXTURE_NVIDIA_DRIVERS = ["590.48.01", "570.211.01"]
FIXTURE_GVISOR_PINS = {
    "590.48.01": "590.48.01",
    "570.211.01": "570.195.03",
}


@pytest.fixture
def versions_yaml(tmp_path):
    """Write fixture versions.yaml and return its parent directory."""
    (tmp_path / "versions.yaml").write_text(FIXTURE_YAML)
    return tmp_path


def run_matrix(cwd):
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def mainstream_tuples(matrix):
    return {
        (e["os_version"], e["arch"], e["kernel_flavour"])
        for e in matrix["build"]["include"]
    }


def gvisor_tuples(matrix):
    return {
        (e["os_version"], e["arch"], e["kernel_flavour"])
        for e in matrix["gvisor_build"]["include"]
    }


def test_gvisor_build_key_present(versions_yaml):
    """Output must contain a gvisor_build key."""
    matrix = run_matrix(versions_yaml)
    assert "gvisor_build" in matrix, (
        "generate_matrix.py does not emit 'gvisor_build' — feature not yet implemented"
    )


def test_gvisor_manifest_key_present(versions_yaml):
    """Output must contain a gvisor_manifest key."""
    matrix = run_matrix(versions_yaml)
    assert "gvisor_manifest" in matrix, (
        "generate_matrix.py does not emit 'gvisor_manifest' — feature not yet implemented"
    )


def test_gvisor_build_uses_pinned_driver_versions(versions_yaml):
    """gVisor build matrix entries must use pinned versions, not mainstream drivers."""
    matrix = run_matrix(versions_yaml)
    assert "gvisor_build" in matrix

    pinned = set(FIXTURE_GVISOR_PINS.values())

    for entry in matrix["gvisor_build"]["include"]:
        dv = entry["driver_version"]
        assert dv in pinned, (
            f"gVisor build entry has driver_version={dv!r} which is not a pinned version"
        )


def test_gvisor_build_covers_same_os_arch_flavour_combos(versions_yaml):
    """Every (os_version, arch, kernel_flavour) in mainstream also appears in gVisor."""
    matrix = run_matrix(versions_yaml)
    assert "gvisor_build" in matrix

    assert gvisor_tuples(matrix) == mainstream_tuples(matrix)


def test_gvisor_entries_carry_image_subfolder(versions_yaml):
    """Each gVisor build entry must carry image_subfolder='gvisor'."""
    matrix = run_matrix(versions_yaml)
    assert "gvisor_build" in matrix

    for entry in matrix["gvisor_build"]["include"]:
        assert entry.get("image_subfolder") == "gvisor", (
            f"gVisor build entry missing image_subfolder='gvisor': {entry}"
        )


def test_mainstream_build_output_unchanged(versions_yaml):
    """Mainstream build matrix must include active and non-expired deprecated versions."""
    matrix = run_matrix(versions_yaml)

    expected_build = [
        {
            "os_version": os_version,
            "driver_version": driver,
            "arch": arch,
            "kernel_flavour": flavour,
        }
        for os_version, arch, flavour, driver in itertools.product(
            FIXTURE_OS_VERSIONS,
            FIXTURE_CPU_ARCHES,
            FIXTURE_KERNEL_FLAVOURS,
            FIXTURE_NVIDIA_DRIVERS,
        )
    ]

    assert matrix["build"]["include"] == expected_build


def test_missing_gvisor_pin_raises(tmp_path):
    """A mainstream driver with no gvisor_driver_pins entry should cause a non-zero exit."""
    incomplete_yaml = """\
os_versions:
- 2150.4.0
kernel_flavour:
- cloud
cpu_arch:
- amd64
nvidia_drivers:
- 590.48.01
- 600.00.00
gvisor_driver_pins:
  590.48.01: 590.48.01
"""
    (tmp_path / "versions.yaml").write_text(incomplete_yaml)

    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0, (
        "Expected non-zero exit when gvisor_driver_pins is missing an entry for a mainstream driver"
    )


def test_expired_deprecated_versions_excluded(tmp_path):
    """Deprecated versions past their expiry date must not appear in the build matrix."""
    yaml_with_expired = f"""\
os_versions:
- 2150.4.0
deprecated_os_versions:
- version: 2150.3.0
  expires: '{PAST_EXPIRY}'
kernel_flavour:
- cloud
cpu_arch:
- amd64
nvidia_drivers:
- 590.48.01
gvisor_driver_pins:
  590.48.01: 590.48.01
"""
    (tmp_path / "versions.yaml").write_text(yaml_with_expired)

    matrix = run_matrix(tmp_path)
    os_versions_in_build = {e["os_version"] for e in matrix["build"]["include"]}
    assert "2150.3.0" not in os_versions_in_build, (
        "Expired deprecated version should not appear in build matrix"
    )
    assert "2150.4.0" in os_versions_in_build


def test_non_expired_deprecated_versions_included(tmp_path):
    """Deprecated versions not yet expired must appear in the build matrix."""
    yaml_with_active_deprecated = f"""\
os_versions:
- 2150.4.0
deprecated_os_versions:
- version: 2150.3.0
  expires: '{FUTURE_EXPIRY}'
kernel_flavour:
- cloud
cpu_arch:
- amd64
nvidia_drivers:
- 590.48.01
gvisor_driver_pins:
  590.48.01: 590.48.01
"""
    (tmp_path / "versions.yaml").write_text(yaml_with_active_deprecated)

    matrix = run_matrix(tmp_path)
    os_versions_in_build = {e["os_version"] for e in matrix["build"]["include"]}
    assert "2150.3.0" in os_versions_in_build
    assert "2150.4.0" in os_versions_in_build


def test_no_deprecated_section_still_works(tmp_path):
    """generate_matrix.py handles versions.yaml without deprecated_os_versions."""
    yaml_no_deprecated = """\
os_versions:
- 2150.4.0
kernel_flavour:
- cloud
cpu_arch:
- amd64
nvidia_drivers:
- 590.48.01
gvisor_driver_pins:
  590.48.01: 590.48.01
"""
    (tmp_path / "versions.yaml").write_text(yaml_no_deprecated)

    matrix = run_matrix(tmp_path)
    os_versions_in_build = {e["os_version"] for e in matrix["build"]["include"]}
    assert "2150.4.0" in os_versions_in_build
