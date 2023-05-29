import pyperscan as ps

db = ps.BlockDatabase(  # (1)!
    ps.Pattern(b"foo.*bar", ps.Flag.SOM_LEFTMOST),
    ps.Pattern(b"bar.*foo", ps.Flag.SOM_LEFTMOST, ps.Flag.DOTALL, tag="tag"),  # (2)!
)


def on_match(ctx, tag, start, end):  # (3)!
    #        ─┬─  ─┬─  ──┬──  ─┬─
    #         │    │     │     └ match end index
    #         │    │     └ match start index (needs SOM_LEFTMOST flag)
    #         │    └ pattern tag, or index
    #         └ arbitrary object to store state
    return ps.Scan.Continue  # (4)!


ctx = ...  # (5)!
scanner = db.build(ctx, on_match)  # (6)!

scanner.scan(b"foobar")  # (7)!
