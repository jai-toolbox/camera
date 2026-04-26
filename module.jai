#import "Math";
#import "Basic";

#import "tbx/turns";
#import "tbx/math";

// small epsilon to stay away from the gimbal lock singularity at exactly 1/4 turn
PITCH_EPSILON :: 0.001;

PIXELS_PER_TURN : float : 2048;

// world space is where the origin is at (0, 0, 0) with axes defined by x = (1, 0, 0), y, z
// camera space is where the origin is at the camera's position with axes defined by the cameras look direction
// clip space is a unit cube [-1, 1]^3 where anything outide gets "clipped" out, and not rendered.
// matrices can represent "change of bases" where we can take a vector written wrt to one basis and write it in the second basis
Camera :: struct {
    position : Vector3;
    offset : Vector3; // when you want to have some constant offset such as "eyes pos"

    yaw, pitch : float; // in turns

    sensitivity : float = 1;

    // is there ever a reason to be storing these in here? probably not and I should get rid of it later on.
    // world_to_camera := Matrix4_Identity;
    // camera_to_clip := Matrix4_Identity;

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

// returns a normalized vector since Z3 is
get_forward :: (camera : *Camera) -> Vector3 {
    raw_forward := -Z3;
    return rotate(raw_forward, get_rotation(camera));
}

get_right :: (camera : *Camera) -> Vector3 {
    raw_right := X3;
    return rotate(raw_right, get_rotation(camera));
}

get_up :: (camera : *Camera) -> Vector3 {
    raw_up := Y3;
    return rotate(raw_up, get_rotation(camera));
}

get_rotation :: (using camera : *Camera) -> Quaternion {
    yaw_quat, pitch_quat: Quaternion;

    // I am not sure why I need to invert the axis of rotation...
    // probably because of the rotation direction and right hand rule, look into later, inverting so it works.

    set_from_axis_and_angle(*yaw_quat, 0, -1, 0, turns_to_radians(yaw));
    set_from_axis_and_angle(*pitch_quat, -1, 0, 0, turns_to_radians(pitch));

    rotation := yaw_quat * pitch_quat;

    return rotation;
}

get_world_to_camera_matrix :: (using camera : *Camera) -> Matrix4 {
    rotation := get_rotation(camera);
    transform := make_translation_matrix4 (position + offset) * rotation_matrix (Matrix4, rotation);

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

    // NOTE this matrix makes -z forward, which is bad and I want to change it later on, this explains the note of (1) 
    // if this used z forward, then we'd undo what was done @ (1) 
    return make_projection_matrix (turns_to_radians(fov), aspect_ratio, 0.1, 1000.0);
}
