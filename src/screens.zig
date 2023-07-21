const std = @import("std");
const main = @import("main.zig");
const Cell = main.cell.Cell;
const Style = main.style.Style;

pub fn FixedSizeScreen(comptime W: usize, comptime H: usize) type {
    return struct {
        grid: [H][W]Cell = .{.{.{}} ** W} ** H,
        cur_x: usize = 0,
        cur_y: usize = 0,
        style: Style = .{},

        const Self = @This();
        pub const Args = struct {};

        pub fn init(_: Args) Self {
            return .{};
        }

        pub fn width(_: *const Self) usize {
            return W;
        }

        pub fn height(_: *const Self) usize {
            return H;
        }

        pub fn as_slice(self: *Self) []Cell {
            return @ptrCast(*[W*H]Cell, &self.grid);
        }

        pub fn at(self: *Self, x: usize, y: usize) *Cell {
            return &self.grid[y][x];
        }
    };
}

test "fixed size screen works" {
    var screen = FixedSizeScreen(80, 24).init(.{});
    try std.testing.expectEqual(screen.width(), 80);
    try std.testing.expectEqual(screen.height(), 24);
    const cell: Cell = .{.char = '!'};
    screen.at(0, 0).* = cell;
    try std.testing.expectEqualSlices(Cell, screen.as_slice(), &(.{cell} ++ .{.{}} ** (80*24 - 1)));
}
