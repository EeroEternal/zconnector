const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = switch (optimize) {
        .ReleaseFast, .ReleaseSmall => true,
        else => false,
    };

    const zconnector_module = b.addModule("zconnector", .{
        .root_source_file = b.path("src/zconnector.zig"),
    });

    const library = b.addLibrary(.{
        .name = "zconnector",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zconnector.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        }),
    });
    b.installArtifact(library);

    const demo = b.addExecutable(.{
        .name = "zconnector-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        }),
    });
    demo.root_module.addImport("zconnector", zconnector_module);
    b.installArtifact(demo);

    const run_demo = b.addRunArtifact(demo);
    if (b.args) |args| {
        run_demo.addArgs(args);
    }

    const run_step = b.step("run", "Run the demo entry point");
    run_step.dependOn(&run_demo.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zconnector.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("zconnector", zconnector_module);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    const example_files = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "simple_chat", .path = "examples/simple_chat.zig" },
        .{ .name = "streaming", .path = "examples/streaming.zig" },
        .{ .name = "reasoning", .path = "examples/reasoning.zig" },
        .{ .name = "file_upload", .path = "examples/file_upload.zig" },
        .{ .name = "multi_provider", .path = "examples/multi_provider.zig" },
        .{ .name = "tools", .path = "examples/tools.zig" },
        .{ .name = "async_evented", .path = "examples/async_evented.zig" },
    };

    inline for (example_files) |example| {
        const executable = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
                .strip = strip,
            }),
        });
        executable.root_module.addImport("zconnector", zconnector_module);
        b.installArtifact(executable);

        const run_example = b.addRunArtifact(executable);
        if (b.args) |args| {
            run_example.addArgs(args);
        }

        const example_step = b.step(example.name, b.fmt("Run the {s} example", .{example.name}));
        example_step.dependOn(&run_example.step);
    }
}
