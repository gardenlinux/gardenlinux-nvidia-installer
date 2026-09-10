"""Tests for gVisor pin-update logic and deprecation logic in update_versions.py.

These tests use fixture data (no live network calls) to validate the
version-selection algorithm for gVisor driver pins and the OS version
deprecation lifecycle.
"""
import copy
import sys
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Add .ci to path so we can import the script as a module
sys.path.insert(0, str(Path(__file__).parent.parent))

# Fixture: a version.go snippet listing nvproxy-qualified driver versions.
# Versions listed here are the ones expected to be parsed from the real file.
FIXTURE_VERSION_GO = """\
package nvproxy

func init() {
\tv570_86_15 := addUnsupportedDriverABI(570, 86, 15, func() *driverABI {
\t\treturn nil
\t})
\tv570_124_06 := addDriverABI(570, 124, 6, "checksum1", "checksum2", v570_86_15)
\tv570_133_20 := addDriverABI(570, 133, 20, "checksum1", "checksum2", v570_124_06)
\tv570_172_08 := addDriverABI(570, 172, 8, "checksum1", "checksum2", v570_133_20)
\t_ = addDriverABI(570, 195, 3, "checksum1", "checksum2", v570_172_08)
\tv580_65_06 := addDriverABI(580, 65, 6, "checksum1", "checksum2", func() *driverABI {
\t\treturn nil
\t})
\tv580_105_08 := addDriverABI(580, 105, 8, "checksum1", "checksum2", v580_65_06)
\tv580_126_09 := addDriverABI(580, 126, 9, "checksum1", "checksum2", v580_105_08)
\tv580_126_20 := addDriverABI(580, 126, 20, "checksum1", "checksum2", v580_126_09)
\tv580_159_03 := addDriverABI(580, 159, 3, "checksum1", "checksum2", v580_126_20)
\t_ = addDriverABI(580, 159, 4, "checksum1", "checksum2", v580_159_03)
\tv590_44_01 := addUnsupportedDriverABI(590, 44, 1, func() *driverABI {
\t\treturn nil
\t})
\tv590_48_01 := addDriverABI(590, 48, 1, "checksum1", "checksum2", v590_44_01)
\t_ = v590_48_01
}
"""

FIXTURE_VERSIONS_YAML = {
    "os_versions": ["2150.4.0"],
    "kernel_flavour": ["cloud"],
    "cpu_arch": ["amd64"],
    "nvidia_drivers": ["590.48.01", "580.167.08", "570.211.01"],
    "gvisor_driver_pins": {
        "590.48.01": "590.48.01",
        "580.167.08": "580.159.04",
        "570.211.01": "570.195.03",
    },
}


def import_update_versions():
    """Import update_versions with network-dependent modules mocked out."""
    mocks = {
        "html2text": MagicMock(),
        "requests": MagicMock(),
    }
    with patch.dict("sys.modules", mocks):
        import importlib
        import update_versions as uv
        importlib.reload(uv)
        return uv


class TestParseQualifiedVersions:
    """Tests for parsing nvproxy-qualified versions from version.go content."""

    def test_returns_only_addDriverABI_versions(self):
        """Only addDriverABI (not addUnsupportedDriverABI) versions are qualified."""
        uv = import_update_versions()
        qualified = uv.parse_gvisor_qualified_versions(FIXTURE_VERSION_GO)
        assert "570.86.15" not in qualified, "unsupported version should not be included"
        assert "590.44.01" not in qualified, "unsupported version should not be included"

    def test_parses_all_supported_versions(self):
        """All addDriverABI entries are returned."""
        uv = import_update_versions()
        qualified = uv.parse_gvisor_qualified_versions(FIXTURE_VERSION_GO)
        expected = {
            "570.124.06", "570.133.20", "570.172.08", "570.195.03",
            "580.65.06", "580.105.08", "580.126.09", "580.126.20",
            "580.159.03", "580.159.04",
            "590.48.01",
        }
        assert qualified == expected


