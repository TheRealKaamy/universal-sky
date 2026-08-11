@tool
extends Resource
class_name VolumetricClouds

## Ray-marched clouds for [StandardSkyMaterial]. Forward+ only.

const COMPUTE_SHADER:= preload("res://addons/universal-sky/src/sky/volumetric-clouds/volumetric_clouds.glsl")
const LARGE_SCALE_NOISE_PATH:= "res://addons/universal-sky/assets/textures/volumetric-clouds/perlworlnoise.tga"
const SMALL_SCALE_NOISE_PATH:= "res://addons/universal-sky/assets/textures/volumetric-clouds/worlnoise.bmp"
const WEATHER_NOISE_PATH:= "res://addons/universal-sky/assets/textures/volumetric-clouds/weather.bmp"
const BLUE_NOISE_PATH:= "res://addons/universal-sky/assets/textures/volumetric-clouds/blue_noise.bmp"

const ENABLE_PARAM:= &"enable_volumetric_clouds"
const BLEND_FROM_PARAM:= &"volumetric_clouds_blend_from_texture"
const BLEND_TO_PARAM:= &"volumetric_clouds_blend_to_texture"
const BLEND_AMOUNT_PARAM:= &"volumetric_clouds_blend_amount"
const INTENSITY_PARAM:= &"volumetric_clouds_intensity"
const RENDERING_METHOD_PATH:= &"rendering/renderer/rendering_method"
const FORWARD_PLUS_RENDER_METHOD_NAME:= "forward_plus"

enum QualityPreset {
	PERFORMANCE,
	BALANCED,
	HIGH,
	ULTRA,
	CUSTOM,
}

@export_group("Clouds")
@export
var enabled: bool = false:
	set(value):
		if enabled == value:
			return
		enabled = value
		if enabled:
			request_full_update()
			if is_instance_valid(_sky_material):
				_connect_frame_update()
				_queue_rebuild()
		else:
			_disable_clouds()

## Wind direction in degrees. Zero points along +X.
@export_custom(PROPERTY_HINT_RANGE, "-180,180,0.1,radians_as_degrees")
var wind_direction: float = 0.0:
	set(value):
		wind_direction = value

## Artistic wind speed.
@export_range(0.0, 120.0, 0.1, "or_greater", "suffix:m/s")
var wind_speed: float = 1.0:
	set(value):
		wind_speed = value

@export_range(0.0, 0.2, 0.001, "or_greater")
var density: float = 0.05:
	set(value):
		density = value

@export_range(0.0, 1.0, 0.01)
var coverage: float = 0.25:
	set(value):
		coverage = value

## Offsets the weather animation.
@export
var time_offset: float = 0.0:
	set(value):
		time_offset = value

@export_range(0.0, 4.0, 0.01, "or_greater")
var intensity: float = 1.0:
	set(value):
		intensity = value
		_apply_intensity()

@export_group("Cloud Layer")
## Height of the bottom of the cloud layer above the planet surface.
@export_range(100.0, 20000.0, 10.0, "or_greater", "suffix:m")
var base_altitude: float = 1500.0:
	set(value):
		base_altitude = value
		_settings_changed()

## Vertical thickness of the cloud layer.
@export_range(100.0, 20000.0, 10.0, "or_greater", "suffix:m")
var layer_thickness: float = 2500.0:
	set(value):
		layer_thickness = value
		_settings_changed()

@export_group("Shape")
@export_subgroup("Noise Scale")
@export_range(0.000001, 0.001, 0.000001, "or_greater")
var weather_scale: float = 0.00006:
	set(value):
		weather_scale = value
		_settings_changed()

@export_range(0.000001, 0.001, 0.000001, "or_greater")
var base_shape_scale: float = 0.00008:
	set(value):
		base_shape_scale = value
		_settings_changed()

@export_range(0.00001, 0.01, 0.00001, "or_greater")
var detail_scale: float = 0.001:
	set(value):
		detail_scale = value
		_settings_changed()

## Height fraction where detail noise finishes changing from erosion to wispy inversion.
@export_range(0.01, 1.0, 0.01)
var detail_inversion_height: float = 0.25:
	set(value):
		detail_inversion_height = value
		_settings_changed()

@export_subgroup("Erosion")
@export_range(0.0, 1.0, 0.01)
var erosion_strength: float = 0.4:
	set(value):
		erosion_strength = value
		_settings_changed()

