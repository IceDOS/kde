"""CPU governor and boost per power profile, for CPUs power-profiles-daemon can't drive (acpi-cpufreq)."""
from pathlib import Path

PROFILES = ("power-saver", "balanced", "performance")
# First available wins; intel_pstate in active mode only offers powersave and performance.
_BALANCED = ("schedutil", "ondemand", "conservative", "powersave")


def _cpufreq(root: Path) -> Path:
    return root / "sys/devices/system/cpu/cpufreq"


def policies(root: Path) -> list[Path]:
    return sorted(_cpufreq(root).glob("policy[0-9]*"), key=lambda p: int(p.name[6:]))


def governors(root: Path) -> list[str]:
    pol = policies(root)
    if not pol:
        return []
    try:
        return (pol[0] / "scaling_available_governors").read_text().split()
    except OSError:
        return []


def plan(profile: str, govs: list[str]) -> tuple[str, bool]:
    """The governor and boost state a profile maps to, given the governors on offer."""
    if profile not in PROFILES:
        raise ValueError(f"unknown profile {profile!r}")
    if profile == "performance" and "performance" in govs:
        return "performance", True
    if profile == "power-saver" and "powersave" in govs and "schedutil" not in govs:
        return "powersave", False
    gov = next((g for g in _BALANCED if g in govs), govs[0] if govs else "")
    return gov, profile != "power-saver"


def read_boost(root: Path) -> bool | None:
    try:
        return (_cpufreq(root) / "boost").read_text().strip() == "1"
    except OSError:
        pass
    try:
        return (root / "sys/devices/system/cpu/intel_pstate/no_turbo").read_text().strip() == "0"
    except OSError:
        return None


def write_boost(root: Path, on: bool) -> None:
    boost = _cpufreq(root) / "boost"
    if boost.exists():
        boost.write_text("1" if on else "0")
        return
    no_turbo = root / "sys/devices/system/cpu/intel_pstate/no_turbo"
    if no_turbo.exists():
        no_turbo.write_text("0" if on else "1")


def current(root: Path) -> str | None:
    """The profile the CPU is in now, read back from sysfs."""
    pol = policies(root)
    if not pol:
        return None
    gov = (pol[0] / "scaling_governor").read_text().strip()
    if gov == "performance":
        return "performance"
    return "power-saver" if read_boost(root) is False else "balanced"


def apply(root: Path, profile: str) -> None:
    gov, boost = plan(profile, governors(root))
    for p in policies(root):
        (p / "scaling_governor").write_text(gov)
    write_boost(root, boost)


def save(state: Path, profile: str) -> None:
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(profile + "\n")


def restore(root: Path, state: Path) -> str | None:
    try:
        profile = state.read_text().strip()
    except OSError:
        return None
    if profile not in PROFILES:
        return None
    apply(root, profile)
    return profile
