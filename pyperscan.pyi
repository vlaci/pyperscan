from collections.abc import Callable, Collection
from mmap import mmap
from typing import Any, TypeVar, Union

class Flag:
    CASELESS = ...
    DOTALL = ...
    MULTILINE = ...
    SINGLEMATCH = ...
    ALLOWEMPTY = ...
    UTF8 = ...
    UCP = ...
    PREFILTER = ...
    SOM_LEFTMOST = ...
    COMBINATION = ...
    QUIET = ...

class Scan:
    Continue = ...
    Terminate = ...

class Pattern:
    def __new__(cls, expression: bytes, *flags: Flag, tag=None): ...

Buffer = Union[bytes, mmap]

class BlockScanner:
    def scan(self, data: Buffer) -> Scan: ...
    def reset(self) -> Scan: ...

C = TypeVar("C")

class Database:
    def __new__(cls, *patterns: Pattern): ...
    def build(
        self, context: C, on_match: Callable[[C, Any, int, int], Scan]
    ) -> BlockScanner: ...

class BlockDatabase(Database): ...

class VectoredScanner:
    def scan(self, data: Collection[Buffer]) -> Scan: ...

class VectoredDatabase(Database): ...

class StreamScanner:
    def scan(self, data: Buffer, chunk_size: int | None = None) -> Scan: ...

class StreamDatabase(Database): ...
