#pragma once
#include "constants.h"
#include "recoil_pose.h"
#include <algorithm>
#include <cmath>
#include <string_view>

namespace BodycamReference
{
// Recoil family from the weapon's `kind` config value.
enum class RecoilFamily
{
	Unknown,
	Pistol,
	Smg,
	Rifle,
	Shotgun,
	Sniper
};

inline RecoilFamily RecoilFamilyFromKind(std::string_view kind)
{
	if (kind == "w_pistol")
		return RecoilFamily::Pistol;
	if (kind == "w_smg")
		return RecoilFamily::Smg;
	if (kind == "w_rifle" || kind == "w_lmg")
		return RecoilFamily::Rifle;
	if (kind == "w_shotgun")
		return RecoilFamily::Shotgun;
	if (kind == "w_sniper")
		return RecoilFamily::Sniper;
	return RecoilFamily::Unknown;
}

struct RecoilAngles
{
	// CWeapon::CameraRecoil stores these in radians after config conversion.
	double dispersionRadians = 0;
	double maxVerticalRadians = 0;
};
struct RecoilMetadata
{
	RecoilFamily family = RecoilFamily::Unknown;
	RecoilAngles hip, aim;
};
struct RecoilPolicy
{
	double hipScale = 1, aimScale = 1;

	double GunPoseScale(bool aiming) const { return aiming ? aimScale : hipScale; }
};

inline double RecoilBudgetFraction(RecoilFamily family)
{
	// Typical dispersion / maximum vertical recoil ratio of the family's installed weapons, rounded.
	// A weapon at or above it keeps the full gun recoil; lower ratios scale it down to .8.
	switch (family)
	{
	case RecoilFamily::Pistol: return .04;
	case RecoilFamily::Smg: return .01;
	case RecoilFamily::Rifle: return .01;
	case RecoilFamily::Shotgun: return .12;
	case RecoilFamily::Sniper: return .05;
	default: return 0;
	}
}

inline double RecoilGunPoseScale(const RecoilAngles& angles, double budget)
{
	if (!std::isfinite(budget) || budget <= 0 || !std::isfinite(angles.dispersionRadians) || angles.dispersionRadians < 0 ||
		angles.dispersionRadians > kPi || !std::isfinite(angles.maxVerticalRadians) || angles.maxVerticalRadians <= 0 ||
		angles.maxVerticalRadians > kPi)
		return 1; // Unavailable or malformed metadata keeps the unscaled gun pose.
	const double fraction = angles.dispersionRadians / angles.maxVerticalRadians;
	return .8 + .2 * std::clamp(fraction / budget, 0., 1.);
}

inline RecoilPolicy BuildRecoilPolicy(const RecoilMetadata& metadata)
{
	const double budget = RecoilBudgetFraction(metadata.family);
	return { RecoilGunPoseScale(metadata.hip, budget), RecoilGunPoseScale(metadata.aim, budget) };
}

inline RecoilPose ScaleRecoilGunPose(RecoilPose pose, double scale)
{
	// Scales the procedural gun recoil only.
	if (scale == 1)
		return pose;
	pose.rotation.pitch *= scale;
	pose.rotation.yaw *= scale;
	pose.rotation.roll *= scale;
	for (auto& value : pose.location)
		value *= scale;
	return pose;
}
}
