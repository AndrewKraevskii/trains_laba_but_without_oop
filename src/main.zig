const std = @import("std");
const rl = @import("raylib");

const Vec = rl.Vector2;
const wagon_length = 100;
const wagon_width = 20;
const rails_width = wagon_width;
const max_waypoints = 1000;

const sleepers_density = 0.1;

pub fn drawTrain(position: Vec, rotation: f32) void {
    rl.drawRectanglePro(rectangleFromSizeAndPos(position, .{ .x = wagon_length, .y = wagon_width }), .{ .x = wagon_length / 2, .y = wagon_width / 2 }, -rotation * 180 / std.math.pi, .white);
}

pub fn getTrainInfo(points: []const Vec, t: f32) ?struct {
    section_index: usize,
    position: rl.Vector2,
    direction: rl.Vector2,
} {
    std.debug.assert(0 <= t and t <= 1);
    if (points.len < 2) return null;

    const total_distance = distance: {
        var total_distance: f32 = 0;
        for (points[0 .. points.len - 1], points[1..points.len]) |from, to| {
            total_distance += from.distance(to);
        }
        break :distance total_distance;
    };
    var distance: f32 = 0;

    const segment_index, const segment_t = segment_t: for (points[0 .. points.len - 1], points[1..points.len], 0..) |from, to, index| {
        const new_distance = distance + from.distance(to);
        if (distance <= t * total_distance and new_distance >= t * total_distance) {
            break :segment_t .{ index, (t * total_distance - distance) / (new_distance - distance) };
        }
        distance = new_distance;
    } else return null;

    std.log.debug("index: {d}", .{segment_index});
    const position =
        rl.getSplinePointCatmullRom(
        points[segment_index -| 1],
        points[segment_index],
        points[segment_index + 1],
        points[@min(segment_index + 2, points.len - 1)],
        segment_t,
    );
    const prev_pos =
        rl.getSplinePointCatmullRom(
        points[segment_index -| 1],
        points[segment_index],
        points[segment_index + 1],
        points[@min(segment_index + 2, points.len - 1)],
        @max(segment_t - 0.1, 0),
    );
    const next_pos =
        rl.getSplinePointCatmullRom(
        points[segment_index -| 1],
        points[segment_index],
        points[segment_index + 1],
        points[@min(segment_index + 2, points.len - 1)],
        @min(segment_t + 0.1, 1),
    );

    return .{
        .section_index = segment_index,
        .position = position,
        .direction = next_pos.subtract(prev_pos).normalize(),
    };
}

pub fn rectangleFromSizeAndPos(position: Vec, size: Vec) rl.Rectangle {
    return .{
        .x = position.x,
        .y = position.y,
        .width = size.x,
        .height = size.y,
    };
}

const Rails = union(enum) {
    common,
    force: f32,
    // station, // Пока хз чё это

    pub fn theme(rail: Rails) struct {
        colors: []const rl.Color,
        widths: []f32,
    } {
        switch (rail) {
            .common, .force => .{ .widths = &.{ rails_width, rails_width - 5 }, .colors = &.{ .brown, .black } },
        }
        return;
    }
};

const Train = struct {
    position: f32,
    speed: f32,
    max_force: f32,
    mass: f32,

    pub fn move(self: *Train, rails: Rails, time: f32) enum {
        moving,
        broke,
    } {
        switch (rails) {
            .common => self.position = self.speed * time,

            .force => |f| {
                if (@abs(f) > @abs(self.max_force)) {
                    return .broke;
                }
                const delta_speed = (f / self.mass) * time;
                const half_delta_speed = delta_speed / 2;

                self.speed += half_delta_speed;
                self.position = self.speed * time;
                self.speed += half_delta_speed;
            },
            // .station => {
            //     @panic("Not implemented");
            // },
        }

        return .moving;
    }
};

