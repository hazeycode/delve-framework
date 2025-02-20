const std = @import("std");
const delve = @import("delve");
const app = delve.app;

var primary_camera: delve.graphics.camera.Camera = undefined;
var secondary_camera: delve.graphics.camera.Camera = undefined;

var material_frustum: delve.platform.graphics.Material = undefined;
var material_cube: delve.platform.graphics.Material = undefined;
var material_highlight: delve.platform.graphics.Material = undefined;

var frustum_mesh: delve.graphics.mesh.Mesh = undefined;
var cube_mesh: delve.graphics.mesh.Mesh = undefined;

var time: f32 = 0.0;

pub fn main() !void {
    const example = delve.modules.Module{
        .name = "frustums_example",
        .init_fn = on_init,
        .tick_fn = on_tick,
        .draw_fn = on_draw,
    };

    try delve.modules.registerModule(example);
    try delve.module.fps_counter.registerModule();

    try app.start(app.AppConfig{ .title = "Delve Framework - Frustums Example" });
}

pub fn on_init() void {
    // Create a material out of the texture
    material_frustum = delve.platform.graphics.Material.init(.{
        .shader = delve.platform.graphics.Shader.initDefault(.{}),
        .texture_0 = delve.platform.graphics.createSolidTexture(0x66FFFFFF),
        .cull_mode = .NONE,
        .depth_write_enabled = false,
        .blend_mode = .BLEND,
    });

    material_cube = delve.platform.graphics.Material.init(.{
        .shader = delve.platform.graphics.Shader.initDefault(.{}),
        .texture_0 = delve.platform.graphics.tex_white,
    });

    material_highlight = delve.platform.graphics.Material.init(.{
        .shader = delve.platform.graphics.Shader.initDefault(.{}),
        .texture_0 = delve.platform.graphics.createSolidTexture(0xFFFF0000),
    });

    // create our two cameras - one for the real camera, and another just to get a smaller frustum from
    primary_camera = delve.graphics.camera.Camera.initThirdPerson(90.0, 0.01, 100.0, 5.0, delve.math.Vec3.up);
    secondary_camera = delve.graphics.camera.Camera.initThirdPerson(30.0, 8, 40.0, 5.0, delve.math.Vec3.up);

    // set initial camera position
    primary_camera.position = delve.math.Vec3.new(0,30,32);
    primary_camera.pitch_angle = -50.0;

    // create the two meshes we'll use - a frustum prism, and a cube
    frustum_mesh = createFrustumMesh() catch {
        delve.debug.fatal("Could not create frustum mesh!", .{});
        return;
    };

    cube_mesh = delve.graphics.mesh.createCube(delve.math.Vec3.new(0, 0, 0), delve.math.Vec3.new(1, 1, 1), delve.colors.white, material_cube) catch {
        delve.debug.fatal("Could not create cube mesh!", .{});
        return;
    };

    // set a bg color
    delve.platform.graphics.setClearColor(delve.colors.examples_bg_dark);

    // capture mouse
    delve.platform.app.captureMouse(true);
}

pub fn on_tick(delta: f32) void {
    if (delve.platform.input.isKeyJustPressed(.ESCAPE))
        std.os.exit(0);

    time += delta;

    primary_camera.runSimpleCamera(8 * delta, 120 * delta, true);
    secondary_camera.setYaw(time * 50.0);
}

pub fn on_draw() void {
    const proj_view_matrix = primary_camera.getProjView();
    const frustum_model_matrix = delve.math.Mat4.rotate(secondary_camera.yaw_angle, delve.math.Vec3.up);

    for(0..10) |x| {
        for(0..10) |z| {
            const cube_pos = delve.math.Vec3.new(@floatFromInt(x), 0, @floatFromInt(z)).scale(5.0).sub(delve.math.Vec3.new(25, 0, 25));
            const cube_model_matrix = delve.math.Mat4.translate(cube_pos);

            const frustum = secondary_camera.getViewFrustum();
            const bounds = cube_mesh.bounds.translate(cube_pos);

            if(frustum.containsBoundingBox(bounds)) {
                cube_mesh.drawWithMaterial(&material_highlight, proj_view_matrix, cube_model_matrix);
            } else {
                cube_mesh.draw(proj_view_matrix, cube_model_matrix);
            }
        }
    }

    frustum_mesh.draw(proj_view_matrix, frustum_model_matrix);
}

pub fn createFrustumMesh() !delve.graphics.mesh.Mesh {
    var builder = delve.graphics.mesh.MeshBuilder.init();
    defer builder.deinit();

    try builder.addFrustum(secondary_camera.getViewFrustum(), delve.math.Mat4.identity, delve.colors.cyan);

    return builder.buildMesh(material_frustum);
}
