/// A 63-bit type representing a subset of values of type `Cell`.
/// When possible, this type is used in place of a pointer to avoid allocating a `Cell`.
const SmallCell = packed struct(u63) {
    _: u63 = undefined,
};

/// A packed 64-bit representation of a `Cell`.
/// This type is a tagged pointer union. If the LSB of `data` is 1, the remaining 63 bits are a `SmallCell`; otherwise, the whole value is a pointer to an allocated `Cell`.
const PackedCell = struct {
    data: u64,

    const Self = @This();

    fn from_small_cell(cell: SmallCell) Self {
        return .{.data = @intCast(u64, @bitCast(u63, cell)) << 1 | 1};
    }

    fn as_small_cell(self: Self) ?SmallCell {
        return if (self.data & 1 == 1) @bitCast(SmallCell, @intCast(u63, self.data >> 1)) else null;
    }
};

test "it works" {
    const c: SmallCell = .{};
    _ = Cell.from_small_cell(c).as_small_cell();
}
