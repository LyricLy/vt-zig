/// A colour. Either the default colour of the background/foreground, one of the 16 primary "named" colours, one of the 256 indexed colours, or a 24-bit RGB triple.
pub const Colour = union(enum) {
    default: void,
    primary: u4,
    indexed: u8,
    trueclr: u24,
};

/// The style data each cell on the screen can hold.
pub const Style = struct {
    foreground: Colour,
    background: Colour,
    // TODO: this should have more fields
};
