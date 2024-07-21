const std = @import("std");

pub const font_data: []const u8 = blk: {
    var data: []const u8 = &.{};
    for (font_set_glyphs) |glyph| {
        data = data ++ &glyphToBytes(glyph);
    }
    break :blk data;
};

test "font_data" {
    try std.testing.expectEqual(0b11110000, font_data[0]);
    try std.testing.expectEqualSlices(u8, &.{ 0b11110000, 0b10010000, 0b10010000, 0b10010000, 0b11110000 }, font_data[0..5]);
}

const font_set_glyphs: [16][]const u8 = .{
    \\####
    \\#  #
    \\#  #
    \\#  #
    \\####
    ,
    \\  # 
    \\ ## 
    \\  # 
    \\  # 
    \\ ###
    ,
    \\####
    \\   #
    \\####
    \\#   
    \\####
    ,
    \\####
    \\   #
    \\####
    \\   #
    \\####
    ,
    \\#  #
    \\#  #
    \\####
    \\   #
    \\   #
    ,
    \\####
    \\#   
    \\####
    \\   #
    \\####
    ,
    \\####
    \\#   
    \\####
    \\#  #
    \\####
    ,
    \\####
    \\   #
    \\  # 
    \\ #  
    \\ #  
    ,
    \\####
    \\#  #
    \\####
    \\#  #
    \\####
    ,
    \\####
    \\#  #
    \\####
    \\   #
    \\####
    ,
    \\ ## 
    \\#  #
    \\####
    \\#  #
    \\#  #
    ,
    \\### 
    \\#  #
    \\### 
    \\#  #
    \\### 
    ,
    \\####
    \\#   
    \\#   
    \\#   
    \\####
    ,
    \\### 
    \\#  #
    \\#  #
    \\#  #
    \\### 
    ,
    \\####
    \\#   
    \\### 
    \\#   
    \\####
    ,
    \\####
    \\#   
    \\### 
    \\#   
    \\#   
};

fn rowToByte(comptime row: *const [4]u8) u8 {
    var byte: u8 = 0;
    for (row, 0..) |c, i| {
        const bit_index: u3 = @intCast(7 - i);
        if (c == '#') {
            byte |= (1 << bit_index);
        }
    }
    return byte;
}

fn glyphToBytes(comptime glyph: []const u8) [5]u8 {
    return .{
        rowToByte(glyph[0..4]),
        rowToByte(glyph[5..9]),
        rowToByte(glyph[10..14]),
        rowToByte(glyph[15..19]),
        rowToByte(glyph[20..24]),
    };
}
