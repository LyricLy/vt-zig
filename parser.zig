//! An implementation of Paul Williams' state machine for ANSI-compatible terminals.

const Interpreter = @import("interpreter.zig").Interpreter;

const IntermediateCell = union(enum) {
    const Self = @This();

    none: void,
    one: u8,
    too_many: void,

    fn add(self: *Self, byte: u8) void {
        self.* = switch (self.*) {
            .none => .{.one = byte},
            else => .too_many,
        };
    }
};

const ParamState = struct {
    const Self = @This();
    const Dispatcher = enum {
        csi,
        dcs,
    };

    intermediate: IntermediateCell = .none,
    params: [16]u14 = .{0} ** 16,
    param_count: usize = 1,

    fn csi_dispatch(self: *Self, parser: *Parser, byte: u8) void {
        const intermediate = switch (self.intermediate) {
            .none => null,
            .one => |c| c,
            .too_many => return,
        };
        parser.interpreter.csi_dispatch(self.params[0..self.param_count], intermediate, byte);
        parser.state = .ground;
    }

    fn dispatch(self: *Self, parser: *Parser, comptime dispatcher: Dispatcher, byte: u8) void {
        switch (dispatcher) {
            .csi => self.csi_dispatch(parser, byte),
            .dcs => {},
        }
    }

    fn do_param(self: *Self, parser: *Parser, comptime dispatcher: Dispatcher, ignore: State, intermediate_state: State, byte: u8) void {
        switch (byte) {
            0x3A, 0x3C...0x3F => parser.state = ignore,
            0x20...0x2F => {
                self.intermediate.add(byte);
                parser.state = intermediate_state;
            },
            0x30...0x39 => if (self.param_count <= 16) {
                const param = &self.params[self.param_count-1];
                param.* = 10*param.* + byte-'0';
            },
            0x3B => self.param_count += 1,
            0x40...0x7E => self.dispatch(parser, dispatcher, byte),
            else => {},
        }
    }

    fn do_intermediate(self: *Self, parser: *Parser, comptime dispatcher: Dispatcher, ignore: State, byte: u8) void {
        switch (byte) {
            0x30...0x3F => parser.state = ignore,
            0x20...0x2F => self.intermediate.add(byte),
            0x40...0x7E => self.dispatch(parser, dispatcher, byte),
            else => {},
        }
    }
};

const EscapeState = struct {
    first: u8,
    second: IntermediateCell = .none,
};

const State = union(enum) {
    ground: void,
    escape: void,
    escape_intermediate: EscapeState,
    csi_entry: void,
    csi_param: ParamState,
    csi_intermediate: ParamState,
    csi_ignore: void,
    dcs_entry: void,
    dcs_param: ParamState,
    dcs_intermediate: ParamState,
    dcs_passthrough: void,
    dcs_ignore: void,
    osc_string: void,
    sos_pm_apc_string: void,
};

/// The API to keep track of parsing state.
/// This struct stores an `Interpreter` to delegate actions to. As data is fed to the parser, methods on the `Interpreter` will be called corresponding to the sequences recognized.
pub const Parser = struct {
    const Self = @This();

    state: State,
    interpreter: Interpreter,

    pub fn accept(self: *Self, byte: u8) void {
        // state-agnostic transitions
        anywhere_transition: {
            self.state = switch (byte) {
                0x98, 0x9E, 0x9F => .sos_pm_apc_string,
                0x90 => .dcs_entry,
                0x1B => .escape,
                0x9D => .osc_string,
                0x9B => .csi_entry,
                0x9C => .ground,
                0x18, 0x1A, 0x80...0x8F, 0x91...0x97, 0x99, 0x9A => blk: {
                    self.interpreter.execute(byte);
                    break :blk .ground;
                },
                else => break :anywhere_transition,
            };
            return;
        }

        // C0/C1
        switch (byte) {
            0x00...0x19, 0x1C...0x1F => switch (self.state) {
                .dcs_param, .dcs_passthrough, .dcs_ignore, .dcs_intermediate, .dcs_entry, .sos_pm_apc_string, .osc_string => {},
                else => {
                    self.interpreter.execute(byte);
                    return;
                },
            },
            else => {},
        }

        switch (self.state) {
            .ground => switch (byte) {
                // TODO: UTF-8
                0x20...0x7F => self.interpreter.print(byte),
                else => {},
            },
            .escape => self.state = switch (byte) {
                0x5B => .csi_entry,
                0x5D => .osc_string,
                0x50 => .dcs_entry,
                0x20...0x2F => .{.escape_intermediate = .{.first = byte, .second = .none}},
                0x58, 0x5E, 0x5F => .sos_pm_apc_string,
                else => .escape,
            },
            .escape_intermediate => |*s| s.second.add(byte),
            .csi_entry => self.state = switch (byte) {
                0x3A => .csi_ignore,
                0x3C...0x3F => .{.csi_param = .{.intermediate = .{.one = byte}}},
                0x30...0x39 => .{.csi_param = .{.params = .{byte-'0'} ++ .{0} ** 15}},
                0x3B => .{.csi_param = .{.param_count = 2}},
                0x20...0x2F => .{.csi_intermediate = .{.intermediate = .{.one = byte}}},
                0x40...0x7E => blk: {
                    self.interpreter.csi_dispatch(&.{}, null, byte);
                    break :blk .ground;
                },
                else => .csi_entry,
            },
            .csi_param => |*s| s.do_param(self, .csi, .csi_ignore, .{.csi_intermediate = s.*}, byte),
            .csi_intermediate => |*s| s.do_intermediate(self, .csi, .csi_ignore, byte),
            .csi_ignore => switch (byte) {
                0x40...0x7E => self.state = .ground,
                else => {},
            },
            .dsc_entry => switch (byte)
        }
    }
};

test "force analysis" {
    var p: Parser = .{ .state = .ground, .interpreter = .{} };
    p.accept(0);
}
