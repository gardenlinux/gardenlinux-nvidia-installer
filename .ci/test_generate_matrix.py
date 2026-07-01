"""Tests for generate_matrix.py gVisor matrix generation.

These tests run generate_matrix.py as a subprocess with a fixture versions.yaml
so they are independent of the live data and do not require network access.
"""
import itertools
import json
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).parent / "generate_matrix.py"

FIXTURE_YAML = """\
os_versions:
- 2150.4.0
- '1877.10'
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

FIXTURE_OS_VERSIONS = ["2150.4.0", "1877.10"]
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
    """Mainstream build matrix must be unaffected by gVisor changes."""
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