@export_range(0.0, 1.0, 0.01)
var erosion_height_influence: float = 1.0:
	set(value):
		erosion_height_influence = value
		_settings_changed()

@export_range(0.1, 4.0, 0.01, "or_greater")
var bottom_density_power: float = 1.3:
	set(value):
		bottom_density_power = value
		_settings_changed()

@export_range(0.1, 4.0, 0.01, "or_greater")
var top_density_power: float = 0.5:
	set(value):
		top_density_power = value
		_settings_changed()

@export_group("Lighting")
@export_range(0.0, 8.0, 0.01, "or_greater")
var direct_light_multiplier: float = 1.0:
	set(value):
		direct_light_multiplier = value

@export_range(0.0, 8.0, 0.01, "or_greater")
var ambient_light_multiplier: float = 0.22:
	set(value):
		ambient_light_multiplier = value

@export_range(0.0, 8.0, 0.01, "or_greater")
var ground_light_multiplier: float = 0.08:
	set(value):
		ground_light_multiplier = value

@export_subgroup("Phase Function")
@export_range(-0.95, 0.95, 0.01)
var forward_scattering: float = 0.6:
	set(value):
		forward_scattering = value
		_settings_changed()

@export_range(-0.95, 0.95, 0.01)
var backward_scattering: float = -0.2:
	set(value):
		backward_scattering = value
		_settings_changed()

@export_range(0.0, 1.0, 0.01)
var backward_scattering_weight: float = 0.2:
	set(value):
		backward_scattering_weight = value
		_settings_changed()

@export_subgroup("Multiple Scattering")
## Adds a broad second scattering order without another light march.
@export_range(0.0, 2.0, 0.01, "or_greater")
var multiple_scattering_intensity: float = 0.35:
	set(value):
		multiple_scattering_intensity = value
		_settings_changed()

@export_range(0.0, 1.0, 0.01)
var multiple_scattering_extinction: float = 0.35:
	set(value):
		multiple_scattering_extinction = value
		_settings_changed()

@export_subgroup("Ambient Occlusion")
@export_range(0.0, 8.0, 0.01, "or_greater")
var ambient_occlusion_strength: float = 2.0:
	set(value):
		ambient_occlusion_strength = value
		_settings_changed()

@export_range(0.0, 1.0, 0.01)
var minimum_ambient_visibility: float = 0.3:
	set(value):
		minimum_ambient_visibility = value
		_settings_changed()

@export_subgroup("Aerial Perspective")
@export_range(0.0, 1.0, 0.01)
var aerial_perspective_strength: float = 0.35:
	set(value):
		aerial_perspective_strength = value
		_settings_changed()

@export_range(0.1, 8.0, 0.01, "or_greater")
var aerial_perspective_horizon_power: float = 2.0:
	set(value):
		aerial_perspective_horizon_power = value
		_settings_changed()

@export_range(0.0, 4.0, 0.01, "or_greater")
var aerial_perspective_distance: float = 0.12:
	set(value):
		aerial_perspective_distance = value
		_settings_changed()

@export_group("Performance")
## Changes ray samples only. Texture resolution and update cadence stay independent.
@export_enum("Performance", "Balanced", "High", "Ultra", "Custom")
var quality_preset: int = QualityPreset.HIGH:
	set(value):
		quality_preset = clampi(value, QualityPreset.PERFORMANCE, QualityPreset.CUSTOM)
		_applying_quality_preset = true
		match quality_preset:
			QualityPreset.PERFORMANCE:
				view_sample_count = 64
				light_sample_count = 3
			QualityPreset.BALANCED:
				view_sample_count = 96
				light_sample_count = 4
			QualityPreset.HIGH:
				view_sample_count = 128
				light_sample_count = 6
			QualityPreset.ULTRA:
				view_sample_count = 160
				light_sample_count = 8
		_applying_quality_preset = false
		_settings_changed()
		notify_property_list_changed()

@export_range(16, 160, 1)
var view_sample_count: int = 128:
	set(value):
		view_sample_count = clampi(value, 16, 160)
		if not _applying_quality_preset and quality_preset != QualityPreset.CUSTOM:
			quality_preset = QualityPreset.CUSTOM
		else:
			_settings_changed()

@export_range(1, 8, 1)
var light_sample_count: int = 6:
	set(value):
		light_sample_count = clampi(value, 1, 8)
		if not _applying_quality_preset and quality_preset != QualityPreset.CUSTOM:
			quality_preset = QualityPreset.CUSTOM
		else:
			_settings_changed()

