#pragma once
#include <string_view>
namespace BodycamReference
{
// The crouch additive script layer also lowers the gun when looking up. Reference poses pitch
// and stance itself, so the layer is not applied while Reference drives the hands.
inline bool ApplyScriptLayer(bool reference, std::string_view name)
{
	return !reference || (name != "liz\\liz_hands_crouch_additive.anm" && name != "liz/liz_hands_crouch_additive.anm");
}
}