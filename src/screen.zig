const std = @import("std");
const Cell = @import("cell.zig").Cell;
const Style = @import("style.zig").Style;

pub fn FixedSizeScreen(comptime W: usize, comptime H: usize) type {
    return struct {
        grid: [H][W]Cell = .{.{.{}} ** W} ** H,
        cur_x: usize = 0,
        cur_y: usize = 0,
        style: Style = .{},

        const Self = @This();

        pub fn width(_: *Self) usize {
            return W;
        }

        pub fn height(_: *Self) usize {
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

pub fn Screen(comptime S: type) type {
    return struct {
        me: *S,
        raw_mode: bool,

        const Self = @This();

        pub fn at_cursor(self: Self) *Cell {
            return self.me.at(self.me.cur_x, self.me.cur_y);
        }

        pub fn cursor_down(self: Self, n: usize) void {
            // TODO a lot
            self.me.cur_y += n;
        }

        pub fn cursor_right(self: Self, n: usize) void {
            const new_pos = self.me.cur_x + n;
            const width = self.me.width();
            if (!self.raw_mode) {
                self.me.cur_x = new_pos % width;
                self.cursor_down(new_pos / width);
            } else {
                self.me.cur_x = std.math.min(new_pos, width-1);
            }
        }
    };
}

pub fn Screens(comptime S: type) type {
    return struct {
        screens: [2]S,
        cur_idx: usize = 0,
        raw_mode: bool,

        const Self = @This();

        pub fn current(self: *Self) Screen(S) {
            return .{.me = &self.screens[self.cur_idx], .raw_mode = self.raw_mode};
        }
    };
}