@export_subgroup("Optimization")
## Lossless at zero. Raising this removes regions with very low weather coverage.
@export_range(0.0, 0.25, 0.001)
var weather_skip_threshold: float = 0.0:
	set(value):
		weather_skip_threshold = value
		_settings_changed()

## Lossless at zero. Raising this removes tenuous cloud density before detail erosion.
@export_range(0.0, 0.25, 0.001)
var density_skip_threshold: float = 0.0:
	set(value):
		density_skip_threshold = value
		_settings_changed()

@export_range(0.0, 0.1, 0.001)
var early_exit_transmittance: float = 0.01:
	set(value):
		early_exit_transmittance = value
		_settings_changed()

@export_range(0.0, 1.0, 0.01)
var blue_noise_jitter: float = 1.0:
	set(value):
		blue_noise_jitter = value
		_settings_changed()
## Frames per full update. Lower values react faster but cost more per frame.
@export_enum("Very Fast (4):4", "Fast (16):16", "Default (64):64", "Performance (256):256")
var frames_to_update: int = 64:
	set(value):
		frames_to_update = value
		_queue_rebuild()

## Cloud texture resolution.
@export_range(32, 2048, 32)
var texture_size: int = 512:
	set(value):
		texture_size = value
		_queue_rebuild()


class RenderResourceCleanup:
	var rd: RenderingDevice
	var rids: Array[RID] = []

	func free_rids() -> void:
		if rd == null:
			return
		for rid in rids:
			if rid.is_valid():
				rd.free_rid(rid)


class FrameData:
	var wind_direction:= Vector2.RIGHT
	var wind_speed: float = 1.0
	var density: float = 0.05
	var coverage: float = 0.25
	var time_offset: float = 0.0
	var ground_color:= Color(0.25, 0.25, 0.25)
	var light_direction:= Vector3.UP
	var light_energy: float = 1.0
	var light_color:= Color.WHITE
	var ambient_color:= Color(0.35, 0.45, 0.65)
	var time: float = 0.0
	var cloud_position:= Vector2.ZERO
	var detail_position:= Vector2.ZERO
	var weather_position:= Vector2.ZERO


var _sky_material: ShaderMaterial
var _frame_data:= FrameData.new()
var _update_position:= Vector2i.ZERO
var _update_region_size: int = 64
var _workgroup_count: int = 8
var _frame: int = 0
var _blue_noise_phase:= Vector2i.ZERO
var _texture_to_update: int = 0
var _texture_to_blend_from: int = 1
var _texture_to_blend_to: int = 2
var _textures: Array[Texture2DRD] = []
var _can_run: bool = false
var _needs_full_update: bool = true
var _rebuild_queued: bool = false
var _warned_unsupported_renderer: bool = false
var _large_scale_noise: Texture3D
var _small_scale_noise: Texture3D
var _weather_noise: Texture2D
var _blue_noise: Texture2D
var _settings_dirty: bool = true
var _applying_quality_preset: bool = false

# Render-thread data.
var _rd: RenderingDevice
var _shader_rid:= RID()
var _pipeline_rid:= RID()
var _texture_rids: Array[RID] = [RID(), RID(), RID()]
var _texture_sets: Array[RID] = [RID(), RID(), RID()]
var _noise_uniform_set:= RID()
var _noise_sampler:= RID()
var _settings_buffer:= RID()
var _settings_uniform_set:= RID()


func _init() -> void:
	call_deferred("_finish_initialization")


func _validate_property(property: Dictionary) -> void:
	if quality_preset != QualityPreset.CUSTOM and property.name in [
			"view_sample_count",
			"light_sample_count",
		]:
		property.usage &= ~PROPERTY_USAGE_EDITOR


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_can_run = false
		_queue_render_resource_cleanup()


func attach(p_sky_material: ShaderMaterial) -> void:
	if _sky_material == p_sky_material:
		_apply_material_parameters()
		return
	detach()
	_sky_material = p_sky_material
	_apply_material_parameters()
	if enabled:
		_connect_frame_update()
		_queue_rebuild()


func detach() -> void:
	_disconnect_frame_update()
	if is_instance_valid(_sky_material):
		_clear_material_bindings(_sky_material)
	_sky_material = null
	_can_run = false
	_queue_render_resource_cleanup()


