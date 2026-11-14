from lumen.state import FOREVER, State, locked, state_dir, write_json


def test_round_trip(tmp_path):
    with locked(tmp_path) as (st, save):
        assert st == State()
        st.paused_until = FOREVER
        st.holds["MG248"] = 123.0
        st.last["MG248"] = 40.0
        save()
    with locked(tmp_path) as (st, _):
        assert st == State(FOREVER, {"MG248": 123.0}, {"MG248": 40.0})


def test_corrupt_file_resets(tmp_path):
    (tmp_path / "state.json").write_text("{")
    with locked(tmp_path) as (st, _):
        assert st == State()


def test_write_json_atomic(tmp_path):
    write_json(tmp_path / "a" / "b.json", {"x": 1})
    assert (tmp_path / "a" / "b.json").read_text() == '{"x": 1}'


def test_migrates_legacy_state_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    legacy = tmp_path / "state" / "lumen"
    legacy.mkdir(parents=True)
    (legacy / "state.json").write_text('{"paused_until": 123.0}')
    with locked(state_dir()) as (st, _):
        assert st.paused_until == 123.0
    new_dir = tmp_path / "state" / "icedos" / "lumen"
    assert (new_dir / "state.json").exists()
    assert not legacy.exists()


def test_both_dirs_exist_merges_and_removes_legacy(tmp_path, monkeypatch):
    import os
    import time
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    legacy = tmp_path / "state/lumen"
    new_dir = tmp_path / "state/icedos/lumen"
    legacy.mkdir(parents=True)
    new_dir.mkdir(parents=True)
    (legacy / "lock").write_text("")
    (new_dir / "state.json").write_text('{"paused_until": 100.0}')
    (legacy / "state.json").write_text('{"paused_until": 200.0}')
    now = time.time()
    os.utime(new_dir / "state.json", (now - 100, now - 100))
    os.utime(legacy / "state.json", (now, now))
    (legacy / "edits.json").write_text('{"points": []}')

    with locked(state_dir()) as (st, _):
        assert st.paused_until == 200.0
    assert (new_dir / "edits.json").exists()
    assert not legacy.exists()
