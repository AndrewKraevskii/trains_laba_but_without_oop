const std = @import("std");
const rl = @import("raylib");
const rgui = @import("raygui");

const Vec = rl.Vector2;
const station_width = 10;

// All unites are in [SI](https://en.wikipedia.org/wiki/International_System_of_Units).

const Segment = union(enum) {
    common: Common,
    force: Force,
    station: Station,

    const Common = struct {
        length: f32 = 1_000,
    };

    const Force = struct {
        length: f32 = 1_000,
        applied_force: f32 = 100_000,
    };

    const Station = struct {
        max_arriving_speed: f32 = 20,
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

    const RouteCompiltionErrors = error{
        ExceesiveSpeedAtTheStation,
        ExcessiveSpeedAtRouteEnd,
        SpeedIsNegative,
        TrainBrokenFromToMuchForce,
        ZeroSpeedOnCommonRails,
    };

    const MoveResult = error{FinishedRouteSuccessfully} || RouteCompiltionErrors;

    pub fn move(
        train: Train,
        route: Route,
        delta_t: f32,
    ) MoveResult!Train {
        var mutable_train = train;
        const maybe_segment = getTrainSegment(mutable_train, route);
        const current_segment = maybe_segment orelse {
            return if (mutable_train.speed > route.route_end_speed_limit)
                error.ExcessiveSpeedAtRouteEnd
            else
                error.FinishedRouteSuccessfully;
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

                return error.FinishedRouteSuccessfully;
            } else {
                const next_segment = route.segments.items[current_segment.index + 1];
                if (next_segment == .station and train.speed > next_segment.station.max_arriving_speed) {
                    return error.ExceesiveSpeedAtTheStation;
                }
            }
        }

        return mutable_train;
    }
};

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
        if (train.position < next_offset_x) return .{
            .segment = segment,
            .index = index,
            .position = train.position - current_offset_x,
        };
    }
    return null;
}

pub fn drawRoute(route: Route, rect: rl.Rectangle, highlighting: ?struct { index: usize, type: enum { hovered, selected } }) void {
    const highlighting_color: ?rl.Color = if (highlighting) |h| if (h.type == .hovered) .white else .yellow else null;
    const middle_left = rl.Vector2.init(rect.x, rect.y + rect.height / 2);
    const length = route.length();
    const scale = rect.width / length;
    const segments = route.segments.items;

    const padding = station_width;

    {
        var current_offset_x: f32 = 0;
        for (segments, 0..) |segment, index| {
            const is_selected = highlighting != null and highlighting.?.index == index;

            const next_offset_x = current_offset_x + segment.length();
            defer current_offset_x = next_offset_x;
            switch (segment) {
                .common, .force => {
                    const start = middle_left.add(.{ .x = scale * current_offset_x, .y = 0 });

                    if (is_selected) {
                        if (highlighting_color) |color| {
                            rl.drawLineEx(
                                start.add(.{ .x = padding, .y = 0 }),
                                start.add(.{ .x = scale * segment.length() - padding, .y = 0 }),
                                9,
                                color,
                            );
                        }
                    }
                    rl.drawLineEx(
                        start.add(.{ .x = padding, .y = 0 }),
                        start.add(.{ .x = scale * segment.length() - padding, .y = 0 }),
                        5,
                        if (segment == .common) .white else .red,
                    );
                },
                .station => {
                    const color: rl.Color = if (is_selected) .yellow else .blue;
                    rl.drawCircleV(
                        middle_left.add(.{ .x = scale * current_offset_x, .y = 0 }),
                        padding,
                        color,
                    );
                },
            }
        }
    }

    {
        var current_offset_x: f32 = 0;
        rl.drawCircleLinesV(
            middle_left.add(.{ .x = 0, .y = 0 }),
            padding,
            .white,
        );
        for (segments[0 .. segments.len - 1], 0..) |segment, index| {
            const next_offset_x = current_offset_x + segment.length();
            defer current_offset_x = next_offset_x;
            if (segments[index] != .station and segments[index + 1] != .station) {
                rl.drawCircleLinesV(
                    middle_left.add(.{ .x = scale * next_offset_x, .y = 0 }),
                    padding,
                    .white,
                );
            }
        }
        rl.drawCircleLinesV(
            middle_left.add(.{ .x = scale * length, .y = 0 }),
            padding,
            .white,
        );
    }
}

pub fn getRouteSegmentIndexByPosition(
    route: Route,
    fraction_of_route: f32,
    stations_padding: f32,
) ?usize {
    std.debug.assert(0 <= fraction_of_route and fraction_of_route <= 1);
    const total_route_length = route.length();
    const scaled_padding = stations_padding;

    const segments = route.segments.items;
    var current_offset_x: f32 = 0;
    for (segments, 0..) |segment, index| {
        const next_offset_x = current_offset_x + segment.length() / total_route_length;
        defer current_offset_x = next_offset_x;
        const padding = if (segment == .station) -scaled_padding else scaled_padding;
        if (current_offset_x + padding <= fraction_of_route and fraction_of_route < next_offset_x - padding) return index;
    }
    return null;
}

