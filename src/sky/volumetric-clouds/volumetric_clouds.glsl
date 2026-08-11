#[compute]
#version 450

// Adapted from Clay John's godot-volumetric-cloud-demo-v2.
// See LICENSES/volumetric-clouds-MIT.txt.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D current_image;
layout(set = 1, binding = 0) uniform sampler3D large_scale_noise;
layout(set = 1, binding = 1) uniform sampler3D small_scale_noise;
layout(set = 1, binding = 2) uniform sampler2D weather_noise;
layout(set = 1, binding = 3) uniform sampler2D blue_noise;

// 128-byte push-constant limit.
layout(push_constant, std430) uniform Params {
    vec2 texture_size;
    vec2 update_position;
    vec2 cloud_pos;
    vec2 detailed_pos;
    vec2 weather_pos;
    vec2 pad1;
    vec3 ground_color;
    float ground_light_multiplier;
    vec3 light_direction;
    float light_energy;
    vec3 light_color;
    float direct_light_multiplier;
    vec3 ambient_color;
    float ambient_light_multiplier;
    float density;
    float cloud_coverage;
    float time;
    float pad2;
} params;

layout(std140, set = 2, binding = 0) uniform CloudConfig {
    vec4 layer;
    vec4 noise;
    vec4 erosion;
    vec4 phase;
    vec4 lighting;
    vec4 sampling;
    vec4 aerial;
    vec4 reserved;
} config;

const float GROUND_RADIUS = 6000000.0;
const int MAX_VIEW_SAMPLES = 160;
const int MAX_LIGHT_SAMPLES = 8;
const float EPSILON = 0.000001;

float cloud_bottom_radius() {
    return GROUND_RADIUS + max(config.layer.x, 0.0);
}

float cloud_top_radius() {
    return cloud_bottom_radius() + max(config.layer.y, 1.0);
}

float henyey_greenstein(float cos_theta, float g) {
    const float INV_4PI = 0.0795774715459;
    g = clamp(g, -0.95, 0.95);
    float denominator = max(1.0 + g * g - 2.0 * g * clamp(cos_theta, -1.0, 1.0), EPSILON);
    return INV_4PI * (1.0 - g * g) / pow(denominator, 1.5);
}

float dual_lobe_henyey_greenstein(float cos_theta, vec2 anisotropy, float backward_weight) {
    return mix(
        henyey_greenstein(cos_theta, anisotropy.x),
        henyey_greenstein(cos_theta, anisotropy.y),
        clamp(backward_weight, 0.0, 1.0)
    );
}

float height_fraction(float radius) {
    return clamp(
        (radius - cloud_bottom_radius()) / max(config.layer.y, 1.0),
        0.0,
        1.0
    );
}

vec4 mix_gradients(float cloud_type) {
    const vec4 STRATUS = vec4(0.02, 0.05, 0.09, 0.11);
    const vec4 STRATOCUMULUS = vec4(0.02, 0.2, 0.48, 0.625);
    const vec4 CUMULUS = vec4(0.01, 0.0625, 0.78, 1.0);
    float stratus = 1.0 - clamp(cloud_type * 2.0, 0.0, 1.0);
    float stratocumulus = 1.0 - abs(cloud_type - 0.5) * 2.0;
    float cumulus = clamp(cloud_type - 0.5, 0.0, 1.0) * 2.0;
    return STRATUS * stratus + STRATOCUMULUS * stratocumulus + CUMULUS * cumulus;
}

float density_height_gradient(float height_frac, float cloud_type) {
    vec4 gradient = mix_gradients(cloud_type);
    return max(
        smoothstep(gradient.x, gradient.y, height_frac)
            - smoothstep(gradient.z, gradient.w, height_frac),
        0.0
    );
}

float sphere_far_distance(vec3 pos, vec3 dir, float radius) {
    float b = dot(dir, pos);
    float c = dot(pos, pos) - radius * radius;
    float discriminant = b * b - c;
    if (discriminant < 0.0) {
        return -1.0;
    }
    return -b + sqrt(discriminant);
}

float sphere_near_distance(vec3 pos, vec3 dir, float radius) {
    float b = dot(dir, pos);
    float c = dot(pos, pos) - radius * radius;
    float discriminant = b * b - c;
    if (discriminant < 0.0) {
        return -1.0;
    }

    float root = sqrt(discriminant);
    float near_distance = -b - root;
    if (near_distance > EPSILON) {
        return near_distance;
    }

    float far_distance = -b + root;
    return far_distance > EPSILON ? far_distance : -1.0;
}

