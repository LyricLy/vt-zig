const std = @import("std");
const main = @import("main.zig");
const Screens = main.screen.Screens;
const FixedSizeScreen = main.screen.FixedSizeScreen;
const Cell = main.cell.Cell;

pub fn Interpreter(comptime S: type) type {
    return struct {
        screens: Screens(S),

        const Self = @This();

        pub fn init(screens: Screens(S)) Self {
            return Self{.screens = screens};
        }

        pub fn print(self: *Self, char: u7) void {
            var screen = self.screens.current();
            // TODO: unicode
            screen.at_cursor().* = Cell{.char = char, .style = screen.me.style};
            screen.cursor_right(1);
        }

        pub fn execute(_: *Self, _: u8) void {}
        pub fn csi_dispatch(_: *Self, _: []const u14, _: ?u8, _: u8) void {}
    };
}

test "printing works" {
    var i = Interpreter(FixedSizeScreen(80, 24)).init(.{.screens = .{.{}, .{}}, .raw_mode = false});
    inline for ("Hi!") |c| {
        i.print(c);
    }
    try std.testing.expectEqualSlices(Cell, &.{.{.char = 'H'}, .{.char = 'i'}, .{.char = '!'}}, i.screens.current().me.as_slice()[0..3]);
}
