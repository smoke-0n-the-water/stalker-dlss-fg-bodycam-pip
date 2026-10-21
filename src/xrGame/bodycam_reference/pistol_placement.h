#pragma once
#include "transform.h"

namespace BodycamReference
{
// Hip position of the source Glock17 relative to its M4: the difference of their ik_hand_gun
// bones plus pose offsets, measured from the shared FP_Camera socket, in camera-local metres
// with -Z forward. Only the hip translation changes; sights and action clips keep their own.
inline Vector PistolHipTranslation(bool pistol)
{
	const double weight = pistol ? 1. : 0.;
	return { -.01665852 * weight, .06854060 * weight, -.22434653 * weight };
}
}
