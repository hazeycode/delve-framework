const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");
const zaudio = @import("zaudio");
const zmesh = @import("zmesh");
const ziglua = @import("ziglua");
const zstbi = @import("zstbi");
const system_sdk = @import("system_sdk");

var target: Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var dep_sokol: *Build.Dependency = undefined;

const String = []const u8;
const ModuleImport = struct {
    module: *Build.Module,
    name: String,
};
const BuildCollection = struct {
    add_imports: []const ModuleImport,
    link_libraries: []const *Build.Step.Compile,
};
const ExampleItem = []const String;

// zig build -freference-trace run-forest
// zig build -Dtarget=wasm32-emscripten -freference-trace run-forest

pub fn build(b: *std.Build) !void {
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});

    dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const ziglua_dep = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
    });
    const ziglua_mod = ziglua_dep.module("ziglua");
    const ziglua_item = .{ .module = ziglua_mod, .name = "ziglua" };
    const ziglua_artifact = ziglua_dep.artifact("lua"); // added to staticLibrary array
    ziglua_artifact.linkLibC();

    const zmesh_pkg = zmesh.package(b, target, optimize, .{});
    const zstbi_pkg = zstbi.package(b, target, optimize, .{});
    const zaudio_pkg = zaudio.package(b, target, optimize, .{});

    const sokol_item = .{ .module = dep_sokol.module("sokol"), .name = "sokol" };
    const zmesh_item = .{ .module = zmesh_pkg.zmesh, .name = "zmesh" };
    const zmesh_options_item = .{ .module = zmesh_pkg.zmesh_options, .name = "zmesh_options" };
    const zstbi_item = .{ .module = zstbi_pkg.zstbi, .name = "zstbi" };
    const zaudio_item = .{ .module = zaudio_pkg.zaudio, .name = "zaudio" };
    const delve_module_imports = [_]ModuleImport{
        sokol_item,
        ziglua_item,
        zmesh_item,
        zmesh_options_item,
        zstbi_item,
        zaudio_item,
    };
    const link_libraries = [_]*Build.Step.Compile{
        ziglua_artifact,
        zmesh_pkg.zmesh_c_cpp,
        zstbi_pkg.zstbi_c_cpp,
        zaudio_pkg.zaudio_c_cpp,
    };

    var build_collection: BuildCollection = .{
        .add_imports = &delve_module_imports,
        .link_libraries = &link_libraries,
    };

    // Delve module
    const delve_mod = b.addModule("delve", .{
        .root_source_file = .{ .path = "src/framework/delve.zig" },
        .target = target,
        .optimize = optimize,
    });

    for (build_collection.add_imports) |build_import| {
        delve_mod.addImport(build_import.name, build_import.module);
    }
    //const emsdk_sysroot_include = b.dependency("emsdk", .{}).path("upstream/emscripten/cache/sysroot/include").getPath(b);
    for (build_collection.link_libraries) |lib| {
        //lib.addIncludePath(.{ .path = emsdk_sysroot_include });
        delve_mod.linkLibrary(lib);
    }

    // create new list with delve included
    const app_module_imports = [_]ModuleImport{
        sokol_item,
        ziglua_item,
        zmesh_item,
        zmesh_options_item,
        zstbi_item,
        zaudio_item,
        .{ .module = delve_mod, .name = "delve" },
    };
    build_collection.add_imports = &app_module_imports;

    // collection of all examples
    const example_list = [_]ExampleItem{
        &[_]String{ "audio", "src/examples/audio.zig" },
        &[_]String{ "sprites", "src/examples/sprites.zig" },
        &[_]String{ "sprite-animation", "src/examples/sprite-animation.zig" },
        &[_]String{ "clear", "src/examples/clear.zig" },
        &[_]String{ "collision", "src/examples/collision.zig" },
        &[_]String{ "debugdraw", "src/examples/debugdraw.zig" },
        &[_]String{ "easing", "src/examples/easing.zig" },
        &[_]String{ "forest", "src/examples/forest.zig" },
        &[_]String{ "framepacing", "src/examples/framepacing.zig" },
        &[_]String{ "frustums", "src/examples/frustums.zig" },
        &[_]String{ "lua", "src/examples/lua.zig" },
        &[_]String{ "meshbuilder", "src/examples/meshbuilder.zig" },
        &[_]String{ "meshes", "src/examples/meshes.zig" },
        &[_]String{ "passes", "src/examples/passes.zig" },
        &[_]String{ "stresstest", "src/examples/stresstest.zig" },
    };

    for (example_list) |example_item| {
        try buildExample(b, example_item, build_collection);
    }

    // TESTS
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/framework/delve.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn buildExample(b: *std.Build, example: ExampleItem, build_collection: BuildCollection) !void {
    const name: []const u8 = example[0];
    const root_source_file: []const u8 = example[1];

    var app: *Build.Step.Compile = undefined;
    // special case handling for native vs web build
    if (target.result.isWasm()) {
        // Web
        app = b.addStaticLibrary(.{
            .target = target,
            .optimize = optimize,
            .name = name,
            .root_source_file = .{ .path = root_source_file },
        });
    } else {
        // Native
        app = b.addExecutable(.{
            .target = target,
            .optimize = optimize,
            .name = name,
            .root_source_file = .{ .path = root_source_file },
        });
    }

    // Modules linked to app
    for (build_collection.add_imports) |mod| {
        app.root_module.addImport(mod.name, mod.module);
    }

    // Static libs linked to app
    for (build_collection.link_libraries) |lib| {
        app.root_module.linkLibrary(lib);
    }

    if (target.result.isWasm()) {
        // create a build step which invokes the Emscripten linker
        const emsdk = dep_sokol.builder.dependency("emsdk", .{});
        const emcc_run: *Build.Step.Run = try sokol.emLinkStep(b, .{
            .lib_main = app,
            .target = target,
            .optimize = optimize,
            .emsdk = emsdk,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = false,
            .shell_file_path = dep_sokol.path(thisDir() ++ "/3rdparty/sokol_web/shell.html").getPath(b),
        });

        for (build_collection.add_imports) |mod| {
            const comp: *Build.Step.Compile = b.addStaticLibrary(.{
                .optimize = optimize,
                .target = target,
                .name = mod.name,
                .root_source_file = mod.module.root_source_file,
            });
            comp.linkLibC(); // + This?
            emcc_run.addArtifactArg(comp);
        }

        const emsdk_sysroot_include = b.dependency("emsdk", .{}).path("upstream/emscripten/cache/sysroot/include").getPath(b);
        for (build_collection.link_libraries) |lib| {
            lib.addIncludePath(.{ .path = emsdk_sysroot_include });
            emcc_run.addArtifactArg(lib);
        }

        // ...and a special run step to start the web build output via 'emrun'
        const run: *Build.Step.Run = sokol.emRunStep(b, .{ .name = name, .emsdk = emsdk });
        run.step.dependOn(&emcc_run.step);

        var option_buffer = [_]u8{undefined} ** 100;
        const run_name = try std.fmt.bufPrint(&option_buffer, "run-{s}", .{name});
        var description_buffer = [_]u8{undefined} ** 200;
        const descr_name = try std.fmt.bufPrint(&description_buffer, "run {s}", .{name});
        b.step(run_name, descr_name).dependOn(&run.step);
    } else {
        b.installArtifact(app);
        const run = b.addRunArtifact(app);
        var option_buffer = [_]u8{undefined} ** 100;
        const run_name = try std.fmt.bufPrint(&option_buffer, "run-{s}", .{name});
        var description_buffer = [_]u8{undefined} ** 200;
        const descr_name = try std.fmt.bufPrint(&description_buffer, "run {s}", .{name});

        b.step(run_name, descr_name).dependOn(&run.step);
    }
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
