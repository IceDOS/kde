from pathlib import Path

import pytest


@pytest.fixture
def put(tmp_path):
    """Write a file under tmp_path, creating parents; tests use tmp_path as a fake /."""
    def _put(rel: str, text: str) -> Path:
        p = tmp_path / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p
    return _put
