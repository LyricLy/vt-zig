//! An implementation of Paul Williams' state machine for ANSI-compatible terminals.

/// A stack-allocated array type with limited capacity.
fn StackArrayList(comptime N: usize, comptime T: type) type {
    return struct {
        data: [N]T = .{0} ** N,
        len: usize = 0,

        const Self = @This();

        fn clear(self: *Self) void {
            self.len = 0;
        }

        fn push(self: *Self, x: T) void {
            if (self.len < N) self.data[self.len] = x;
            self.len += 1;
        }

        fn last(self: *Self) ?*T {
            return if (self.len > 0 and self.len <= N) &self.data[self.len-1] else null;
        }

        fn as_slice(self: *Self) []T {
            return self.data[0..self.len];
        }
    };
}

/// States for the parsing state machine.
const State = enum {
    ground,
    escape,
    escape_intermediate,
    csi_entry,
    csi_param,
    csi_intermediate,
    csi_ignore,
    dcs_entry,
    dcs_param,
    dcs_intermediate,
    dcs_passthrough,
    dcs_ignore,
    osc_string,
    sos_pm_apc_string,
};

/// CSI and DSC parameters are parsed identically, so this struct abstracts parameter passing, along with the `ParamStates` struct.
/// `Parser.entry`, `Parser.param`, `Parser.ignore`, and `Parser.intermediate` dispatch the `*_entry`, `*_param`, `*_ignore`, and `*_intermediate` states respectively for CSI and DSC sequences.
/// They receive this enum as a comptime parameter indicating which states to switch to and how to handle dispatching after the whole sequence is recognized.
const ParamKind = enum {
    csi,
    dcs,

    fn to_states(comptime self: @This()) ParamStates {
        return switch (self) {
            .csi => ParamStates{
                .entry = .csi_entry,
                .param = .csi_param,
                .intermediate = .csi_intermediate,
                .ignore = .csi_ignore,
            },
            .dcs => ParamStates{
                .entry = .dcs_entry,
                .param = .dcs_param,
                .intermediate = .dcs_intermediate,
                .ignore = .dcs_ignore,
            },
        };
    }
};

const ParamStates = struct {
    entry: State,
    param: State,
    intermediate: State,
    ignore: State,
};

/// The API to keep track of parsing state.
///
/// This struct stores an `Interpreter` (or another type with the same interface) to delegate actions to.
/// As data is fed to the parser, methods on the interpreter will be called corresponding to the sequences recognized.
pub fn Parser(comptime I: type) type {
    return struct {
        state: State,
        interpreter: I,
        intermediates: StackArrayList(2, u8),
        params: StackArrayList(16, u14),

        const Self = @This();

        pub fn init(interpreter: I) Self {
            return Self{
                .state = .ground,
                .interpreter = interpreter,
                .intermediates = StackArrayList(2, u8){},
                .params = StackArrayList(16, u14){},
            };
        }

        fn clear(self: *Self) void {
            self.intermediates.clear();
            self.params.clear();
        }

        fn csi_dispatch(self: *Self, byte: u8) void {
            const intermed = switch (self.intermediates.len) {
                0 => null,
                1 => self.intermediates.data[0],
                else => return,
            };
            self.interpreter.csi_dispatch(self.params.as_slice(), intermed, byte);
            self.state = .ground;
        }

        fn dcs_dispatch(_: *Self, _: u8) void {}

        fn dispatch(self: *Self, comptime kind: ParamKind, byte: u8) void {
            switch (kind) {
                .csi => self.csi_dispatch(byte),
                .dcs => self.dcs_dispatch(byte),
            }
        }

        fn entry(self: *Self, comptime kind: ParamKind, byte: u8) void {
            const states = kind.to_states();
            switch (byte) {
                0x3A => self.state = states.ignore,
                0x3C...0x3F => {
                    self.intermediates.push(byte);
                    self.state = states.param;
                },
                0x30...0x39 => {
                    self.params.push(byte-'0');
                    self.state = states.param;
                },
                0x3B => {
                    // the last element in the list of parameters is mutable, so this is pushing one definite 0 and putting a new value after it to be modified by later digits  
                    self.params.push(0);
                    self.params.push(0);
                    self.state = states.param;
                },
                0x20...0x2F => {
                    self.intermediates.push(byte);
                    self.state = states.intermediate;
                },
                0x40...0x7E => {
                    self.dispatch(kind, byte);
                    self.state = .ground;
                },
                else => {},
            }
        }

        fn param(self: *Self, comptime kind: ParamKind, byte: u8) void {
            const states = kind.to_states();
            switch (byte) {
                0x3A, 0x3C...0x3F => self.state = states.ignore,
                0x20...0x2F => {
                    self.intermediates.push(byte);
                    self.state = states.intermediate;
                },
                0x30...0x39 => if (self.params.len <= 16)
                    if (self.params.last()) |n| {
                        n.* = 10*n.* + byte-'0';
                    },
                0x3B => self.params.push(0),
                0x40...0x7E => self.dispatch(kind, byte),
                else => {},
            }
        }

        fn intermediate(self: *Self, comptime kind: ParamKind, byte: u8) void {
            const states = kind.to_states();
            switch (byte) {
                0x30...0x3F => self.state = states.ignore,
                0x20...0x2F => self.intermediates.push(byte),
                0x40...0x7E => self.dispatch(kind, byte),
                else => {},
            }
        }

        fn ignore(self: *Self, byte: u8) void {
            switch (byte) {
                0x40...0x7E => self.state = .ground,
                else => {},
            }
        }

        pub fn accept_byte(self: *Self, byte: u8) void {
            // state-agnostic transitions
            anywhere_transition: {
                self.state = switch (byte) {
                    0x98, 0x9E, 0x9F => .sos_pm_apc_string,
                    0x90 => .dcs_entry,
                    0x1B => blk: {
                        self.clear();
                        break :blk .escape;
                    },
                    0x9D => .osc_string,
                    0x9B => blk: {
                        self.clear();
                        break :blk .csi_entry;
                    },
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
                    0x20...0x2F => blk: {
                        self.intermediates.push(byte);
                        break :blk .escape_intermediate;
                    },
                    0x58, 0x5E, 0x5F => .sos_pm_apc_string,
                    else => .escape,
                },
                .escape_intermediate => self.intermediates.push(byte),
                .csi_entry => self.entry(.csi, byte),
                .csi_param => self.param(.csi, byte),
                .csi_intermediate => self.intermediate(.csi, byte),
                .csi_ignore => self.ignore(byte),
                .dcs_entry => self.entry(.dcs, byte),
                .dcs_param => self.param(.dcs, byte),
                .dcs_intermediate => self.intermediate(.dcs, byte),
                .dcs_ignore => self.ignore(byte),
                .dcs_passthrough => {},  // TODO: DCS hooking
                .osc_string => {},  // TODO: OSC strings?
                .sos_pm_apc_string => {},  // this one isn't a todo
            }
        }

        pub fn accept(self: *Self, bytes: []const u8) void {
            for (bytes) |byte| self.accept_byte(byte);
        }
    };
}

test {
    _ = @import("parser/test.zig");
}
