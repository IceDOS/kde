from lumen.state import FOREVER, State, locked, write_json


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