pub fn generateRandomRoute(alloc: std.mem.Allocator, random: std.Random, number_of_segments: usize) !Route {
    var route = Route{ .segments = .init(alloc), .route_end_speed_limit = random.float(f32) * 10 + 30 };
    errdefer route.segments.deinit();

    try route.segments.ensureTotalCapacityPrecise(number_of_segments);

    var prev: std.meta.Tag(Segment) = .force;
    route.segments.appendAssumeCapacity(.{ .force = .{
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
        route.segments.appendAssumeCapacity(segment);
    }

    return route;
}

const MessageDrawer = struct {
    position: Vec,
    messages: std.BoundedArray(Message, 50),
    font_size: i32,

    const Message = struct {
        string: [:0]const u8,
        color: rl.Color = .red,
        current_position: f32 = 0,
        time_to_live: f32 = 10,
    };

    pub fn addMessage(self: *MessageDrawer, message: Message) void {
        if (self.messages.capacity() == self.messages.len) {
            _ = self.messages.orderedRemove(0);
        }

        self.messages.appendAssumeCapacity(message);
    }

    pub fn update(self: *@This(), delta_time: f32) void {
        var index: usize = 0;
        while (index < self.messages.len) {
            var message = self.messages.get(index);
            message.time_to_live -= delta_time;
            if (message.time_to_live <= 0) {
                _ = self.messages.orderedRemove(index);
                continue;
            }
            const correct_position = @as(f32, @floatFromInt(index)) *
                @as(f32, @floatFromInt(self.font_size));
            message.current_position = expDecay(message.current_position, correct_position, 3, delta_time);

            self.messages.set(index, message);

            index += 1;
        }
    }

    pub fn draw(self: @This()) void {
        for (self.messages.slice()) |message| {
            const fade_time = 0.4;
            rl.drawText(
                message.string,
                @intFromFloat(self.position.x),
                @intFromFloat(self.position.y + message.current_position),
                self.font_size,
                message.color.fade(@min(message.time_to_live, fade_time) / fade_time),
            );
        }
    }
};

fn expDecay(a: anytype, b: @TypeOf(a), lambda: @TypeOf(a), dt: @TypeOf(a)) @TypeOf(a) {
    return std.math.lerp(a, b, 1 - @exp(-lambda * dt));
}

pub fn generateNiceRoute(
    alloc: std.mem.Allocator,
    train: Train,
    number_of_nodes: usize,
    starting_seed: u64,
) !struct {
    route: Route,
    seed: u64,
    /// time it takes for given train to pass route
    time: f32,
} {
    var random_impl = std.Random.DefaultPrng.init(0);
    var random = random_impl.random();

    var route = try generateRandomRoute(alloc, random, number_of_nodes);

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

const TryRouteError = Train.RouteCompiltionErrors || error{Timeout};

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
        if (train.move(route, config.delta_t)) |new_train| {
            train = new_train;
        } else |err| {
            switch (err) {
                error.FinishedRouteSuccessfully => {
                    return .{ .time_to_finish_seconds = time_passed };
                },
                else => |other| {
                    return other;
                },
            }
        }
    }
}

pub fn runUi() !void {
    var buf: [10000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const width = 1000;
    const height = 1000;

    const default_train = Train{ .mass = 200 * 1000, .max_force = 1000 * 1000 };

    var train = default_train;
    const number_of_nodes: i32 = 10;
    const result = try generateNiceRoute(alloc, train, number_of_nodes, 0);
    var route = result.route;
    defer route.segments.deinit();
    var seed = result.seed + 1;

    var messages = MessageDrawer{
        .position = .zero(),
        .messages = .{},
        .font_size = 30,
    };

    rl.initWindow(width, height, "it's training time");
    rl.setTargetFPS(60);

    var is_paused: bool = false;
    var maybe_selected_index: ?usize = null;

    var time_scale: f32 = 3;
    const time_step = 1.0 / 60.0;
    var ui_time_step: f32 = 0;
    const widget_width = 100;

    var drop_down_edit_mode = false;
    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(.key_space)) {
            is_paused = !is_paused;
        }

        if (!is_paused) {
            ui_time_step += rl.getFrameTime() * @exp(time_scale);
            while (ui_time_step > time_step) : (ui_time_step -= time_step) {
                if (train.move(route, 1.0 / 60.0)) |new_train| {
                    train = new_train;
                } else |err| {
                    const color: rl.Color = switch (err) {
                        error.FinishedRouteSuccessfully => .green,
                        else => .red,
                    };
                    messages.addMessage(.{
                        .string = @errorName(err),
                        .color = color,
                    });
                    maybe_selected_index = null;
                    route.segments.deinit();
                    train = default_train;
                    const res = try generateNiceRoute(alloc, train, number_of_nodes, seed);
                    seed = res.seed + 1;
                    route = res.route;
                }
            }
        }
        messages.update(rl.getFrameTime());

        {
            rl.beginDrawing();
            rl.clearBackground(rl.Color.black);

            const route_rect = rl.Rectangle{ .x = 0, .y = height / 2.0, .width = @floatFromInt(rl.getScreenWidth()), .height = 30 };
            const maybe_hovered_index = if (rl.checkCollisionPointRec(rl.getMousePosition(), route_rect)) selected_index: {
                const mouse_x = rl.getMousePosition().x;
                const fraction = (mouse_x - route_rect.x) / route_rect.width;
                break :selected_index getRouteSegmentIndexByPosition(
                    route,
                    fraction,
                    station_width / route_rect.width,
                );
            } else null;

            const maybe_index = maybe_selected_index orelse maybe_hovered_index;

            drawRoute(route, route_rect, if (maybe_index) |index| .{
                .index = index,
                .type = if (maybe_selected_index != null) .selected else .hovered,
            } else null);

            var rect = rl.Rectangle{ .x = @floatFromInt(rl.getScreenWidth() - widget_width - 100), .y = 10, .height = 20, .width = widget_width };

            if (rgui.guiButton(rect, "RELOAD") == 1) {
                messages.addMessage(.{
                    .string = "Reloaded",
                    .color = .yellow,
                });
                maybe_selected_index = null;
                route.segments.deinit();
                train = default_train;
                const res = try generateNiceRoute(alloc, train, number_of_nodes, seed);
                seed = res.seed + 1;
                route = res.route;
            }
            rect.y += rect.height * 2;

            if (rgui.guiButton(rect, if (is_paused) "CONTINUE" else "PAUSE") == 1) {
                is_paused = !is_paused;
                messages.addMessage(.{
                    .string = if (is_paused) "Paused" else "Unpaused",
                    .color = .yellow,
                });
            }
            rect.y += rect.height * 2;

            _ = rgui.guiSlider(
                rect,
                "slow " ++ std.fmt.comptimePrint("{}", .{comptime std.fmt.fmtDuration(@intFromFloat(@exp(-2.0) * std.time.ns_per_s))}),
                "fast " ++ std.fmt.comptimePrint("{}", .{comptime std.fmt.fmtDuration(@intFromFloat(@exp(8.0) * std.time.ns_per_s))}),
                &time_scale,
                -2,
                8,
            );
            rect.y += rect.height * 2;
            if (maybe_index) |selected_index| { // draw segment info
                if (rl.isMouseButtonPressed(.mouse_button_left)) {
                    if (maybe_hovered_index) |hovered_index|
                        maybe_selected_index = hovered_index;
                }
                const segment: *Segment = &route.segments.items[selected_index];

                { // change node type
                    var active: i32 = @intFromEnum(segment.*);

                    if (rgui.guiDropdownBox(
                        rect,
                        "common;force;station",
                        &active,
                        drop_down_edit_mode,
                    ) == 1) {
                        drop_down_edit_mode = !drop_down_edit_mode;
                    }
                    if (active != @intFromEnum(segment.*)) {
                        switch (@as(std.meta.Tag(Segment), @enumFromInt(active))) {
                            .common => {
                                segment.* = if (segment.* == .force)
                                    .{ .common = .{ .length = segment.force.length } }
                                else
                                    .{ .common = .{} };
                            },
                            .force => {
                                segment.* = if (segment.* == .common)
                                    .{ .force = .{ .length = segment.common.length } }
                                else
                                    .{ .force = .{} };
                            },
                            .station => {
                                segment.* = .{ .station = .{} };
                            },
                        }
                    }

                    rect.y += rect.height * @as(f32, if (drop_down_edit_mode) 5 else 2);
                    switch (segment.*) {
                        .common => {
                            _ = rgui.guiSlider(
                                rect,
                                "length 0m",
                                "10km",
                                &segment.common.length,
                                0,
                                10000,
                            );
                            rect.y += rect.height;
                        },
                        .force => {
                            _ = rgui.guiSlider(
                                rect,
                                "length 0m",
                                "100km",
                                &segment.force.length,
                                0,
                                100000,
                            );
                            rect.y += rect.height;
                            _ = rgui.guiSlider(
                                rect,
                                "applied force 0N",
                                "1MN",
                                &segment.force.applied_force,
                                -1000000,
                                1000000,
                            );
                        },
                        .station => {
                            _ = rgui.guiSlider(
                                rect,
                                "max speed 0m/s",
                                "100m/s",
                                &segment.station.max_arriving_speed,
                                0,
                                100,
                            );
                            rect.y += rect.height;
                        },
                    }
                }
            }

            { // draw train
                const scale = width / route.length();
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

pub fn main() !void {
    if (@import("config").benchmark) {
        try benchmark();
    } else {
        try runUi();
    }
}

pub fn benchmark() !void {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var seed: u64 = 0;
    const train = Train{ .max_force = 1000_000, .mass = 600000 };
    for (0..100) |_| {
        const res = try generateNiceRoute(fba.allocator(), train, 10, seed);
        seed = res.seed + 1;
        fba.reset();
    }
}
