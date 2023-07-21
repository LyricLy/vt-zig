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
        const Args = struct {};

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

pub fn Interpreter(comptime S: type) type {
    return struct {
        screens: [2]S,
        cur_idx: usize,
        raw_mode: bool,

        const Self = @This();

        pub fn init(args: S.Args, raw_mode: bool) Self {
            return .{.screens = .{S.init(args), S.init(args)}, .cur_idx = 0, .raw_mode = raw_mode};
        }

        fn current(self: *Self) *S {
            return &self.screens[self.cur_idx];
        }

        fn width(self: *const Self) usize {
            return self.current().width();
        }

        fn height(self: *const Self) usize {
            return self.current().height();
        }

        fn as_slice(self: *Self) []Cell {
            return self.current().as_slice();
        }

        fn at(self: *Self, x: usize, y: usize) *Cell {
            return self.current().at(x, y);
        }

        fn at_cursor(self: *Self) *Cell {
            return self.at(self.current().cur_x, self.current().cur_y);
        }

        fn cursor_down(self: *Self, n: usize) void {
            // TODO a lot
            self.current().cur_y += n;
        }

        fn cursor_right(self: *Self, n: usize) void {
            const new_pos = self.current().cur_x + n;
            const w = self.current().width();
            if (!self.raw_mode) {
                self.current().cur_x = new_pos % w;
                self.cursor_down(new_pos / w);
            } else {
                self.current().cur_x = std.math.min(new_pos, w-1);
            }
        }

        pub fn print(self: *Self, char: u7) void {
            // TODO: unicode
            self.at_cursor().* = Cell{.char = char, .style = self.current().style};
            self.cursor_right(1);
        }

        pub fn execute(_: *Self, _: u8) void {}
        pub fn csi_dispatch(_: *Self, _: []const u14, _: ?u8, _: u8) void {}
    };
}

test "printing works" {
    var i = Interpreter(FixedSizeScreen(80, 24)).init(.{}, false);
    inline for ("Hi!") |c| {
        i.print(c);
    }
    try std.testing.expectEqualSlices(Cell, &.{.{.char = 'H'}, .{.char = 'i'}, .{.char = '!'}}, i.as_slice()[0..3]);
}