func _disable_clouds() -> void:
	_disconnect_frame_update()
	_can_run = false
	if is_instance_valid(_sky_material):
		_clear_material_bindings(_sky_material)
	_queue_render_resource_cleanup()


## Updates cloud lighting. Colors must be in linear space.
func set_lighting(
		p_light_direction: Vector3,
		p_light_color: Color,
		p_light_energy: float,
		p_ambient_color: Color,
		p_ground_color: Color
	) -> void:
	_frame_data.light_direction = p_light_direction.normalized() \
		if not p_light_direction.is_zero_approx() else Vector3.UP
	_frame_data.light_color = p_light_color
	_frame_data.light_energy = maxf(p_light_energy, 0.0)
	_frame_data.ambient_color = p_ambient_color
	_frame_data.ground_color = p_ground_color


func request_full_update() -> void:
	_needs_full_update = true


func _settings_changed() -> void:
	_settings_dirty = true


func _queue_render_resource_cleanup() -> void:
	if _rd == null:
		return
	var cleanup:= RenderResourceCleanup.new()
	cleanup.rd = _rd
	cleanup.rids.append_array(_texture_sets)
	cleanup.rids.append_array(_texture_rids)
	cleanup.rids.append(_noise_uniform_set)
	cleanup.rids.append(_noise_sampler)
	cleanup.rids.append(_settings_uniform_set)
	cleanup.rids.append(_settings_buffer)
	cleanup.rids.append(_pipeline_rid)
	cleanup.rids.append(_shader_rid)
	_texture_sets = [RID(), RID(), RID()]
	_texture_rids = [RID(), RID(), RID()]
	_noise_uniform_set = RID()
	_noise_sampler = RID()
	_settings_uniform_set = RID()
	_settings_buffer = RID()
	_pipeline_rid = RID()
	_shader_rid = RID()
	_textures.clear()
	RenderingServer.call_on_render_thread(cleanup.free_rids)


## Uploads one immutable settings snapshot at a full texture-generation boundary.
func _upload_pending_settings() -> void:
	if not _settings_dirty or not _can_run:
		return
	var settings_data:= _fill_settings_buffer().to_byte_array()
	_settings_dirty = false
	RenderingServer.call_on_render_thread(_update_settings_buffer.bind(settings_data))


func _update_settings_buffer(settings_data: PackedByteArray) -> void:
	if not _can_run or _rd == null or not _settings_buffer.is_valid():
		return
	_rd.buffer_update(_settings_buffer, 0, settings_data.size(), settings_data)


func _finish_initialization() -> void:
	_update_performance_values()
	if enabled and is_instance_valid(_sky_material):
		_connect_frame_update()
	if enabled and is_instance_valid(_sky_material) and not _can_run and not _rebuild_queued:
		_queue_rebuild()


func _connect_frame_update() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(_update_sky):
		RenderingServer.frame_pre_draw.connect(_update_sky)


func _disconnect_frame_update() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_update_sky):
		RenderingServer.frame_pre_draw.disconnect(_update_sky)


func _renderer_is_supported() -> bool:
	return str(ProjectSettings.get_setting_with_override(RENDERING_METHOD_PATH)) \
		== FORWARD_PLUS_RENDER_METHOD_NAME


func _queue_rebuild() -> void:
	_update_performance_values()
	_can_run = false
	_apply_enabled()
	_needs_full_update = true
	if not enabled:
		return
	if is_instance_valid(_sky_material):
		_clear_material_bindings(_sky_material)
	if _rebuild_queued or not is_instance_valid(_sky_material):
		return
	if not _renderer_is_supported():
		_apply_enabled()
		if not _warned_unsupported_renderer:
			push_warning("VolumetricClouds requires the Forward+ renderer.")
			_warned_unsupported_renderer = true
		return
	_load_noise_textures()
	if not is_instance_valid(_large_scale_noise) \
			or not is_instance_valid(_small_scale_noise) \
			or not is_instance_valid(_weather_noise) \
			or not is_instance_valid(_blue_noise):
		push_error("VolumetricClouds could not load its noise textures.")
		return
	_rebuild_queued = true
	var settings_data:= _fill_settings_buffer().to_byte_array()
	_settings_dirty = false
	RenderingServer.call_on_render_thread.call_deferred(
		_initialize_compute.bind(settings_data)
	)


