import importlib.util
from pathlib import Path

import pytest

EXAMPLES = [
    pytest.param(e, id=e.name)
    for e in (Path(__file__).parent / "examples").glob("*.py")
]


@pytest.mark.parametrize("example", EXAMPLES)
def test_examples(example: Path):
    spec = importlib.util.spec_from_file_location(
        f"test_example_{example.with_suffix('').name}", example
    )
    assert spec
    assert spec.loader
    foo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(foo)
