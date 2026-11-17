#import "Math";
#import "Basic";

#import "tbx/turns";
#import "tbx/math";

// small epsilon to stay away from the gimbal lock singularity at exactly 1/4 turn
PITCH_EPSILON :: 0.001;

PIXELS_PER_TURN : float : 16384; 

/*

link to toolbox article about "whats up"

*/


Camera :: struct {
    position : Vector3;
    offset : Vector3; // when you want to have some constant offset such as "eyes pos"

    yaw, pitch : float; // in turns
    
    // world up allows us to allow this camera to work in different rendering
    // systems where gravitational up is bound to a different axis.
    world_up: Vector3 = WORLD_UP;

    sensitivity : float = 1;

    fov : float = ONE_QUARTER_TURN;
    last_mouse_x, last_mouse_y : int;
};

update_angles :: (using camera : *Camera, mouse_x: int, mouse_y: int, sensitivity_override: float = -1) {
    sensitivity_to_use : float = ifx sensitivity_override != -1 then sensitivity_override else sensitivity;
    mouse_delta_x : float = (mouse_x - last_mouse_x) * sensitivity_to_use;
    mouse_delta_y : float = (mouse_y - last_mouse_y) * sensitivity_to_use;
    last_mouse_x = mouse_x; last_mouse_y = mouse_y;
    yaw   += mouse_delta_x / PIXELS_PER_TURN;
    pitch += mouse_delta_y / PIXELS_PER_TURN;
    pitch = clamp(pitch, -ONE_QUARTER_TURN + PITCH_EPSILON, ONE_QUARTER_TURN - PITCH_EPSILON);
}

update_angles_with_deltas :: (using camera : *Camera, mouse_delta_x: int, mouse_delta_y: int, sensitivity_override: float = -1) {
    sensitivity_to_use : float = ifx sensitivity_override != -1 then sensitivity_override else sensitivity;
    
    yaw   += mouse_delta_x / PIXELS_PER_TURN * sensitivity_to_use;
    pitch += mouse_delta_y / PIXELS_PER_TURN * sensitivity_to_use;

    pitch = clamp(pitch, -ONE_QUARTER_TURN + PITCH_EPSILON, ONE_QUARTER_TURN - PITCH_EPSILON);
}

// https://toolbox.cuppajoeman.com/programming/game_dev/fov_and_sensitivity.html
// note that the inputs are measured in turns
compute_new_sensitivity :: (original_sensitivity: float, original_fov: float, new_fov: float) -> float {
    tan_half_original_fov := tan_turns(original_fov / 2.0);
    tan_half_new_fov      := tan_turns(new_fov / 2.0);

    return original_sensitivity * (tan_half_new_fov / tan_half_original_fov);
}

// Neutral camera axes match the world convention. Projection performs the
// conversion to clip space; the view matrix only removes the camera pose.
get_forward :: (camera : *Camera) -> Vector3 {
    raw_forward := WORLD_FORWARD;
    return rotate(raw_forward, get_rotation(camera));
}

get_right :: (camera : *Camera) -> Vector3 {
    raw_right := WORLD_RIGHT;
    return rotate(raw_right, get_rotation(camera));
}

get_up :: (camera : *Camera) -> Vector3 {
    raw_up := WORLD_UP;
    return rotate(raw_up, get_rotation(camera));
}

get_rotation :: (using camera : *Camera) -> Quaternion {
    yaw_quat, pitch_quat: Quaternion;

    // Positive mouse deltas look right/down. Yaw rotates about world down;
    // pitch rotates about the neutral camera's left axis, before yaw.
    set_from_axis_and_angle(*yaw_quat, WORLD_DOWN.x, WORLD_DOWN.y, WORLD_DOWN.z, turns_to_radians(yaw));
    set_from_axis_and_angle(*pitch_quat, WORLD_LEFT.x, WORLD_LEFT.y, WORLD_LEFT.z, turns_to_radians(pitch));

    rotation := rotation_between_vectors(WORLD_UP, world_up) * yaw_quat * pitch_quat;

    return rotation;
}

set_camera_look_at :: (camera: *Camera, position: Vector3, target: Vector3) {
    camera.position = position;
    direction := rotate(normalize(target - (position + camera.offset)), conjugate(rotation_between_vectors(WORLD_UP, camera.world_up)));
    forward := dot(direction, WORLD_FORWARD);
    right := dot(direction, WORLD_RIGHT);
    up := dot(direction, WORLD_UP);
    camera.yaw = atan2(right, forward) / TAU;
    // atan2 retains precision at the poles, including exact orthographic axis views.
    camera.pitch = -atan2(up, length(Vector2.{forward, right})) / TAU;
}

