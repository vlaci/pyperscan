from array import array
from collections.abc import Collection
from mmap import mmap
from typing import Any, Generic, Protocol, TypeAlias, TypeVar, Union

BufferType: TypeAlias = Union[array[int], bytes, bytearray, memoryview, mmap]
_TContext_contra = TypeVar("_TContext_contra", contravariant=True)
_TScanner = TypeVar("_TScanner", BlockScanner, VectoredScanner, StreamScanner)

class Pattern:
    """Pattern to search matches for."""

    def __new__(cls, expression: bytes, *flags: Flag, tag: Any = None):
        """Construct a new search pattern.

        Args:
            expression: Regular expression.
            flags: modify expression matching behavior.
            tag: Python object to pass to callback when match succeeds.
                If unset, the pattern index is used.
        """

class Flag:
    """Pattern compile flags."""

    CASELESS: Flag = ...
    """Set case-insensitive matching.

    This flag sets the expression to be matched case-insensitively by default.  The
    expression may still use PCRE tokens (notably (?i) and (?-i)) to switch
    case-insensitive matching on and off.

    See
    [HS_FLAGS_CASELESS](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_CASELESS)
    """
    DOTALL: Flag = ...
    """Matching a `.` will not exclude newlines.

    This flag sets any instances of the `.` token to match newline characters as well as
    all other characters.  The PCRE specification states that the `.` token does not
    match newline characters by default, so without this flag the `.` token will not
    cross line boundaries.

    See
    [HS_FLAGS_DOTALL](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_DOTALL)
    """
    MULTILINE: Flag = ...
    """Set multi-line anchoring.

    This flag instructs the expression to make the `^` and `$` tokens match newline
    characters as well as the start and end of the stream.  If this flag is not
    specified, the `^` token will only ever match at the start of a stream, and the `$`
    token will only ever match at the end of a stream within the guidelines of the PCRE
    specification.

    See
    [HS_FLAGS_MULTILINE](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_MULTILINE)
    """
    SINGLEMATCH: Flag = ...
    """Set single-match only mode.

    This flag sets the expression's match ID to match at most once.  In streaming mode,
    this means that the expression will return only a single match over the lifetime of
    the stream, rather than reporting every match as per standard Hyperscan semantics.
    In block mode or vectored mode, only the first match for each invocation of
    `scan()` will be returned.

    If multiple expressions in the database share the same match ID, then they either
    must all specify `SINGLEMATCH`. or none of them specify `SINGLEMATCH`.
    If a group of expressions sharing a match ID specify the flag, then at most one
    match with the match ID will be generated per stream.

    Note: The use of this flag in combination with `SOM_LEFTMOST` is not currently
    supported.

    See
    [HS_FLAGS_SINGLEMATCH](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_SINGLEMATCH)
    """
    ALLOWEMPTY: Flag = ...
    """Allow expressions that can match against empty buffers.

    This flag instructs the compiler to allow expressions that can match against empty
    buffers, such as `.?`, `.*`, `(a|)`.  Since Hyperscan can return every possible
    match for an expression, such expressions generally execute very slowly; the default
    behaviour is to return an error when an attempt to compile one is made.  Using this
    flag will force the compiler to allow such an expression.

    See
    [HS_FLAGS_ALLOWEMPTY](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_ALLOWEMPTY)
    """
    UTF8: Flag = ...
    """Enable UTF-8 mode for this expression.

    This flag instructs Hyperscan to treat the pattern as a sequence of UTF-8
    characters.  The results of scanning invalid UTF-8 sequences with a Hyperscan
    library that has been compiled with one or more patterns using this flag are
    undefined.

    See
    [HS_FLAGS_UTF8](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_UTF8)
    """
    UCP: Flag = ...
    """Enable Unicode property support for this expression.

    This flag instructs Hyperscan to use Unicode properties, rather than the default
    ASCII interpretations, for character mnemonics like \\w and \\s as well as the POSIX
    character classes.  It is only meaningful in conjunction with
    [UTF8][pyperscan._pyperscan.Flag.UTF8].

    See
    [HS_FLAGS_UCP](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_UCP)
    """
    PREFILTER: Flag = ...
    """Enable prefiltering mode for this expression.

    This flag instructs Hyperscan to compile an “approximate” version of this pattern
    for use in a prefiltering application, even if Hyperscan does not support the
    pattern in normal operation.

    The set of matches returned when this flag is used is guaranteed to be a superset of
    the matches specified by the non-prefiltering expression.

    If the pattern contains pattern constructs not supported by Hyperscan (such as
    zero-width assertions, back-references or conditional references) these constructs
    will be replaced internally with broader constructs that may match more often.

    Furthermore, in prefiltering mode Hyperscan may simplify a pattern that would
    otherwise return a “Pattern too large” error at compile time, or for performance
    reasons (subject to the matching guarantee above).

    It is generally expected that the application will subsequently confirm prefilter
    matches with another regular expression matcher that can provide exact matches for
    the pattern.

    Note: The use of this flag in combination with
    [SOM_LEFTMOST][pyperscan._pyperscan.Flag.SOM_LEFTMOST] is not currently supported.

    See
    [HS_FLAGS_PREFILTER](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_PREFILTER)
    """
    SOM_LEFTMOST: Flag = ...
    """Enable leftmost start of match reporting.

    This flag instructs Hyperscan to report the leftmost possible start of match offset
    when a match is reported for this expression.  (By default, no start of match is
    returned.)

    For all the 3 modes, enabling this behaviour may reduce performance.  And
    particularly, it may increase stream state requirements in streaming mod

    See
    [HS_FLAGS_LEFTMOST](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_LEFTMOST)
    """
    COMBINATION: Flag = ...
    """Logical combination.

    This flag instructs Hyperscan to parse this expression as logical combination
    syntax.  Logical constraints consist of operands, operators and parentheses.  The
    operands are expression indices, and operators can be `!` (NOT), `&` (AND) or `|`
    (OR).  For example: `(101&102&103)|(104&!105)` `((301|302)&303)&(304|305)`

    See
    [HS_FLAGS_COMBINATION](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_COMBINATION)
    """
    QUIET: Flag = ...
    """Don't do any match reporting.

    This flag instructs Hyperscan to ignore match reporting for this expression.  It is
    designed to be used on the sub-expressions in logical combinations.

    See
    [HS_FLAGS_QUIET](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.HS_FLAG_QUIET)
    """

