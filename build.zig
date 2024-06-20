const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zeit_dep = b.dependency("zeit", .{
        .target = target,
        .optimize = optimize,
    });

    const zmail_mod = b.addModule("zmail", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zmail_mod.addImport("zeit", zeit_dep.module("zeit"));

    const api_tests = b.addTest(.{
        .root_source_file = b.path("test/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    api_tests.root_module.addImport("zeit", zeit_dep.module("zeit"));
    api_tests.root_module.addImport("zmail", zmail_mod);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("zeit", zeit_dep.module("zeit"));

    const run_api_tests = b.addRunArtifact(api_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_api_tests.step);
    test_step.dependOn(&run_unit_tests.step);

    const imap_step = b.step("imap", "Run the imap example");
    const imap = b.addExecutable(.{
        .name = "imap-test",
        .root_source_file = b.path("test/imap.zig"),
        .optimize = optimize,
        .target = target,
    });
    imap.root_module.addImport("zmail", zmail_mod);
    const imap_run = b.addRunArtifact(imap);
    if (b.args) |args| {
        imap_run.addArgs(args);
    }
    imap_step.dependOn(&imap_run.step);
}