float sample_density(vec3 point, float mip) {
    float radius = length(point);
    float bottom_radius = cloud_bottom_radius();
    float top_radius = cloud_top_radius();
    if (radius <= bottom_radius || radius >= top_radius) {
        return 0.0;
    }

    float height_frac = height_fraction(radius);
    vec3 weather = texture(
        weather_noise,
        point.xz * max(config.noise.x, 0.0) + 0.5 + params.weather_pos
    ).xyz;
    float weather_coverage = clamp(params.cloud_coverage * weather.b, 0.0, 1.0);
    float weather_skip = max(config.layer.z, 0.0);
    if (weather_coverage <= weather_skip) {
        return 0.0;
    }

    float height_gradient = density_height_gradient(height_frac, weather.r);
    if (height_gradient <= 0.0) {
        return 0.0;
    }

    vec3 p = point;
    p.xz += 20.0 * params.cloud_pos * 0.6;
    vec4 base_noise = textureLod(
        large_scale_noise,
        p * max(config.noise.y, 0.0),
        max(mip - 2.0, 0.0)
    );
    float base_fbm = base_noise.g * 0.625 + base_noise.b * 0.25 + base_noise.a * 0.125;
    float base_cloud = clamp(
        (base_noise.r + 1.0 - base_fbm) / max(2.0 - base_fbm, EPSILON),
        0.0,
        1.0
    );
    base_cloud = clamp(
        (base_cloud * height_gradient - (1.0 - weather_coverage))
            / max(weather_coverage, EPSILON),
        0.0,
        1.0
    ) * weather_coverage;

    float density_skip = max(config.layer.w, 0.0);
    if (base_cloud <= density_skip) {
        return 0.0;
    }

    p.xz -= params.detailed_pos * 40.0;
    p.y -= params.time * 40.0;
    vec3 detail_noise = textureLod(
        small_scale_noise,
        p * max(config.noise.z, 0.0),
        max(mip, 0.0)
    ).rgb;
    float detail_fbm = detail_noise.r * 0.625
            + detail_noise.g * 0.25
            + detail_noise.b * 0.125;
    float inversion_height = max(config.noise.w, EPSILON);
    detail_fbm = mix(
        detail_fbm,
        1.0 - detail_fbm,
        clamp(height_frac / inversion_height, 0.0, 1.0)
    );

    float erosion_height = mix(
        1.0,
        height_frac,
        clamp(config.erosion.y, 0.0, 1.0)
    );
    float erosion_amount = clamp(
        detail_fbm * max(config.erosion.x, 0.0) * erosion_height,
        0.0,
        1.0 - EPSILON
    );
    base_cloud = clamp(
        (base_cloud - erosion_amount) / max(1.0 - erosion_amount, EPSILON),
        0.0,
        1.0
    );
    if (base_cloud <= density_skip) {
        return 0.0;
    }

    float density_power = mix(
        max(config.erosion.z, EPSILON),
        max(config.erosion.w, EPSILON),
        height_frac
    );
    return pow(base_cloud, density_power);
}

float light_path_length(vec3 point, vec3 light_direction) {
    float top_exit = sphere_far_distance(point, light_direction, cloud_top_radius());
    if (top_exit <= 0.0) {
        return 0.0;
    }

    float bottom_entry = sphere_near_distance(point, light_direction, cloud_bottom_radius());
    if (bottom_entry > 0.0 && bottom_entry < top_exit) {
        return bottom_entry;
    }
    return top_exit;
}

