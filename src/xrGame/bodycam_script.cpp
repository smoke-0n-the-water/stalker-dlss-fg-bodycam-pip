#include "pch_script.h"
#include "bodycam_camera.h"
#include "bodycam_settings.h"
#include "Actor.h"
#include "ai_space.h"
#include "script_engine.h"

using namespace luabind;

static bool bodycam_request_motion_mode(int mode)
{
	return Bodycam::RequestMotionMode(mode);
}

static int bodycam_get_motion_mode()
{
	return static_cast<int>(Bodycam::GetMotionSelection().Requested());
}

static int bodycam_get_active_motion_mode()
{
	return static_cast<int>(Bodycam::GetMotionSelection().Active());
}

static Fvector bodycam_get_reference_weapon_position(LPCSTR section, bool ads)
{
	const auto& value = Bodycam::GetReferenceWeaponPosition(section);
	return ads ? value.ads : value.hip;
}
static Fvector bodycam_get_reference_weapon_position_baseline(LPCSTR section, bool ads)
{
	const auto& value = Bodycam::GetReferenceWeaponPositionBaseline(section);
	return ads ? value.ads : value.hip;
}
static bool bodycam_set_reference_weapon_position(LPCSTR section, bool ads, float x, float y, float z)
{
	Fvector value;
	value.set(x, y, z);
	return Bodycam::SetReferenceWeaponPosition(section, ads, value);
}

// Logs each unknown setting name once.
static void bodycam_report_unknown_setting(LPCSTR name)
{
	static xr_set<shared_str> reported;
	if (reported.insert(name).second)
		Msg("! bodycam: unknown setting '%s', using the script's fallback", name);
}

static float bodycam_get_float(LPCSTR name, float fallback)
{
	float value = fallback;
	if (!Bodycam::GetFloat(name, value))
		bodycam_report_unknown_setting(name);
	return value;
}

static bool bodycam_get_bool(LPCSTR name, bool fallback)
{
	bool value = fallback;
	if (!Bodycam::GetBool(name, value))
		bodycam_report_unknown_setting(name);
	return value;
}

static void bodycam_set_viewmodel_profile(float pos_x, float pos_y, float pos_z, float pitch, float yaw, float roll, float blend_speed)
{
	CActor* actor = Bodycam::CurrentActor();
	if (!actor)
		return;

	Fvector pos;
	pos.set(pos_x, pos_y, pos_z);
	Fvector rot;
	rot.set(yaw, pitch, roll);
	actor->cam_BodycamSetViewmodelProfile(pos, rot, blend_speed);
}

static void bodycam_clear_viewmodel_profile(float blend_speed)
{
	if (CActor* actor = Bodycam::CurrentActor())
		actor->cam_BodycamClearViewmodelProfile(blend_speed);
}

static object bodycam_get_bindings()
{
	lua_State* L = ai().script_engine().lua();
	object bindings = newtable(L);
	int index = 1;

	u32 count = 0;
	const Bodycam::FloatBinding* floats = Bodycam::GetFloatBindings(count);
	for (u32 i = 0; i < count; ++i)
	{
		const Bodycam::FloatBinding& binding = floats[i];
		object entry = newtable(L);
		entry["name"] = binding.name;
		entry["console_name"] = binding.console_name;
		entry["type"] = "float";
		entry["default"] = binding.default_value;
		entry["min"] = binding.min_value;
		entry["max"] = binding.max_value;
		bindings[index++] = entry;
	}

	const Bodycam::BoolBinding* bools = Bodycam::GetBoolBindings(count);
	for (u32 i = 0; i < count; ++i)
	{
		const Bodycam::BoolBinding& binding = bools[i];
		object entry = newtable(L);
		entry["name"] = binding.name;
		entry["console_name"] = binding.console_name;
		entry["type"] = "bool";
		entry["default"] = binding.default_value;
		bindings[index++] = entry;
	}

	return bindings;
}

#pragma optimize("s", on)
void Bodycam::script_register(lua_State* L)
{
	module(L, "bodycam")[def("request_motion_mode", &bodycam_request_motion_mode), def("get_motion_mode", &bodycam_get_motion_mode),
		def("get_active_motion_mode", &bodycam_get_active_motion_mode),
		def("get_reference_weapon_position", &bodycam_get_reference_weapon_position),
		def("get_reference_weapon_position_baseline", &bodycam_get_reference_weapon_position_baseline),
		def("has_reference_weapon_position_baseline", &Bodycam::HasReferenceWeaponPositionBaseline),
		def("restore_reference_weapon_position", &Bodycam::RestoreReferenceWeaponPosition),
		def("set_reference_weapon_position", &bodycam_set_reference_weapon_position),
		def("save_reference_weapon_position", &Bodycam::SaveReferenceWeaponPosition), def("get_float", &bodycam_get_float),
		def("set_float", &Bodycam::SetFloat), def("get_bool", &bodycam_get_bool), def("set_bool", &Bodycam::SetBool),
		def("apply_preset", &Bodycam::ApplyPreset), def("set_viewmodel_profile", &bodycam_set_viewmodel_profile),
		def("clear_viewmodel_profile", &bodycam_clear_viewmodel_profile), def("dump", &Bodycam::DumpState),
		def("get_bindings", &bodycam_get_bindings)];
}