func _load_noise_textures() -> void:
	# Load before the render thread asks for texture RIDs.
	if not is_instance_valid(_large_scale_noise):
		_large_scale_noise = load(LARGE_SCALE_NOISE_PATH)
	if not is_instance_valid(_small_scale_noise):
		_small_scale_noise = load(SMALL_SCALE_NOISE_PATH)
	if not is_instance_valid(_weather_noise):
		_weather_noise = load(WEATHER_NOISE_PATH)
	if not is_instance_valid(_blue_noise):
		_blue_noise = load(BLUE_NOISE_PATH)


func _update_performance_values() -> void:
	var frame_grid_size:= maxi(1, int(sqrt(float(frames_to_update))))
	_update_region_size = maxi(
		8,
		floori(float(texture_size) * pow(float(frame_grid_size), -1.0))
	)
	if texture_size % frame_grid_size != 0:
		texture_size = _update_region_size * frame_grid_size
	_workgroup_count = int(ceil(float(_update_region_size) / 8.0))


func _apply_material_parameters() -> void:
	_apply_enabled()
	_apply_intensity()
	if not is_instance_valid(_sky_material):
		return
	if not enabled or not _can_run or _textures.size() != 3:
		_clear_material_bindings(_sky_material)
		return
	_sky_material.set_shader_parameter(BLEND_FROM_PARAM, _textures[_texture_to_blend_from])
	_sky_material.set_shader_parameter(BLEND_TO_PARAM, _textures[_texture_to_blend_to])
	_sky_material.set_shader_parameter(BLEND_AMOUNT_PARAM, 0.0)


func _clear_material_bindings(p_material: ShaderMaterial) -> void:
	p_material.set_shader_parameter(ENABLE_PARAM, false)
	p_material.set_shader_parameter(BLEND_FROM_PARAM, null)
	p_material.set_shader_parameter(BLEND_TO_PARAM, null)
	p_material.set_shader_parameter(BLEND_AMOUNT_PARAM, 0.0)


func _apply_enabled() -> void:
	if is_instance_valid(_sky_material):
		_sky_material.set_shader_parameter(
			ENABLE_PARAM,
			enabled and _renderer_is_supported() and _can_run and _textures.size() == 3
		)


func _apply_intensity() -> void:
	if is_instance_valid(_sky_material):
		_sky_material.set_shader_parameter(INTENSITY_PARAM, intensity)


func _update_sky() -> void:
	if not enabled or not _can_run or not is_instance_valid(_sky_material):
		return
	_apply_enabled()

	if _needs_full_update:
		_needs_full_update = false
		_upload_pending_settings()
		_initialize_sky_textures()

	if _frame >= frames_to_update:
		_texture_to_update = (_texture_to_update + 1) % 3
		_upload_pending_settings()
		_blue_noise_phase = Vector2i(
			(_blue_noise_phase.x + 37) % 128,
			(_blue_noise_phase.y + 71) % 128
		)
		_texture_to_blend_from = (_texture_to_blend_from + 1) % 3
		_texture_to_blend_to = (_texture_to_blend_to + 1) % 3
		_update_frame_data()
		_sky_material.set_shader_parameter(
			BLEND_FROM_PARAM,
			_textures[_texture_to_blend_from]
		)
		_sky_material.set_shader_parameter(
			BLEND_TO_PARAM,
			_textures[_texture_to_blend_to]
		)
		_frame = 0

	_sky_material.set_shader_parameter(
		BLEND_AMOUNT_PARAM,
		float(_frame) / float(frames_to_update)
	)
	RenderingServer.call_on_render_thread(_render_tile.bind(_texture_to_update))
	_advance_update_position()
	_frame += 1


func _initialize_sky_textures() -> void:
	_update_frame_data()
	# Prime both textures used by the first blend.
	for i in range(frames_to_update * 2):
		_update_sky()


func _advance_update_position() -> void:
	_update_position.x += _update_region_size
	if _update_position.x >= texture_size:
		_update_position.x = 0
		_update_position.y += _update_region_size
	if _update_position.y >= texture_size:
		_update_position = Vector2i.ZERO


