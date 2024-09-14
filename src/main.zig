const std = @import("std");
const rl = @import("raylib");

pub fn main() void {
    rl.initWindow(1000, 1000, "it's training time");

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();

        var bytes: [@sizeOf(rl.Color)]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        rl.clearBackground(@bitCast(bytes));
        rl.endDrawing();
    }

    rl.closeWindow();
}