// Returns camera-local coordinates in the world axis convention, NOT the
// legacy -Z-forward eye convention. Pair with make_world_projection_matrix
// or make_world_orthographic_projection_matrix.
get_world_to_camera_matrix :: (using camera : *Camera) -> Matrix4 {
    rotation := get_rotation(camera);
    transform := make_translation_matrix4(position + offset) * rotation_matrix(Matrix4, rotation);

    // suppose we are a camera, if I take a picture and then move to the right and take a new picture, then all objects from the first scene appear to the left of the original
    // picture. Now suppose the camera is an immovable object, if we want the same effect, then for every object in the scene we need to move it left instead of right.
    // This explains why we must invert the transform here, the camera is immovable (it just sits in the center of the [-1, 1]^3 cube), thus to create the illusion of movement
    // we have to move everything the opposite way that we are going.

    // is it always possible to invert?
    able_to_invert, inverse := inverse(transform);

    return inverse;
}

get_projection_matrix :: (using camera : *Camera, window_width : int, window_height : int) -> Matrix4 {
    aspect_ratio := window_width / cast (float) window_height;

    return make_world_projection_matrix(turns_to_radians(fov), aspect_ratio, 0.1, 1000.0);
}

// Input is camera-local XYZ in the world convention: +X forward, -Y right,
// +Z up, with w = 1 for positions. Output is OpenGL clip coordinates; the GPU
// performs the perspective divide. In particular, w_clip = x_camera.
// FOV is vertical and in radians. Near/far are positive forward distances.
make_world_projection_matrix :: (
    fov_vertical: float,
    aspect_ratio: float,
    z_near: float,
    z_far: float,
    depth_range_01 := false,
) -> Matrix4 {
    assert(fov_vertical > 0 && fov_vertical < PI, "Vertical FOV must be between zero and pi radians");
    assert(aspect_ratio > 0, "Aspect ratio must be positive");
    assert(z_near > 0 && z_far > z_near, "Expected 0 < near < far");

    vertical_scale := 1 / tan(fov_vertical * 0.5);
    horizontal_scale := vertical_scale / aspect_ratio;
    depth_scale := (z_far + z_near) / (z_far - z_near);
    depth_offset := -2 * z_far * z_near / (z_far - z_near);
    if depth_range_01 {
        depth_scale = z_far / (z_far - z_near);
        depth_offset = -z_far * z_near / (z_far - z_near);
    }

    result: Matrix4;
    result._11 = horizontal_scale * WORLD_RIGHT.x;
    result._12 = horizontal_scale * WORLD_RIGHT.y;
    result._13 = horizontal_scale * WORLD_RIGHT.z;
    result._21 = vertical_scale * WORLD_UP.x;
    result._22 = vertical_scale * WORLD_UP.y;
    result._23 = vertical_scale * WORLD_UP.z;
    result._31 = depth_scale * WORLD_FORWARD.x;
    result._32 = depth_scale * WORLD_FORWARD.y;
    result._33 = depth_scale * WORLD_FORWARD.z;
    result._34 = depth_offset;
    result._41 = WORLD_FORWARD.x;
    result._42 = WORLD_FORWARD.y;
    result._43 = WORLD_FORWARD.z;
    return result;
}

// Orthographic counterpart using the same camera-local convention. Left/right
// and bottom/top measure distances along WORLD_RIGHT and WORLD_UP respectively.
make_world_orthographic_projection_matrix :: (
    left: float, right: float, bottom: float, top: float,
    z_near: float, z_far: float,
    depth_range_01 := false,
) -> Matrix4 {
    assert(right > left && top > bottom && z_far > z_near);
    basis := Matrix4_Identity;
    basis._11 = WORLD_RIGHT.x;
    basis._12 = WORLD_RIGHT.y;
    basis._13 = WORLD_RIGHT.z;
    basis._21 = WORLD_UP.x;
    basis._22 = WORLD_UP.y;
    basis._23 = WORLD_UP.z;
    basis._31 = -WORLD_FORWARD.x;
    basis._32 = -WORLD_FORWARD.y;
    basis._33 = -WORLD_FORWARD.z;
    return orthographic_projection_matrix(left, right, bottom, top, z_near, z_far, depth_range_01 = depth_range_01) * basis;
}
