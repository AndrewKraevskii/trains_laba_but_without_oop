const std = @import("std");
const rl = @import("raylib");

const Vec = rl.Vector2;

// All unites are in [SI](https://en.wikipedia.org/wiki/International_System_of_Units).

const Segment = union(enum) {
    common: Common,
    force: Force,
    station: Station,

    const Common = struct {
        length: f32,
    };

    const Force = struct {
        length: f32,
        applied_force: f32,
    };

    const Station = struct {
        max_arriving_speed: f32,
    };

    pub fn length(self: @This()) f32 {
        return switch (self) {
            .common => |seg| seg.length,
            .force => |seg| seg.length,
            .station => 0,
        };
    }
};

const Route = struct {
    segments: std.ArrayList(Segment),
    route_end_speed_limit: f32,

    pub fn length(self: @This()) f32 {
        var sum: f32 = 0;
        for (self.segments.items) |segment|
            sum += segment.length();
        return sum;
    }
};

const Train = struct {
    position: f32 = 0.0,
    speed: f32 = 0.0,
    max_force: f32,
    mass: f32,
};

pub fn drawRoute(route: Route, rect: rl.Rectangle) void {
    const top_left = rl.Vector2.init(rect.x, rect.y);
    const length = route.length();
    const scale = rect.width / length;
    const segments = route.segments.items;

    const padding = 10;

    {
        var current_offset_x: f32 = 0;
        for (segments) |segment| {
            const next_offset_x = current_offset_x + segment.length();
            defer current_offset_x = next_offset_x;
            switch (segment) {
                .common, .force => {
                    const color: rl.Color = if (segment == .common) .white else .red;
                    const start = top_left.add(.{ .x = scale * current_offset_x, .y = 0 });
                    rl.drawLineEx(
                        start.add(.{ .x = padding, .y = 0 }),
                        start.add(.{ .x = scale * segment.length() - padding, .y = 0 }),
                        5,
                        color,
                    );
                },
                .station => {
                    rl.drawCircleV(
                        top_left.add(.{ .x = scale * current_offset_x, .y = 0 }),
                        padding,
                        .blue,
                    );
                },
            }
        }
    }

    {
        var current_offset_x: f32 = 0;
        for (segments[0 .. segments.len - 1], 0..) |segment, index| {
            const next_offset_x = current_offset_x + segment.length();
            defer current_offset_x = next_offset_x;
            if (segments[index] != .station and segments[index + 1] != .station) {
                rl.drawCircleLinesV(
                    top_left.add(.{ .x = scale * next_offset_x, .y = 0 }),
                    padding,
                    .white,
                );
            }
        }
    }
}

pub fn getTrainSegment(train: Train, route: Route) ?struct {
    segment: Segment,
    index: usize,
    position: f32,
} {
    const segments = route.segments.items;
    var current_offset_x: f32 = 0;
    std.debug.assert(current_offset_x >= 0);
    for (segments, 0..) |segment, index| {
        const next_offset_x = current_offset_x + segment.length();
        defer current_offset_x = next_offset_x;
        if (current_offset_x <= train.position and train.position < next_offset_x) return .{
            .segment = segment,
            .index = index,
            .position = train.position - current_offset_x,
        };
    }
    return null;
}
const RouteCompiltionErrors = error{
    ExceesiveSpeedAtTheStation,
    ExcessiveSpeedAtRouteEnd,
    SpeedIsNegative,
    TrainBrokenFromToMuchForce,
    ZeroSpeedOnCommonRails,
};

