/// A colour. Either one of the 16 primary "named" colours, one of the 256 indexed colours, or a 24-bit RGB triple.
const Colour = union(enum) {
    primary: u4,
    indexed: u8,
    trueclr: u24,
};

/// The style data each cell on the screen can hold.
const Style = struct {
    foreground: Colour,
    background: Colour,
};
