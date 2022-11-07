import mmap
from unittest import mock

import pytest

import pyperscan as ps


def args(*args, **kwargs):
    return (args, kwargs)


@pytest.mark.parametrize(
    "args",
    (
        pytest.param(
            args(
                b"foo",
            ),
            id="default-args",
        ),
        pytest.param(args(b"foo", ps.Flag.SOM_LEFTMOST), id="single-flag"),
        pytest.param(
            args(b"foo", ps.Flag.SOM_LEFTMOST, ps.Flag.DOTALL), id="multiple-flags"
        ),
        pytest.param(
            args(b"foo", ps.Flag.SOM_LEFTMOST, ps.Flag.DOTALL, tag="bar"),
            id="flag-tag",
        ),
    ),
)
def test_patterns(args):
    ps.Pattern(*args[0], **args[1])


def test_pattern_expression_argument_is_required():
    with pytest.raises(
        TypeError, match="missing 1 required positional argument: 'expression'"
    ):
        ps.Pattern()  # type: ignore


def test_pattern_expression_argument_must_be_str():
    with pytest.raises(
        TypeError,
        match="argument 'expression': 'str' object cannot be converted to 'PyBytes'",
    ):
        ps.Pattern("foo")  # type: ignore


def test_pattern_flags_argument_must_be_flags():
    with pytest.raises(
        TypeError,
        match="'int' object cannot be converted to 'Flag'",
    ):
        ps.Pattern(b"foo", 123)  # type: ignore


@pytest.fixture
def tag():
    return "tag"


@pytest.fixture
def database(request, tag):
    pat = ps.Pattern(b"foo", ps.Flag.SOM_LEFTMOST, tag=tag)
    return request.param(pat)


@pytest.fixture
def ctx():
    return object()


@pytest.fixture
def on_match():
    on_match = mock.Mock()
    on_match.return_value = ps.Scan.Continue
    return on_match


@pytest.mark.parametrize("database", (ps.BlockDatabase,), indirect=True)
def test_block_database(database, ctx, tag, on_match):
    scan = database.build(ctx, on_match)

    scan.scan(b"foo")
    on_match.assert_called_with(ctx, tag, 0, 3)
    scan.scan(b"barfoo")
    on_match.assert_called_with(ctx, tag, 3, 6)


@pytest.mark.parametrize(
    "database",
    (ps.VectoredDatabase,),
    indirect=True,
)
def test_vectored_database(database, ctx, tag, on_match):
    scan = database.build(ctx, on_match)

    scan.scan([b"foo", b"barfoo"])
    on_match.assert_has_calls((mock.call(ctx, tag, 0, 3), mock.call(ctx, tag, 6, 9)))


@pytest.mark.parametrize(
    "database",
    (ps.StreamDatabase,),
    indirect=True,
)
def test_stream_database(database, ctx, tag, on_match):
    scan = database.build(ctx, on_match)

    scan.scan(b"foo")
    on_match.assert_called_with(ctx, tag, 0, 3)
    scan.scan(b"barf")
    scan.scan(b"oo")
    on_match.assert_called_with(ctx, tag, 6, 9)


def test_pattern_tags(ctx, on_match):
    scan = ps.BlockDatabase(ps.Pattern(b"foo", tag="tag"), ps.Pattern(b"bar")).build(
        ctx, on_match
    )
    scan.scan(b"foo")
    on_match.assert_called_with(ctx, "tag", 0, 3)
    scan.scan(b"bar")
    on_match.assert_called_with(ctx, 1, 0, 3)


def test_data_can_be_mmap_object(ctx, on_match):
    scan = ps.BlockDatabase(ps.Pattern(b"foo")).build(ctx, on_match)

    with mmap.mmap(-1, len("foo")) as mm:
        mm.write(b"foo")

        scan.scan(mm)
        on_match.assert_called_with(ctx, 0, 0, 3)


@pytest.mark.parametrize(
    "database,data",
    (
        (ps.BlockDatabase, b"foofoo"),
        (
            ps.VectoredDatabase,
            (b"foofoo",),
        ),
        (ps.StreamDatabase, b"foofoo"),
    ),
    indirect=("database",),
)
def test_scanning_can_be_aborted(database, data, ctx, tag, on_match):
    scan = database.build(ctx, on_match)

    on_match.return_value = ps.Scan.Continue
    assert scan.scan(data) == ps.Scan.Continue
    assert on_match.call_count == 2

    on_match.reset_mock()
    on_match.return_value = ps.Scan.Terminate
    assert scan.scan(data) == ps.Scan.Terminate
    assert on_match.call_count == 1