class OnMatch(Protocol, Generic[_TContext_contra]):
    """Callback called on match."""

    def __call__(
        self, context: _TContext_contra, tag: Any, start: int, end: Any
    ) -> Scan:
        """Called when a match happens.

        Note:
            Call parameters are passed positonally.

        Args:
            context: Object passed to [Database.build][pyperscan._pyperscan.Database.build]
            tag: [Pattern.tag][pyperscan._pyperscan.Pattern] of the pattern matched.
            start: start index of the matched pattern.
            end: end index of the matched pattern.

        Returns:
            Instructs Hyperscan wether to continue or stop searching for subsequent matches.
        """

class Database(Generic[_TScanner]):
    """A Hyperscan pattern database."""

    def __new__(cls, *patterns: Pattern):
        """Compiles a Hyperscan pattern database.

        Args:
            patterns: Expressions to compile into the database to later match against.

        Note:
            Calls [hs_compile_ext_multi](https://intel.github.io/hyperscan/dev-reference/api_files.html#c.hs_compile_ext_multi)
            internally.
        """
    def build(
        self, context: _TContext_contra, on_match: OnMatch[_TContext_contra]
    ) -> _TScanner:
        """Build a scanner object that is usable to search for pattern procurances.

        Args:
            context: arbitrary object which is passed as a first parameter to `on_match`.
            on_match: callable to call when a match happens upon `scan` call.
        """

class BlockDatabase(Database[BlockScanner]):  # noqa: F821
    """A database for block (non-streaming) scanning."""

class VectoredDatabase(Database[VectoredScanner]):  # noqa: F821
    """A databes for vectored scanning."""

class StreamDatabase(Database[StreamScanner]):  # noqa: F821
    """A database for stream scanning."""

class Scan:
    """Match callback return value to instruct Hyperscan wether to contine or terminate scanning."""

    Continue: Scan = ...
    """Continue scanning."""
    Terminate: Scan = ...
    """Terminate scanning."""

class BlockScanner:
    """Created from `BlockDatabase` for block scanning."""

    def scan(self, data: BufferType) -> Scan:
        """Scan for matches in a single buffer (block).

        Args:
            data: buffer to search matches in. Can be any object implementing the buffer protocol.

        Returns:
            Indicates if scanning is terminated from `OnMatch` callback.
        """

class VectoredScanner:
    """Created from `VectoredDatabase` for scanning."""

    def scan(self, data: Collection[BufferType]) -> Scan:
        """Scan for matches in a multiple buffers (vector).

        Args:
            data: buffer to search matches in. Can be any object implementing the buffer protocol.

        Returns:
            Indicates if scanning is terminated from `OnMatch` callback.
        """

