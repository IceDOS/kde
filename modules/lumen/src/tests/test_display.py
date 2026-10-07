import pytest

from lumen.display import Display, _vcp, list_displays, set_brightness


DETECT = """Display 1
   I2C bus:          /dev/i2c-6
   DRM connector:    card1-DP-1
   drm_connector_id: 511
   Monitor:          XMI:Mi Monitor:

Display 2
   I2C bus:          /dev/i2c-7
   DRM connector:    card1-DP-2
   drm_connector_id: 521
   Monitor:          AUS:MG248:K4LMQS100269

"""
ON = "VCP code 0xd6 (Power mode                    ): DPM: On,  DPMS: Off (sl=0x01)\n"
OFF = "VCP code 0xd6 (Power mode                    ): DPM: Off, DPMS: Off (sl=0x04)\n"


def bright(cur, mx=100):
    return f"VCP code 0x10 (Brightness): current value = {cur}, max value = {mx}\n"


def fake(calls, vcp=None, detect=DETECT):
    """run() replacement: answers keyed by (bus, code); an exception value is raised."""
    vcp = vcp or {}

    def run(*args):
        calls.append(args)
        if args[0] == "detect":
            if isinstance(detect, Exception):
                raise detect
            return detect
        got = vcp.get((args[1], args[3]), ON if args[3] == "d6" else bright(30))
        if isinstance(got, Exception):
            raise got
        return got

    return run


def test_list_displays_reads_live_brightness_and_power():
    calls = []
    ds = list_displays(run=fake(calls, {("6", "10"): bright(75), ("6", "d6"): ON}))
    assert ds == [Display("6", "Mi Monitor", 75, 100, 1), Display("7", "MG248", 30, 100, 1)]
    assert ds[0].pct == 75 and ds[0].awake and ds[1].label == "MG248"
    assert ("detect", "--brief") in calls


def test_asleep_panel_reports_off():
    ds = list_displays(run=fake([], {("6", "d6"): OFF}))
    assert not ds[0].awake and ds[1].awake


def test_silent_bus_counts_as_asleep():
    ds = list_displays(run=fake([], {("6", "10"): RuntimeError("bus busy"), ("6", "d6"): RuntimeError("bus busy")}))
    assert not ds[0].awake
    assert ds[0].brightness == 0 and ds[0].pct == 0
    assert ds[1].awake  # one quiet display must not hide the other


def test_panel_without_power_feature_stays_awake():
    # Brightness answered, so 0xD6 failing means the code is unsupported, not that the panel is off.
    ds = list_displays(run=fake([], {("6", "d6"): RuntimeError("unsupported VCP")}))
    assert ds[0].awake and ds[0].brightness == 30


def test_detect_without_a_bus_is_skipped():
    assert list_displays(run=fake([], detect="Invalid display\n   No I2C bus\n")) == []


def test_set_brightness_writes_vcp():
    calls = []
    set_brightness("7", 4500, run=fake(calls))
    assert ("--bus", "7", "setvcp", "10", "4500") in calls


def test_set_brightness_error_propagates():
    def boom(*args):
        raise RuntimeError("DDC communication failed")

    with pytest.raises(RuntimeError, match="DDC"):
        set_brightness("7", 4500, run=boom)


def test_unreadable_vcp_output():
    with pytest.raises(RuntimeError, match="unreadable"):
        _vcp("6", "10", run=fake([], {("6", "10"): "nonsense\n"}))


def _put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def test_detect_edp_connected_and_awake(tmp_path):
    _put(tmp_path / "sys/class/drm/card0-eDP-1/status", "connected\n")
    _put(tmp_path / "sys/class/drm/card0-eDP-1/dpms", "On\n")
    _put(tmp_path / "sys/class/backlight/intel_backlight/actual_brightness", "500\n")
    _put(tmp_path / "sys/class/backlight/intel_backlight/max_brightness", "1000\n")
    _put(tmp_path / "sys/class/backlight/intel_backlight/type", "raw\n")

    ds = list_displays(run=fake([], detect=""), sysfs_root=tmp_path)
    assert ds == [Display("backlight:intel_backlight", "eDP-1", 500, 1000, 1)]
    assert ds[0].pct == 50.0 and ds[0].awake


def test_detect_edp_asleep_when_dpms_off(tmp_path):
    _put(tmp_path / "sys/class/drm/card0-eDP-1/status", "connected\n")
    _put(tmp_path / "sys/class/drm/card0-eDP-1/dpms", "Off\n")
    _put(tmp_path / "sys/class/backlight/intel_backlight/actual_brightness", "500\n")
    _put(tmp_path / "sys/class/backlight/intel_backlight/max_brightness", "1000\n")

    ds = list_displays(run=fake([], detect=""), sysfs_root=tmp_path)
    assert not ds[0].awake and ds[0].power == 4


def test_detect_edp_prefers_raw_over_firmware(tmp_path):
    _put(tmp_path / "sys/class/drm/card0-eDP-1/status", "connected\n")
    _put(tmp_path / "sys/class/backlight/acpi_video0/actual_brightness", "5\n")
    _put(tmp_path / "sys/class/backlight/acpi_video0/max_brightness", "15\n")
    _put(tmp_path / "sys/class/backlight/acpi_video0/type", "firmware\n")
    _put(tmp_path / "sys/class/backlight/amdgpu_bl0/actual_brightness", "128\n")
    _put(tmp_path / "sys/class/backlight/amdgpu_bl0/max_brightness", "255\n")
    _put(tmp_path / "sys/class/backlight/amdgpu_bl0/type", "raw\n")

    ds = list_displays(run=fake([], detect=""), sysfs_root=tmp_path)
    assert ds[0].bus == "backlight:amdgpu_bl0"
    assert ds[0].brightness == 128


def test_detect_edp_ignores_disconnected_connector(tmp_path):
    _put(tmp_path / "sys/class/drm/card0-eDP-1/status", "disconnected\n")
    _put(tmp_path / "sys/class/drm/card0-eDP-2/status", "connected\n")
    _put(tmp_path / "sys/class/backlight/intel_backlight/actual_brightness", "300\n")
    _put(tmp_path / "sys/class/backlight/intel_backlight/max_brightness", "1000\n")

    ds = list_displays(run=fake([], detect=""), sysfs_root=tmp_path)
    assert ds[0].label == "eDP-2"


def test_set_brightness_edp_calls_logind():
    calls = []

    def fake_bus(*args):
        calls.append(args)
        return ""

    set_brightness("backlight:intel_backlight", 750, run_bus=fake_bus)
    assert calls == [(
        "call",
        "org.freedesktop.login1",
        "/org/freedesktop/login1/session/auto",
        "org.freedesktop.login1.Session",
        "SetBrightness",
        "ssu",
        "backlight",
        "intel_backlight",
        "750",
    )]

