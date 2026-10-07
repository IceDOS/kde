from vigor import gpu


def test_amdgpu_busy_and_ppt(tmp_path, put):
    put("sys/class/drm/card1/device/gpu_busy_percent", "17\n")
    put("sys/class/drm/card1/device/hwmon/hwmon1/power1_average", "37000000\n")
    put("sys/class/drm/card1-DP-1/status", "connected\n")
    assert gpu.read_amdgpu(tmp_path) == [gpu.GpuReading("card1", 17.0, 37.0)]


def test_amdgpu_without_power_sensor(tmp_path, put):
    put("sys/class/drm/card0/device/gpu_busy_percent", "5\n")
    assert gpu.read_amdgpu(tmp_path) == [gpu.GpuReading("card0", 5.0, None)]


def test_parse_nvidia_smi():
    out = "45, 120.50\n0, [N/A]\n"
    assert gpu.parse_nvidia_smi(out) == [
        gpu.GpuReading("nvidia0", 45.0, 120.5),
        gpu.GpuReading("nvidia1", 0.0, None),
    ]