class StreamScanner:
    """Created from `StreamDatabase` for stream scanning."""

    def scan(self, data: BufferType, chunk_size: int | None = None) -> Scan:
        """Scan for matches in a stream.

        Multiple calls constitute to the same scanning operation, matches can happen at
        the edge of multiple `scan` calls, and match start/end offsets are counted from
        the first scan call.

        Args:
            data: buffer to search matches in. Can be any object implementing the buffer protocol.
            chunk_size: when provided, `data` is scanned in `chunk_size` bits.

        Tip:
            Hyperscan can match only up-to the first `4 GiB` of buffers. Use an
            arbitrary big buffer with a `chunk_size` less than `4 GiB` to overcome this
            limitation.

        Returns:
            Indicates if scanning is terminated from `OnMatch` callback.
        """
    def reset(self) -> Scan:
        """Reset stream scanning to its initial state.

        After this method is called, all in-flight possible matches are discarded and
        subsequent `scan` operation will act as the first call, counting match index
        from zero.
        """

class HyperscanErrorCode:
    """List of errors can be returned by the low level Hyperscan operations.

    Most error codes cannot appear in Pyperscan.
    """

    Invalid: HyperscanErrorCode = ...
    """A parameter passed to this function was invalid.

    This error is only returned in cases where the function can detect an invalid
    parameter it cannot be relied upon to detect (for example) pointers to freed memory
    or other invalid data.
    """

    Nomem: HyperscanErrorCode = ...
    """A memory allocation failed."""

    ScanTerminated: HyperscanErrorCode = ...
    """The engine was terminated by callback.

    This return value indicates that the target buffer was partially scanned, but that
    the callback function requested that scanning cease after a match was located.
    """

    CompilerError: HyperscanErrorCode = ...
    """The pattern compiler failed, and the hs_compile_error_t should be inspected for
    more detail.
    """

    DbVersionError: HyperscanErrorCode = ...
    """The given database was built for a different version of Hyperscan."""

    DbPlatformError: HyperscanErrorCode = ...
    """The given database was built for a different platform (i.e., CPU type)."""

    DbModeError: HyperscanErrorCode = ...
    """The given database was built for a different mode of operation.

    This error is returned when streaming calls are used with a block or vectored
    database and vice versa.
    """

    BadAlign: HyperscanErrorCode = ...
    """A parameter passed to this function was not correctly aligned."""

    BadAlloc: HyperscanErrorCode = ...
    """The memory allocator (either malloc() or the allocator set with
    hs_set_allocator()) did not correctly return memory suitably aligned for the largest
    representable data type on this platform.
    """

    ScratchInUse: HyperscanErrorCode = ...
    """The scratch region was already in use.

    This error is returned when Hyperscan is able to detect that the scratch region
    given is already in use by another Hyperscan API call.

    A separate scratch region, allocated with hs_alloc_scratch() or hs_clone_scratch(),
    is required for every concurrent caller of the Hyperscan API.

    For example, this error might be returned when hs_scan() has been called inside a
    callback delivered by a currently-executing hs_scan() call using the same scratch
    region.

    Note: Not all concurrent uses of scratch regions may be detected.  This error is
    intended as a best-effort debugging tool, not a guarantee.
    """

    ArchError: HyperscanErrorCode = ...
    """Unsupported CPU architecture.

    This error is returned when Hyperscan is able to detect that the current system does
    not support the required instruction set.

    At a minimum, Hyperscan requires Supplemental Streaming SIMD Extensions 3 (SSSE3).
    """

    InsufficientSpace: HyperscanErrorCode = ...
    """
    Provided buffer was too small.

    This error indicates that there was insufficient space in the buffer.  The call
    should be repeated with a larger provided buffer.

    Note: in this situation, it is normal for the amount of space required to be
    returned in the same manner as the used space would have been returned if the call
    was successful.
    """

    UnknownError: HyperscanErrorCode = ...
    """Unexpected internal error.

    This error indicates that there was unexpected matching behaviors.  This could be
    related to invalid usage of stream and scratch space or invalid memory operations by
    users.
    """

    UnknownErrorCode: HyperscanErrorCode = ...
    """An error unknown to Pyperscan happened."""

class HyperscanError:
    """An error happened while calling the low level Hyperscan API."""

    args: tuple[HyperscanErrorCode, int]
    """An error flag and low level error codes."""

class HyperscanCompileError:
    """One of the patterns to be compiled is invalid."""

    args: tuple[str, int]
    """Contains a human readable message and the index of the offending pattern."""