const MoveTrainResult = error{FinishedRouteSuccesfully} || RouteCompiltionErrors;
pub fn moveTrain(
    train: Train,
    route: Route,
    delta_t: f32,
) MoveTrainResult!Train {
    var mutable_train = train;
    const current_segment = getTrainSegment(mutable_train, route) orelse {
        return if (mutable_train.speed > route.route_end_speed_limit)
            error.ExcessiveSpeedAtRouteEnd
        else
            error.FinishedRouteSuccesfully;
    };
    if (train.speed <= 0 and current_segment.segment == .common) {
        return error.ZeroSpeedOnCommonRails;
    }

    var train_delta_pos: f32 = 0;
    switch (current_segment.segment) {
        .common => {
            train_delta_pos += delta_t * mutable_train.speed;
        },
        .force => |force| {
            if (mutable_train.max_force < force.applied_force) {
                return error.TrainBrokenFromToMuchForce;
            }
            const acceleration = force.applied_force / mutable_train.mass;

            train_delta_pos += delta_t * mutable_train.speed / 2;
            mutable_train.speed += acceleration * delta_t;
            train_delta_pos += delta_t * mutable_train.speed / 2;
        },
        .station => {
            // empty
        },
    }
    mutable_train.position += train_delta_pos;

    if (mutable_train.speed < 0) {
        return error.SpeedIsNegative;
    }

    if ((train_delta_pos + current_segment.position) > current_segment.segment.length()) {
        // train moved to next segment
        if (current_segment.index + 1 == route.segments.items.len) {
            // route finished
            if (mutable_train.speed > route.route_end_speed_limit)
                return error.ExcessiveSpeedAtRouteEnd;

            return error.FinishedRouteSuccesfully;
        } else {
            const next_segment = route.segments.items[current_segment.index + 1];
            if (next_segment == .station and train.speed > next_segment.station.max_arriving_speed) {
                return error.ExceesiveSpeedAtTheStation;
            }
        }
    }

    return mutable_train;
}

pub fn generateRandomRoute(alloc: std.mem.Allocator, random: std.Random, number_of_segments: usize) !Route {
    var route = Route{ .segments = .init(alloc), .route_end_speed_limit = random.float(f32) * 10 + 30 };
    errdefer route.segments.deinit();

    var prev: std.meta.Tag(Segment) = .force;
    try route.segments.append(.{ .force = .{
        .length = random.float(f32) * 4000 + 1000,
        .applied_force = random.float(f32) * 800000 - 300000,
    } });
    for (1..number_of_segments) |index| {
        var segment_type = random.enumValue(std.meta.Tag(Segment));
        defer prev = segment_type;
        while (.station == segment_type and (.station == prev or index + 1 == number_of_segments)) {
            segment_type = random.enumValue(std.meta.Tag(Segment));
        }

        const segment: Segment = switch (segment_type) {
            .common => .{ .common = .{
                .length = random.float(f32) * 4000 + 1000,
            } },
            .station => .{ .station = .{ .max_arriving_speed = random.float(f32) * 30 + 10 } },
            .force => .{ .force = .{
                .length = random.float(f32) * 1000 + 100,
                .applied_force = random.float(f32) * 800000 - 300000,
            } },
        };
        try route.segments.append(segment);
    }

    return route;
}

const ErrorMessages = struct {
    position: Vec,
    messages: std.BoundedArray(Message, 50),
    font_size: i32,

    const Message = struct {
        string: [:0]const u8,
        color: rl.Color = .red,
        current_position: f32 = 0,
        time_to_leave: f32 = 10,
    };

    pub fn addMessage(self: *ErrorMessages, message: Message) void {
        if (self.messages.capacity() == self.messages.len) {
            _ = self.messages.orderedRemove(0);
        }

        self.messages.appendAssumeCapacity(message);
    }

    pub fn update(self: *@This(), delta_time: f32) void {
        var index: usize = 0;
        while (index < self.messages.len) {
            var message = self.messages.get(index);
            message.time_to_leave -= delta_time;
            if (message.time_to_leave <= 0) {
                _ = self.messages.orderedRemove(index);
                continue;
            }
            const correct_positon = @as(f32, @floatFromInt(index)) *
                @as(f32, @floatFromInt(self.font_size));
            message.current_position = expDecay(message.current_position, correct_positon, 3, delta_time);

            self.messages.set(index, message);

            index += 1;
        }
    }

    pub fn draw(self: @This()) void {
        for (self.messages.slice()) |message| {
            rl.drawText(
                message.string,
                @intFromFloat(self.position.x),
                @intFromFloat(self.position.y + message.current_position),
                self.font_size,
                message.color,
            );
        }
    }
};

fn expDecay(a: anytype, b: @TypeOf(a), lambda: @TypeOf(a), dt: @TypeOf(a)) @TypeOf(a) {
    return std.math.lerp(a, b, 1 - @exp(-lambda * dt));
}

