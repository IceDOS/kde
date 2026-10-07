import pytest

from vigor import tune

CPUFREQ = "sys/devices/system/cpu/cpufreq"


@pytest.fixture
def acpi(put):
    for i in (0, 1):
        put(f"{CPUFREQ}/policy{i}/scaling_available_governors", "performance schedutil\n")
        put(f"{CPUFREQ}/policy{i}/scaling_governor", "schedutil\n")
    put(f"{CPUFREQ}/boost", "1\n")


def test_plan_acpi_cpufreq():
    govs = ["performance", "schedutil"]
    assert tune.plan("power-saver", govs) == ("schedutil", False)
    assert tune.plan("balanced", govs) == ("schedutil", True)
    assert tune.plan("performance", govs) == ("performance", True)


def test_plan_intel_pstate_active():
    govs = ["performance", "powersave"]
    assert tune.plan("power-saver", govs) == ("powersave", False)
    assert tune.plan("balanced", govs) == ("powersave", True)


def test_plan_rejects_unknown():
    with pytest.raises(ValueError):
        tune.plan("turbo", ["performance"])


def test_apply_and_read_back(tmp_path, acpi):
    tune.apply(tmp_path, "power-saver")
    assert (tmp_path / CPUFREQ / "boost").read_text() == "0"
    assert tune.current(tmp_path) == "power-saver"
    tune.apply(tmp_path, "performance")
    assert (tmp_path / CPUFREQ / "policy1/scaling_governor").read_text() == "performance"
    assert tune.current(tmp_path) == "performance"
    tune.apply(tmp_path, "balanced")
    assert tune.current(tmp_path) == "balanced"


def test_intel_no_turbo(tmp_path, put):
    put(f"{CPUFREQ}/policy0/scaling_available_governors", "performance powersave\n")
    put(f"{CPUFREQ}/policy0/scaling_governor", "powersave\n")
    put("sys/devices/system/cpu/intel_pstate/no_turbo", "0\n")
    tune.apply(tmp_path, "power-saver")
    assert (tmp_path / "sys/devices/system/cpu/intel_pstate/no_turbo").read_text() == "1"
    assert tune.current(tmp_path) == "power-saver"


def test_restore(tmp_path, acpi):
    state = tmp_path / "var/lib/vigor/profile"
    assert tune.restore(tmp_path, state) is None
    tune.save(state, "performance")
    assert tune.restore(tmp_path, state) == "performance"
    assert tune.current(tmp_path) == "performance"
    state.write_text("bogus\n")
    assert tune.restore(tmp_path, state) is None


def test_no_cpufreq(tmp_path):
    assert tune.current(tmp_path) is None
    assert tune.governors(tmp_path) == []
