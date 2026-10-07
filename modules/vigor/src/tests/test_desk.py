from vigor import desk


def test_device_prefers_coarse_level():
    d = desk.device({"Type": 5, "Model": "G305", "Percentage": 55.0, "BatteryLevel": 6, "State": 2,
                     "IconName": "battery-low-symbolic", "PowerSupply": False})
    assert d["kind"] == "mouse" and d["level"] == "normal" and d["percent"] is None
    assert d["state"] == "discharging"


def test_device_exact_percent():
    d = desk.device({"Type": 17, "Percentage": 80.0, "BatteryLevel": 1, "State": 1, "TimeToFull": 600})
    assert d["kind"] == "headset" and d["percent"] == 80.0 and d["level"] is None
    assert d["state"] == "charging" and d["time_to_full"] == 600


def test_merge_inhibitors_dedupes_and_sorts():
    logind = [
        ("sleep", "UPower", "Pause device polling", "delay", 0, 10),
        ("idle:sleep", "vigor", "Kept awake", "block", 1000, 11),
    ]
    requested = [
        ("idle:sleep", "vigor", "Kept awake", "block", 3),
        ("idle", "Firefox", "Playing video", "block", 3),
        ("sleep", "Steam", "Downloading", "block", 3),
    ]
    active = [("idle", "Firefox", "Playing video", "block", 3)]
    out = desk.merge_inhibitors(logind, requested, active)
    assert [i["who"] for i in out] == ["Firefox", "Steam", "vigor", "UPower"]
    assert out[1]["allowed"] is False and out[0]["allowed"] is True
    assert out[2]["ours"] and out[2]["source"] == "logind"


def test_sensors_and_cpu(tmp_path, put):
    put("sys/class/hwmon/hwmon2/name", "k10temp\n")
    put("sys/class/hwmon/hwmon2/temp1_input", "41250\n")
    put("sys/class/hwmon/hwmon2/temp1_label", "Tctl\n")
    put("sys/class/hwmon/hwmon10/name", "nct6775\n")
    put("sys/class/hwmon/hwmon10/fan1_input", "900\n")
    put("sys/class/hwmon/hwmon10/fan2_input", "0\n")
    s = desk.sensors(tmp_path)
    assert s["temps"] == [{"chip": "k10temp", "label": "Tctl", "c": 41.25}]
    assert s["fans"] == [{"chip": "nct6775", "label": "fan1", "rpm": 900}]

    base = "sys/devices/system/cpu/cpufreq"
    for i, f in ((0, "2000000"), (1, "3000000")):
        put(f"{base}/policy{i}/scaling_cur_freq", f + "\n")
        put(f"{base}/policy{i}/scaling_governor", "schedutil\n")
        put(f"{base}/policy{i}/cpuinfo_max_freq", "3750000\n")
    put(f"{base}/boost", "0\n")
    c = desk.cpu(tmp_path)
    assert (c["mhz"], c["peak_mhz"], c["max_mhz"], c["boost"]) == (2500, 3000, 3750, False)


def test_profile_state_source(tmp_path, put, monkeypatch):
    daemon = {"active": "balanced", "profiles": ["power-saver", "balanced"], "managed": False,
              "degraded": "", "holds": [], "service": ()}
    put("sys/devices/system/cpu/cpufreq/policy0/scaling_governor", "performance\n")
    monkeypatch.setattr(desk, "BIN", "/bin/vigor")
    st = desk.profile_state(tmp_path, daemon)
    assert st["source"] == "cpufreq" and st["active"] == "performance" and len(st["available"]) == 3
    st = desk.profile_state(tmp_path, {**daemon, "managed": True})
    assert st["source"] == "ppd" and st["available"] == ["power-saver", "balanced"]
    monkeypatch.setattr(desk, "BIN", "")
    assert desk.profile_state(tmp_path, daemon)["source"] == "ppd"
    assert desk.profile_state(tmp_path, None) is None


def test_hold_rejects_unknown_kind():
    assert desk.start_hold("coffee", 0) == 2
    assert desk.stop_hold("coffee") == 2
