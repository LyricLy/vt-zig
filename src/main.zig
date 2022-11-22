const std = @import("std");

pub const parser = @import("parser.zig");
pub const interpreter = @import("interpreter.zig");

test {
    std.testing.refAllDecls(@This());
}
