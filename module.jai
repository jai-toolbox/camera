#import "Math";
#import "Basic";

#import "tbx/math";

// world space is where the origin is at (0, 0, 0) with axes defined by x = (1, 0, 0), y, z
// camera space is where the origin is at the camera's position with axes defined by the cameras look direction
// clip space is a unit cube [-1, 1]^3 where anything outide gets "clipped" out, and not rendered.
// matrices can represent "change of bases" where we can take a vector written wrt to one basis and write it in the second basis
Camera :: struct {
    position : Vector3;
    offset : Vector3; // when you want to have some constant offset such as "eyes pos"
    yaw, pitch : float;
    // is there ever a reason to be storing these in here? probably not and I should get rid of it later on.
    world_to_camera := Matrix4_Identity;
    camera_to_clip := Matrix4_Identity;
    fov := 90.0;
    last_mouse_x, last_mouse_y : int;
};

update_angles :: (using camera : *Camera, mouse_x: int, mouse_y: int) {
    mouse_delta_x := mouse_x - last_mouse_x;
    mouse_delta_y := mouse_y - last_mouse_y;
    last_mouse_x = mouse_x; last_mouse_y = mouse_y;
    yaw += mouse_delta_x * PI / 180.0;
    pitch += mouse_delta_y * PI / 180.0;
    pitch = clamp (pitch, -89.0  * PI / 180.0, 89.0 * PI / 180.0);
}

update_angles_with_deltas :: (using camera : *Camera, mouse_delta_x: int, mouse_delta_y: int) {
    yaw += mouse_delta_x * PI / 180.0;
    pitch += mouse_delta_y * PI / 180.0;
    pitch = clamp (pitch, -89.0  * PI / 180.0, 89.0 * PI / 180.0);
}


get_forward :: (camera : *Camera) -> Vector3 {
    raw_forward := -Z3;
    return rotate(raw_forward, get_rotation(camera));
}

get_rotation :: (using camera : *Camera) -> Quaternion {
    yaw_quat, pitch_quat: Quaternion;

    // I am not sure why I need to invert the axis of rotation...
    // probably because of the rotation direction and right hand rule, look into later, inverting so it works.

    set_from_axis_and_angle (*yaw_quat, 0, -1, 0, yaw);
    set_from_axis_and_angle (*pitch_quat, -1, 0, 0, pitch);

    rotation := yaw_quat * pitch_quat;

    return rotation;
}

update_matrices :: (using camera : *Camera, window_width: int, window_height: int) {
    rotation := get_rotation(camera);
    transform := make_translation_matrix4 (position + offset) * rotation_matrix (Matrix4, rotation);

    // suppose we are a camera, if I take a picture and then move to the right and take a new picture, then all objects from the first scene appear to the left of the original
    // picture. Now suppose the camera is an immovable object, if we want the same effect, then for every object in the scene we need to move it left instead of right.
    // This explains why we must invert the transform here, the camera is immovable (it just sits in the center of the [-1, 1]^3 cube), thus to create the illusion of movement
    // we have to move everything the opposite way that we are going.
    camera.world_to_camera = inverse(transform);

    aspect_ratio := window_width / cast (float) window_width;

    // NOTE this matrix makes -z forward, which is bad and I want to change it later on, this explains the note of (1) 
    // if this used z forward, then we'd undo what was done @ (1) 
    camera_to_clip = make_projection_matrix (fov * PI / 180.0, aspect_ratio, 0.1, 1000.0);
}

update_matrices_third_person :: (using camera : *Camera, window_width: int, window_height: int) {

    rotation := get_rotation(camera);
    forward := get_forward(camera);
    
    distance_behind := 4.0;
    height_offset := 0.0;

    transform := make_translation_matrix4 (position + offset - forward * distance_behind + Y3 * height_offset) * rotation_matrix (Matrix4, rotation);

    // suppose we are a camera, if I take a picture and then move to the right and take a new picture, then all objects from the first scene appear to the left of the original
    // picture. Now suppose the camera is an immovable object, if we want the same effect, then for every object in the scene we need to move it left instead of right.
    // This explains why we must invert the transform here, the camera is immovable (it just sits in the center of the [-1, 1]^3 cube), thus to create the illusion of movement
    // we have to move everything the opposite way that we are going.
    camera.world_to_camera = inverse(transform);

    aspect_ratio := window_width / cast (float) window_width;

    // NOTE this matrix makes -z forward, which is bad and I want to change it later on, this explains the note of (1) 
    // if this used z forward, then we'd undo what was done @ (1) 
    camera_to_clip = make_projection_matrix (fov * PI / 180.0, aspect_ratio, 0.1, 1000.0);
}
