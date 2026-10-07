import os
import stat

from vigor import ailease


def test_prepare_makes_a_drop_box(tmp_path):
    d = tmp_path / "ai"
    ailease.prepare(d)
    ailease.prepare(d)
    assert stat.S_IMODE(d.stat().st_mode) == 0o1733


def test_active_needs_a_fresh_lease(tmp_path):
    d = tmp_path / "ai"
    ailease.prepare(d)
    assert ailease.active(d, 1000.0) is False
    (d / "a").touch()
    os.utime(d / "a", (990.0, 990.0))
    assert ailease.active(d, 1000.0) is False
    (d / "b").touch()
    os.utime(d / "b", (998.0, 998.0))
    assert ailease.active(d, 1000.0) is True


def test_missing_dir_is_inactive(tmp_path):
    assert ailease.active(tmp_path / "none", 1000.0) is False
