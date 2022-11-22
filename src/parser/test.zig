const std = @import("std");
const Parser = @import("../main.zig").parser.Parser;

const CsiDispatch = struct {
    params: []const u14,
    intermediate: ?u8,
    byte: u8,
};

const Action = union(enum) {
    execute: u8,
    print: u8,
    csi_dispatch: CsiDispatch,
};

const MockInterpreter = struct {
    const Self = @This();

    actions: std.ArrayList(Action),

    fn init() Self {
        return Self{.actions = std.ArrayList(Action).init(std.testing.allocator)};
    }

    fn deinit(self: *Self) void {
        self.actions.deinit();
    }

    pub fn execute(self: *Self, byte: u8) void {
        self.actions.append(.{.execute = byte}) catch unreachable;
    }

    pub fn print(self: *Self, byte: u8) void {
        self.actions.append(.{.print = byte}) catch unreachable;
    }

    pub fn csi_dispatch(self: *Self, params: []const u14, intermediate: ?u8, byte: u8) void {
        self.actions.append(.{.csi_dispatch = .{.params = params, .intermediate = intermediate, .byte = byte}}) catch unreachable;
    }
};

test "do nothing" {
    var interpreter = MockInterpreter.init();
    defer interpreter.deinit();
    // parser is unneeded because we don't feed anything to it
    _ = Parser(*MockInterpreter).init(&interpreter);

    try std.testing.expect(interpreter.actions.items.len == 0);
}

test "print" {
    var interpreter = MockInterpreter.init();
    defer interpreter.deinit();
    var parser = Parser(*MockInterpreter).init(&interpreter);

    parser.accept("Hi!");

    try std.testing.expectEqualSlices(Action, &.{.{.print = 'H'}, .{.print = 'i'}, .{.print = '!'}}, interpreter.actions.items);
}

test "csi" {
    var interpreter = MockInterpreter.init();
    defer interpreter.deinit();
    var parser = Parser(*MockInterpreter).init(&interpreter);

    parser.accept("\x1B[12;34a");

    try std.testing.expect(interpreter.actions.items.len == 1);
    const dispatch = switch (interpreter.actions.items[0]) {
        .csi_dispatch => |a| a,
        else => return error.WrongActionType,
    };
    try std.testing.expectEqualSlices(u14, &.{12, 34}, dispatch.params);
    try std.testing.expect(dispatch.intermediate == null and dispatch.byte == 'a');
}
