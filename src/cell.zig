const std = @import("std");
const style = @import("style.zig");

/// One cell on the terminal's screen. Might be a single whole character or half of a wide character, and is preceded by zero or more zero-width characters.
pub const Cell = struct {
    /// This field is -1 (0x1fffff) if the cell is the second half of a wide character.
    char: u21,
    style: style.Style,
    zero_widths: std.ArrayListUnmanaged(u21) = std.ArrayListUnmanaged(u21){},
};

/// A cell that remembers its place in memory so that pointers to it can be trivially copied.
const OwnedCell = struct {
    owner: *OwnedCell,
    inner: Cell,

    const Self = @This();

    pub fn allocate(allocator: std.mem.Allocator) !*Self {
        var me = try allocator.create(Self);
        me.owner = me;
        return me;
    }
};

const SmallColourTag = enum(u1) {
    primary,
    indexed,
};

const SmallColour = packed struct {
    tag: SmallColourTag = .primary,
    index: u8 = 0xBA,

    const Self = @This();

    pub fn pack(colour: style.Colour) !Self {
        return switch (colour) {
            .default => .{.tag = .primary, .index = 0xBA},
            .primary => |c| .{.tag = .primary, .index = c},
            .indexed => |c| .{.tag = .indexed, .index = c},
            else => error.Unpackable,
        };
    }

    pub fn unpack(self: Self) style.Colour {
        return switch (self.tag) {
            .primary => if (self.index == 0xBA) .default else .{.primary = self.index},
            .indexed => .{.indexed = self.index},
        };
    }
};

/// A 63-bit type representing a subset of values of type `Cell`.
/// When possible, this type is used in place of a pointer to avoid allocating a `Cell`.
const SmallCell = packed struct(u63) {
    char: u21 = ' ',
    foreground: SmallColour = .{},
    background: SmallColour = .{},
    _: u24 = undefined,

    const Self = @This();

    pub fn pack(cell: Cell) !Self {
        return .{
            .char = cell.char,
            .foreground = try SmallColour.pack(cell.style.foreground),
            .background = try SmallColour.pack(cell.style.background),
        };
    }

    pub fn unpack(self: Self) Cell {
        return .{
            .char = self.char,
            .style = .{
                .foreground = self.foreground.unpack(),
                .background = self.background.unpack(),
            },
        };
    }
};

/// A packed 64-bit representation of a `Cell`.
/// This type is a tagged pointer union. If the LSB of `data` is 1, the remaining 63 bits are a `SmallCell`; otherwise, the whole value is a pointer to an allocated `Cell`.
/// The same allocator must be passed to all calls of `assign` and `deinit`.
pub const PackedCell = struct {
    data: u64,

    const Self = @This();

    fn from_small_cell(cell: SmallCell) Self {
        return .{.data = @intCast(u64, @bitCast(u63, cell)) << 1 | 1};
    }

    fn is_small_cell(self: Self) bool {
        return self.data & 1 == 1;
    }

    fn as_small_cell(self: Self) SmallCell {
        return @bitCast(SmallCell, @intCast(u63, self.data >> 1));
    }

    fn deref(self: Self) *OwnedCell {
        return @intToPtr(*OwnedCell, self.data);
    }

    fn allocate(self: *Self, allocator: std.mem.Allocator) !void {
        self.data = @ptrToInt(try OwnedCell.allocate(allocator));
    }

    fn owned(self: Self) bool {
        return self.deref().owner == self.deref();
    }

    pub fn init() Self {
        return Self.from_small_cell(SmallCell{});
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        if (!self.is_small_cell() and self.owned()) allocator.destroy(self.deref());
    }

    /// Copy assignment from a Cell. Allocates if `self` is a `SmallCell` and the input cannot be represented as one.
    pub fn assign(self: *Self, allocator: std.mem.Allocator, cell: Cell) !void {
        if (self.is_small_cell()) {
            if (SmallCell.pack(cell)) |p| {
                self.* = Self.from_small_cell(p);
                return;
            } else |_| {}
        }
        if (self.is_small_cell() or !self.owned()) {
            try self.allocate(allocator);
        }
        self.deref().inner = cell;
    }

    /// Return the value's contents as a `Cell`.
    pub fn as_cell(self: Self) Cell {
        if (self.is_small_cell()) {
            return self.as_small_cell().unpack();
        }
        return self.deref().inner;
    }
};