func _update_frame_data() -> void:
	_frame_data.wind_direction = Vector2.from_angle(wind_direction).normalized()
	_frame_data.wind_speed = wind_speed
	_frame_data.density = density
	_frame_data.coverage = coverage
	_frame_data.time_offset = time_offset

	var now:= Time.get_ticks_msec() / 1000.0
	var delta:= now - _frame_data.time
	var weather_delta:= delta * 0.001 + 0.005 * _frame_data.time_offset
	_frame_data.time = now
	_frame_data.detail_position += delta * _frame_data.wind_direction
	_frame_data.cloud_position += delta * _frame_data.wind_direction * _frame_data.wind_speed
	_frame_data.weather_position += weather_delta \
		* _frame_data.wind_direction * _frame_data.wind_speed


func _fill_settings_buffer() -> PackedFloat32Array:
	var values:= PackedFloat32Array()
	values.resize(32)
	values[0] = base_altitude
	values[1] = layer_thickness
	values[2] = weather_skip_threshold
	values[3] = density_skip_threshold
	values[4] = weather_scale
	values[5] = base_shape_scale
	values[6] = detail_scale
	values[7] = detail_inversion_height
	values[8] = erosion_strength
	values[9] = erosion_height_influence
	values[10] = bottom_density_power
	values[11] = top_density_power
	values[12] = forward_scattering
	values[13] = backward_scattering
	values[14] = backward_scattering_weight
	values[15] = multiple_scattering_intensity
	values[16] = multiple_scattering_extinction
	values[17] = ambient_occlusion_strength
	values[18] = minimum_ambient_visibility
	values[19] = early_exit_transmittance
	values[20] = view_sample_count
	values[21] = light_sample_count
	values[22] = blue_noise_jitter
	values[23] = 0.0
	values[24] = aerial_perspective_strength
	values[25] = aerial_perspective_horizon_power
	values[26] = aerial_perspective_distance
	values[27] = 0.0
	values[28] = 0.0
	values[29] = 0.0
	values[30] = 0.0
	values[31] = 0.0
	return values


func _fill_push_constants() -> PackedFloat32Array:
	var values:= PackedFloat32Array()
	values.resize(32)
	values[0] = texture_size
	values[1] = texture_size
	values[2] = _update_position.x
	values[3] = _update_position.y
	values[4] = _frame_data.cloud_position.x
	values[5] = _frame_data.cloud_position.y
	values[6] = _frame_data.detail_position.x
	values[7] = _frame_data.detail_position.y
	values[8] = _frame_data.weather_position.x
	values[9] = _frame_data.weather_position.y
	values[10] = _blue_noise_phase.x
	values[11] = _blue_noise_phase.y
	values[12] = _frame_data.ground_color.r
	values[13] = _frame_data.ground_color.g
	values[14] = _frame_data.ground_color.b
	values[15] = ground_light_multiplier
	values[16] = _frame_data.light_direction.x
	values[17] = _frame_data.light_direction.y
	values[18] = _frame_data.light_direction.z
	values[19] = _frame_data.light_energy
	values[20] = _frame_data.light_color.r
	values[21] = _frame_data.light_color.g
	values[22] = _frame_data.light_color.b
	values[23] = direct_light_multiplier
	values[24] = _frame_data.ambient_color.r
	values[25] = _frame_data.ambient_color.g
	values[26] = _frame_data.ambient_color.b
	values[27] = ambient_light_multiplier
	values[28] = _frame_data.density
	values[29] = _frame_data.coverage
	values[30] = _frame_data.time
	values[31] = 0.0
	return values


# Render-thread code.

func _fail_compute_initialization(message: String) -> void:
	push_error(message)
	_cleanup_render_resources()


