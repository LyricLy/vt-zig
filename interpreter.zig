pub const Interpreter = struct {
    const Self = @This();

    pub fn execute(_: *Self, _: u8) void {}
    pub fn print(_: *Self, _: u8) void {}
    pub fn csi_dispatch(_: *Self, _: []u14, _: ?u8, _: u8) void {}
};