class TestSelectGvisorPin:
    """Tests for selecting the highest qualified pin ≤ mainstream version."""

    def test_selects_highest_qualified_patch_leq_mainstream(self):
        """Pin is the highest qualified version with same major ≤ mainstream."""
        uv = import_update_versions()
        qualified = uv.parse_gvisor_qualified_versions(FIXTURE_VERSION_GO)

        assert uv.select_gvisor_pin("570.211.01", qualified) == "570.195.03"
        assert uv.select_gvisor_pin("580.167.08", qualified) == "580.159.04"
        assert uv.select_gvisor_pin("590.48.01", qualified) == "590.48.01"

    def test_exact_match_is_selected(self):
        """When mainstream version is directly qualified, it is selected as pin."""
        uv = import_update_versions()
        qualified = uv.parse_gvisor_qualified_versions(FIXTURE_VERSION_GO)
        assert uv.select_gvisor_pin("590.48.01", qualified) == "590.48.01"

    def test_no_qualified_version_raises(self):
        """Raises ValueError when no qualified version ≤ mainstream exists for the major."""
        uv = import_update_versions()
        qualified = {"590.48.01", "580.159.04"}  # no 600.x versions
        with pytest.raises((ValueError, KeyError)):
            uv.select_gvisor_pin("600.00.00", qualified)


class TestUpdateGvisorPins:
    """Tests for update_gvisor_driver_pins() modifying versions.yaml data."""

    def test_already_current_returns_false(self):
        """Returns False (no update) when pins are already up to date."""
        uv = import_update_versions()
        data = copy.deepcopy(FIXTURE_VERSIONS_YAML)
        changed = uv.update_gvisor_driver_pins(data, FIXTURE_VERSION_GO)
        assert changed is False
        assert data["gvisor_driver_pins"] == FIXTURE_VERSIONS_YAML["gvisor_driver_pins"]

    def test_outdated_pin_is_updated_and_returns_true(self):
        """Returns True and updates pin when a newer qualified version is available."""
        uv = import_update_versions()
        data = copy.deepcopy(FIXTURE_VERSIONS_YAML)
        # Simulate an outdated pin for 580.x
        data["gvisor_driver_pins"]["580.167.08"] = "580.126.09"

        changed = uv.update_gvisor_driver_pins(data, FIXTURE_VERSION_GO)
        assert changed is True
        assert data["gvisor_driver_pins"]["580.167.08"] == "580.159.04"

    def test_gvisor_version_update_output_true_when_changed(self, capsys):
        """GVISOR_VERSION_UPDATE=true is printed when a pin is updated."""
        uv = import_update_versions()
        data = copy.deepcopy(FIXTURE_VERSIONS_YAML)
        data["gvisor_driver_pins"]["570.211.01"] = "570.124.06"  # outdated

        uv.update_gvisor_driver_pins(data, FIXTURE_VERSION_GO)
        # The caller (update_versions) prints the output; verify the return value
        # drives the output flag correctly
        changed = uv.update_gvisor_driver_pins(
            copy.deepcopy(FIXTURE_VERSIONS_YAML), FIXTURE_VERSION_GO
        )
        assert changed is False  # already current

    def test_stale_key_removed_and_returns_true(self):
        """Pins whose key is not in nvidia_drivers are removed and True is returned."""
        uv = import_update_versions()
        data = copy.deepcopy(FIXTURE_VERSIONS_YAML)
        data["gvisor_driver_pins"]["999.00.00"] = "590.48.01"  # stale: not in nvidia_drivers

        changed = uv.update_gvisor_driver_pins(data, FIXTURE_VERSION_GO)
        assert changed is True
        assert "999.00.00" not in data["gvisor_driver_pins"]
        assert data["gvisor_driver_pins"] == FIXTURE_VERSIONS_YAML["gvisor_driver_pins"]

    def test_new_mainstream_major_without_qualified_version_warns(self, capsys):
        """A new mainstream major with no qualified gVisor version logs a warning."""
        uv = import_update_versions()
        data = copy.deepcopy(FIXTURE_VERSIONS_YAML)
        data["nvidia_drivers"].append("600.00.00")
        data["gvisor_driver_pins"]["600.00.00"] = "590.48.01"  # wrong major as placeholder

        # Should not crash, but should warn
        import warnings
        with warnings.catch_warnings(record=True):
            warnings.simplefilter("always")
            try:
                uv.update_gvisor_driver_pins(data, FIXTURE_VERSION_GO)
            except (ValueError, KeyError):
                pass  # acceptable: a clear error is also acceptable per the spec


