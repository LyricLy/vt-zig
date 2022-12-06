const std = @import("std");
const style = @import("style.zig");

/// One cell on the terminal's screen. Might be a single whole character or half of a wide character, and is preceded by zero or more zero-width characters.
pub const Cell = struct {
    /// This field is -1 (0x1fffff) if the cell is the second half of a wide character.
    char: u21 = ' ',
    style: style.Style = .{},
    zero_widths: std.ArrayListUnmanaged(u21) = std.ArrayListUnmanaged(u21){},
};
