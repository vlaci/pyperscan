The following gist is to help you getting started using this library

```python
--8<-- "tests/examples/block.py"
```

1.  Create a `BlockDatabase` holding the patterns to match against
2.  Annotate patterns with flags and `tag` object to be able to distinguish, which pattern matched
3.  Create a match handler function that will be run when a match is found
4.  You can stop or continue searching with the callback's return value
5.  Define a context object to store state in your match handler callback
6.  Build a scanner object to connect the database with your callback and context
7.  Feed data to execute the scanner