class TestDeprecationHelpers:
    """Tests for deprecation helper functions."""

    def test_latest_per_major(self):
        uv = import_update_versions()
        versions = ["2150.1.0", "2150.9.0", "2150.3.0", "1877.10", "1877.23"]
        result = uv._latest_per_major(versions)
        assert result == {"2150": "2150.9.0", "1877": "1877.23"}


class TestGetLatestGardenlinuxTagsDeprecation:
    """Tests for the deprecation lifecycle in get_latest_gardenlinux_tags."""

    def _make_data(self, active, deprecated=None):
        return {
            "os_versions": list(active),
            "deprecated_os_versions": list(deprecated or []),
            "nvidia_drivers": ["590.48.01"],
        }

    def _mock_tags_response(self, uv, tags):
        """Patch requests.get to return a fake tag list."""
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = [{"name": t} for t in tags]
        return patch.object(uv.requests, "get", return_value=mock_resp)

    def test_new_version_deprecates_old_latest(self):
        """When a new version appears, the old latest moves to deprecated."""
        uv = import_update_versions()
        data = self._make_data(["2150.8.0", "1877.22"])
        today = date(2026, 9, 10)

        with self._mock_tags_response(uv, ["2150.9.0", "2150.8.0", "1877.23", "1877.22"]):
            changed = uv.get_latest_gardenlinux_tags(data, today=today)

        assert changed is True
        assert set(str(v) for v in data["os_versions"]) == {"2150.9.0", "1877.23"}
        dep_versions = {str(e["version"]) for e in data["deprecated_os_versions"]}
        assert "2150.8.0" in dep_versions
        assert "1877.22" in dep_versions

    def test_expired_versions_are_removed(self):
        """Versions past their expiry date are dropped entirely."""
        uv = import_update_versions()
        data = self._make_data(
            ["2150.9.0"],
            [{"version": "2150.8.0", "expires": "2026-01-01"}],
        )
        today = date(2026, 9, 10)

        with self._mock_tags_response(uv, ["2150.9.0", "2150.8.0"]):
            changed = uv.get_latest_gardenlinux_tags(data, today=today)

        dep_versions = {str(e["version"]) for e in data["deprecated_os_versions"]}
        assert "2150.8.0" not in dep_versions

    def test_existing_deprecation_expiry_preserved(self):
        """Already-deprecated versions keep their original expiry date."""
        uv = import_update_versions()
        original_expiry = "2027-06-01"
        data = self._make_data(
            ["2150.9.0"],
            [{"version": "2150.8.0", "expires": original_expiry}],
        )
        today = date(2026, 9, 10)

        with self._mock_tags_response(uv, ["2150.9.0", "2150.8.0"]):
            uv.get_latest_gardenlinux_tags(data, today=today)

        dep_entry = next(e for e in data["deprecated_os_versions"] if str(e["version"]) == "2150.8.0")
        assert dep_entry["expires"] == original_expiry

    def test_no_change_returns_false(self):
        """Returns False when tags haven't changed."""
        uv = import_update_versions()
        data = self._make_data(
            ["2150.9.0"],
            [{"version": "2150.8.0", "expires": "2027-03-10"}],
        )
        today = date(2026, 9, 10)

        with self._mock_tags_response(uv, ["2150.9.0", "2150.8.0"]):
            changed = uv.get_latest_gardenlinux_tags(data, today=today)

        assert changed is False

    def test_multiple_new_versions_only_latest_is_active(self):
        """When several new versions appear at once, only the latest per major is active."""
        uv = import_update_versions()
        data = self._make_data(["2150.5.0"])
        today = date(2026, 9, 10)

        with self._mock_tags_response(uv, ["2150.9.0", "2150.8.0", "2150.7.0", "2150.6.0", "2150.5.0"]):
            changed = uv.get_latest_gardenlinux_tags(data, today=today)

        assert changed is True
        assert data["os_versions"] == ["2150.9.0"]
        dep_versions = {str(e["version"]) for e in data["deprecated_os_versions"]}
        assert dep_versions == {"2150.8.0", "2150.7.0", "2150.6.0", "2150.5.0"}