pub fn mainUi() !void {
    var buf: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const width = 1000;
    const height = 1000;

    const default_train = Train{ .mass = 200 * 1000, .max_force = 1000 * 1000 };

    var train = default_train;
    var result = try generateNiceRoute(alloc, train, 0);
    var route = result.route;
    var seed = result.seed + 1;

    var messages = ErrorMessages{
        .position = .zero(),
        .messages = .{},
        .font_size = 30,
    };

    std.log.debug("{any}", .{route});
    rl.initWindow(width, height, "it's training time");
    rl.setTargetFPS(60);

    const time_scale = 600;
    const time_step = 1.0 / 60.0;
    var ui_time_step: f32 = 0;
    while (!rl.windowShouldClose()) {
        std.log.debug("{}", .{fba.end_index});
        {
            if (rl.isMouseButtonPressed(.mouse_button_left)) {
                route.segments.deinit();
                train = default_train;
                result = try generateNiceRoute(alloc, train, seed);
                seed = result.seed + 1;
                route = result.route;
            }
            ui_time_step += rl.getFrameTime() * time_scale;
            while (ui_time_step > time_step) : (ui_time_step -= time_step) {
                if (moveTrain(train, route, 1.0 / 60.0)) |new_train| {
                    train = new_train;
                } else |err| {
                    const color: rl.Color = switch (err) {
                        error.FinishedRouteSuccesfully => .green,
                        else => .red,
                    };
                    messages.addMessage(.{
                        .string = @errorName(err),
                        .color = color,
                    });
                    route.segments.deinit();
                    train = default_train;
                    const res = try generateNiceRoute(alloc, train, seed);
                    seed = res.seed + 1;
                    route = res.route;
                }
            }

            messages.update(rl.getFrameTime());
        }

        {
            rl.beginDrawing();
            rl.clearBackground(rl.Color.black);

            const scale = width / route.length();
            drawRoute(route, .{ .x = 0, .y = height / 2.0, .width = width, .height = height });
            { // draw train
                rl.drawRectanglePro(.{
                    .x = train.position * scale,
                    .y = height / 2.0,
                    .width = 10,
                    .height = 10,
                }, .{ .x = 5, .y = 5 }, 0, .white);
            }
            messages.draw();

            rl.endDrawing();
        }
    }

    rl.closeWindow();
}

pub fn generateNiceRoute(
    alloc: std.mem.Allocator,
    train: Train,
    starting_seed: u64,
) !struct {
    route: Route,
    seed: u64,
    /// time it takes for given train to pass route
    time: f32,
} {
    var random_impl = std.Random.DefaultPrng.init(0);
    var random = random_impl.random();

    var route = try generateRandomRoute(alloc, random, 10);

    var seed: u64 = starting_seed;
    while (true) {
        const res = tryRoute(train, route, .{}) catch {
            seed += 1;
            random_impl = std.Random.DefaultPrng.init(seed);
            random = random_impl.random();

            route.segments.deinit();
            route = try generateRandomRoute(alloc, random, 10);
            continue;
        };
        return .{ .route = route, .seed = seed, .time = res.time_to_finish_seconds };
    }
}

const TryRouteError = RouteCompiltionErrors || error{Timeout};

pub fn tryRoute(
    starting_train: Train,
    route: Route,
    config: struct {
        max_time_seconds: f32 = 10 * 60 * 60, // 10h
        delta_t: f32 = 1.0 / 60.0,
    },
) TryRouteError!struct { time_to_finish_seconds: f32 } {
    var train = starting_train;

    var time_passed: f32 = 0;
    while (true) {
        time_passed += config.delta_t;
        if (time_passed > config.max_time_seconds) return error.Timeout;
        if (moveTrain(train, route, config.delta_t)) |new_train| {
            train = new_train;
        } else |err| {
            switch (err) {
                error.FinishedRouteSuccesfully => {
                    return .{ .time_to_finish_seconds = time_passed };
                },
                else => |other| {
                    return other;
                },
            }
        }
    }
}

pub fn mainHeadless() !void {
    var seed: u64 = 0;
    for (0..100) |_| {
        const result = try generateNiceRoute(
            .{ .mass = 200 * 1000, .max_force = 1000 * 1000 },
            seed,
        );
        // std.log.err("found succesfull route with seed: {d} in {}", .{ seed, std.fmt.fmtDuration(@intFromFloat(res.time_to_finish_seconds * std.time.ns_per_s)) });
        std.debug.print("found succesfull route with seed: {d} in {}\n", .{ result.seed, std.fmt.fmtDuration(@intFromFloat(result.time * std.time.ns_per_s)) });
        seed = result.seed + 1;
    }
}

pub fn main() !void {
    try mainUi();
}