func _initialize_compute(settings_data: PackedByteArray) -> void:
	_cleanup_render_resources()
	_rebuild_queued = false
	if not enabled or not is_instance_valid(_sky_material) or not _renderer_is_supported():
		return

	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return

	var shader_spirv: RDShaderSPIRV = COMPUTE_SHADER.get_spirv()
	_shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	if not _shader_rid.is_valid():
		_fail_compute_initialization("VolumetricClouds could not create its compute shader.")
		return
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	if not _pipeline_rid.is_valid():
		_fail_compute_initialization("VolumetricClouds could not create its compute pipeline.")
		return

	_noise_uniform_set = _create_noise_uniform_set()
	if not _noise_uniform_set.is_valid():
		_fail_compute_initialization("VolumetricClouds could not bind its noise textures.")
		return
	_settings_uniform_set = _create_settings_uniform_set(settings_data)
	if not _settings_uniform_set.is_valid():
		_fail_compute_initialization("VolumetricClouds could not bind its settings buffer.")
		return

	var texture_format:= RDTextureFormat.new()
	texture_format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	texture_format.width = texture_size
	texture_format.height = texture_size
	texture_format.depth = 1
	texture_format.array_layers = 1
	texture_format.mipmaps = 1
	texture_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)
	if Engine.is_editor_hint():
		texture_format.usage_bits |= RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	_textures.clear()
	for i in range(3):
		_texture_rids[i] = _rd.texture_create(texture_format, RDTextureView.new(), [])
		if not _texture_rids[i].is_valid():
			_fail_compute_initialization("VolumetricClouds could not create an output texture.")
			return
		_rd.texture_clear(_texture_rids[i], Color.TRANSPARENT, 0, 1, 0, 1)
		_texture_sets[i] = _create_output_uniform_set(_texture_rids[i])
		if not _texture_sets[i].is_valid():
			_fail_compute_initialization("VolumetricClouds could not bind an output texture.")
			return
		var texture:= Texture2DRD.new()
		texture.texture_rd_rid = _texture_rids[i]
		_textures.push_back(texture)

	_frame = 0
	_texture_to_update = 0
	_texture_to_blend_from = 1
	_texture_to_blend_to = 2
	_update_position = Vector2i.ZERO
	_blue_noise_phase = Vector2i.ZERO
	_needs_full_update = true
	_can_run = true


func _create_output_uniform_set(texture_rid: RID) -> RID:
	var uniform:= RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rid)
	return _rd.uniform_set_create([uniform], _shader_rid, 0)


func _create_settings_uniform_set(settings_data: PackedByteArray) -> RID:
	_settings_buffer = _rd.uniform_buffer_create(settings_data.size(), settings_data)
	if not _settings_buffer.is_valid():
		return RID()
	var uniform:= RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(_settings_buffer)
	return _rd.uniform_set_create([uniform], _shader_rid, 2)


func _create_noise_uniform_set() -> RID:
	var sampler_state:= RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_noise_sampler = _rd.sampler_create(sampler_state)

	var textures: Array[Texture] = [
		_large_scale_noise,
		_small_scale_noise,
		_weather_noise,
		_blue_noise,
	]
	var uniforms: Array[RDUniform] = []
	for i in range(textures.size()):
		var texture_rid:= RenderingServer.texture_get_rd_texture(textures[i].get_rid())
		if not texture_rid.is_valid():
			return RID()
		var uniform:= RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform.binding = i
		uniform.add_id(_noise_sampler)
		uniform.add_id(texture_rid)
		uniforms.push_back(uniform)
	return _rd.uniform_set_create(uniforms, _shader_rid, 1)


func _render_tile(texture_index: int) -> void:
	if not _can_run or _rd == null:
		return
	var compute_list:= _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	_rd.compute_list_bind_uniform_set(compute_list, _texture_sets[texture_index], 0)
	_rd.compute_list_bind_uniform_set(compute_list, _noise_uniform_set, 1)
	_rd.compute_list_bind_uniform_set(compute_list, _settings_uniform_set, 2)
	var push_constants:= _fill_push_constants()
	_rd.compute_list_set_push_constant(
		compute_list,
		push_constants.to_byte_array(),
		push_constants.size() * 4
	)
	_rd.compute_list_dispatch(compute_list, _workgroup_count, _workgroup_count, 1)
	_rd.compute_list_end()


func _cleanup_render_resources() -> void:
	_can_run = false
	if _rd == null:
		return
	for i in range(3):
		if _texture_sets[i].is_valid():
			_rd.free_rid(_texture_sets[i])
			_texture_sets[i] = RID()
		if _texture_rids[i].is_valid():
			_rd.free_rid(_texture_rids[i])
			_texture_rids[i] = RID()
	if _noise_uniform_set.is_valid():
		_rd.free_rid(_noise_uniform_set)
		_noise_uniform_set = RID()
	if _noise_sampler.is_valid():
		_rd.free_rid(_noise_sampler)
		_noise_sampler = RID()
	if _settings_uniform_set.is_valid():
		_rd.free_rid(_settings_uniform_set)
		_settings_uniform_set = RID()
	if _settings_buffer.is_valid():
		_rd.free_rid(_settings_buffer)
		_settings_buffer = RID()
	if _pipeline_rid.is_valid():
		_rd.free_rid(_pipeline_rid)
		_pipeline_rid = RID()
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)
		_shader_rid = RID()
	_textures.clear()