vec4 march_clouds(
        vec3 start,
        vec3 direction,
        float ray_length,
        int step_count,
        float jitter
    ) {
    float step_size = ray_length / float(step_count);
    vec3 p = start + direction * jitter * step_size;
    vec3 light_direction = normalize(params.light_direction);

    float transmittance = 1.0;
    vec3 luminance = vec3(0.0);
    float cos_theta = dot(light_direction, direction);
    vec2 phase_anisotropy = config.phase.xy;
    float phase_single = dual_lobe_henyey_greenstein(
        cos_theta,
        phase_anisotropy,
        config.phase.z
    );
    float phase_multiple = dual_lobe_henyey_greenstein(
        cos_theta,
        phase_anisotropy * 0.5,
        config.phase.z
    );

    vec3 direct_light = params.light_color
            * params.light_energy
            * params.direct_light_multiplier;
    vec3 ambient_light = params.ambient_color * params.ambient_light_multiplier;
    vec3 ground_light = params.ground_color * params.ground_light_multiplier;
    int light_sample_count = int(clamp(floor(config.sampling.y + 0.5), 1.0, 8.0));
    float early_exit = clamp(config.lighting.w, 0.0, 1.0);

    for (int i = 0; i < MAX_VIEW_SAMPLES; i++) {
        if (i >= step_count) {
            break;
        }

        float radius = length(p);
        float height_frac = height_fraction(radius);
        float cloud_density = sample_density(p, 0.0);
        if (cloud_density > 0.0) {
            float tau_step = max(params.density, 0.0) * cloud_density * step_size;
            float step_transmittance = exp(-tau_step);
            float segment_alpha = 1.0 - step_transmittance;

            float single_scattering = 0.0;
            float multiple_scattering = 0.0;
            bool ground_occluded = sphere_near_distance(
                p,
                light_direction,
                GROUND_RADIUS
            ) > 0.0;
            float light_distance = ground_occluded ? 0.0 : light_path_length(p, light_direction);
            if (light_distance > 0.0) {
                float light_step_size = light_distance / float(light_sample_count);
                float integrated_light_density = 0.0;
                for (int j = 0; j < MAX_LIGHT_SAMPLES; j++) {
                    if (j >= light_sample_count) {
                        break;
                    }
                    float sample_distance = (float(j) + jitter) * light_step_size;
                    vec3 light_point = p + light_direction * sample_distance;
                    float light_mip = light_sample_count > 1
                        ? 5.0 * float(j) / float(light_sample_count - 1)
                        : 0.0;
                    integrated_light_density += sample_density(light_point, light_mip)
                        * light_step_size;
                }

                float tau_light = max(params.density, 0.0) * integrated_light_density;
                float beer = exp(-tau_light);
                float powder = 1.0 - beer * beer;
                single_scattering = 2.0 * beer * powder * phase_single;

                float multiple_extinction = max(config.lighting.x, 0.0);
                float multiple_transmittance = exp(-tau_light * multiple_extinction);
                multiple_scattering = max(config.phase.w, 0.0)
                    * multiple_transmittance
                    * (1.0 - beer)
                    * phase_multiple;
            }

            float ambient_ao = max(
                clamp(config.lighting.z, 0.0, 1.0),
                1.0 / (
                    1.0
                    + max(config.lighting.y, 0.0) * cloud_density * cloud_density
                )
            );
            vec3 ambient = mix(
                ground_light,
                ambient_light,
                smoothstep(0.0, 1.0, height_frac)
            ) * ambient_ao;
            vec3 source_radiance = ambient
                + direct_light * (single_scattering + multiple_scattering);
            luminance += transmittance * source_radiance * segment_alpha;
            transmittance *= step_transmittance;

            if (transmittance <= early_exit) {
                break;
            }
        }

        p += direction * step_size;
    }

    float alpha = clamp(1.0 - transmittance, 0.0, 1.0);
    vec3 cloud_color = alpha > EPSILON ? luminance / alpha : vec3(0.0);
    if (alpha > EPSILON && config.aerial.x > 0.0) {
        float horizon = pow(
            max(1.0 - clamp(direction.y, 0.0, 1.0), 0.0),
            max(config.aerial.y, EPSILON)
        );
        float relative_distance = ray_length / max(config.layer.y, 1.0);
        float distance_fade = 1.0 - exp(
            -max(config.aerial.z, 0.0) * relative_distance
        );
        float aerial_amount = clamp(config.aerial.x * horizon * distance_fade, 0.0, 1.0);
        cloud_color = mix(cloud_color, params.ambient_color, aerial_amount);
    }

    return vec4(cloud_color, alpha);
}

vec4 render_sky_direction(vec3 direction, float jitter) {
    if (direction.y <= 0.0) {
        return vec4(0.0);
    }

    vec3 camera_position = vec3(0.0, GROUND_RADIUS, 0.0);
    float start_distance = sphere_far_distance(
        camera_position,
        direction,
        cloud_bottom_radius()
    );
    float end_distance = sphere_far_distance(
        camera_position,
        direction,
        cloud_top_radius()
    );
    if (start_distance < 0.0 || end_distance <= start_distance) {
        return vec4(0.0);
    }

    vec3 start = camera_position + direction * start_distance;
    float ray_length = end_distance - start_distance;
    int step_count = int(clamp(floor(config.sampling.x + 0.5), 1.0, 160.0));
    return march_clouds(start, direction, ray_length, step_count, jitter);
}

vec2 oct_wrap(vec2 value) {
    vec2 signs = vec2(value.x >= 0.0 ? 1.0 : -1.0, value.y >= 0.0 ? 1.0 : -1.0);
    return (1.0 - abs(value.yx)) * signs;
}

vec3 oct_to_direction(vec2 encoded) {
    vec3 direction;
    direction.x = encoded.x - encoded.y;
    direction.y = encoded.x + encoded.y - 1.0;
    direction.z = 1.0 - abs(direction.x) - abs(direction.y);
    direction.xy = direction.z >= 0.0 ? direction.xy : oct_wrap(direction.xy);
    return normalize(direction);
}

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy) + ivec2(params.update_position);
    if (pixel.x >= int(params.texture_size.x) || pixel.y >= int(params.texture_size.y)) {
        return;
    }
    ivec2 blue_size = max(textureSize(blue_noise, 0), ivec2(1));
    ivec2 phased_pixel = pixel + ivec2(floor(params.pad1));
    ivec2 blue_coord = ivec2(
        ((phased_pixel.x % blue_size.x) + blue_size.x) % blue_size.x,
        ((phased_pixel.y % blue_size.y) + blue_size.y) % blue_size.y
    );
    float blue_value = texelFetch(blue_noise, blue_coord, 0).r;
    float jitter = mix(0.5, blue_value, clamp(config.sampling.z, 0.0, 1.0));

    vec2 uv = vec2(pixel) / params.texture_size;
    vec3 direction = oct_to_direction(uv).xzy;
    imageStore(current_image, pixel, render_sky_direction(direction, jitter));
}