const Railroad = struct {
    positions: std.ArrayList(Vec),
    type: std.ArrayList(Rails),
    length: f32 = 1000,

    pub fn init(alloc: std.mem.Allocator) Railroad {
        return .{
            .positions = .init(alloc),
            .type = .init(alloc),
        };
    }

    pub fn drawRails(railroad: Railroad, colors: struct { rail: rl.Color, sleeper: rl.Color }) void {
        const pos = railroad.positions.items;
        if (railroad.type.items.len < 4) return;
        const theme = railroad.type.items[0];
        _ = theme; // autofix
        for (0..railroad.positions.items.len - 4) |i| {
            _ = i; // autofix
            inline for (.{ rails_width, rails_width - 5 }, .{ colors.rail, rl.Color.black }) |thickness, color| {
                rl.drawSplineCatmullRom(pos, thickness, color);
                if (pos.len >= 3) {
                    {
                        const points = pos[0..1] ++ pos[0..3];
                        rl.drawSplineCatmullRom(points, thickness, color);
                    }
                    {
                        const points = pos[pos.len - 3 ..][0..3] ++ pos[pos.len - 1 ..][0..1];
                        rl.drawSplineCatmullRom(points, thickness, color);
                    }
                }
            }
        }
        if (pos.len >= 4) {
            var maybe_prev_sleeper_pos: ?Vec = null;
            for (0..pos.len - 1) |i| {
                const start_pos =
                    rl.getSplinePointCatmullRom(
                    pos[i -| 1],
                    pos[i],
                    pos[i + 1],
                    pos[@min(i + 2, pos.len - 1)],
                    0,
                );

                const end_pos =
                    rl.getSplinePointCatmullRom(
                    pos[i -| 1],
                    pos[i],
                    pos[i + 1],
                    pos[@min(i + 2, pos.len - 1)],
                    1,
                );

                const distance = end_pos.distance(start_pos);
                const times = distance * sleepers_density;

                for (0..@intFromFloat(times)) |t| {
                    const sleeper_pos =
                        rl.getSplinePointCatmullRom(
                        pos[i -| 1],
                        pos[i],
                        pos[i + 1],
                        pos[@min(i + 2, pos.len - 1)],
                        @as(f32, @floatFromInt(t)) / times,
                    );
                    defer maybe_prev_sleeper_pos = sleeper_pos;
                    const prev_sleeper_pos = maybe_prev_sleeper_pos orelse continue;

                    const perpendicular = prev_sleeper_pos.subtract(sleeper_pos).normalize().rotate(std.math.tau / 4.0).scale(rails_width / 2.0);
                    rl.drawLineV(prev_sleeper_pos.add(perpendicular), prev_sleeper_pos.subtract(perpendicular), colors.sleeper);
                }
            }
        }
    }
};

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var buf: [100000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    var cursor_force_value: f32 = 0;

    rl.initWindow(1000, 1000, "it's training time");

    var railroad: Railroad = .init(alloc);

    var train = Train{
        .position = 0,
        .speed = 0,
        .max_force = 100,
        .mass = 100,
    };

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();

        cursor_force_value += rl.getMouseWheelMove();

        rl.clearBackground(rl.Color.black);
        if (rl.isMouseButtonPressed(.mouse_button_left) or rl.isMouseButtonPressed(.mouse_button_right)) {
            try railroad.positions.append(rl.getMousePosition());
            if (railroad.positions.items.len != 1) {
                try railroad.type.append(if (rl.isMouseButtonPressed(.mouse_button_left)) .common else .{ .force = cursor_force_value });
            }
        }

        railroad.drawRails(.{
            .rail = .brown,
            .sleeper = .gray,
        });

        if (getTrainInfo(railroad.positions.items, train.position / railroad.length)) |info| {
            if (train.move(railroad.type.items[info.section_index], rl.getFrameTime()) == .broke) return;

            std.log.debug("angle: {d}", .{info.direction.angle(.init(0, 1))});
            drawTrain(info.position, info.direction.angle(.init(1, 0)));
            std.log.debug("Position is {any}", .{info.position});
            const text = try std.fmt.allocPrintZ(alloc, "curent force value: {any}", .{cursor_force_value});
            defer alloc.free(text);
            rl.drawText(text, 40, 40, 20, .white);
        } else {
            std.log.debug("Position not found", .{});
        }
        rl.drawFPS(10, 10);

        rl.endDrawing();
    }

    rl.closeWindow();
}
