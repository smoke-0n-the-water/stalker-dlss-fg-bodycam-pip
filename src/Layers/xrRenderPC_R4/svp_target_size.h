#pragma once

namespace svp
{
struct TargetSettings
{
	bool upscale;
	bool flatWindow;
	bool adaptiveGrow;
	float adaptiveResolution;
	float supersample;
	float renderScale;
	// Scope Resolution: share of the on-screen lens size in display px, 0 = the older sizing above.
	float scopeResolution;
};

struct TargetFrame
{
	unsigned baseHeight;
	unsigned displayHeight;
	float disc;
	float panelAspect;
	float displayDisc; // the lens disc in display px
	unsigned displayCap; // display height, the largest scope image
};

struct TargetSize
{
	unsigned width;
	unsigned height;
};

inline unsigned RenderExtent(const TargetSettings& settings, const TargetFrame& frame)
{
	// Scope Resolution sizes from the lens as shown, not from the render-size composite: the upscaler
	// reconstructs the lens, so detail above render size still reaches the screen. It replaces the
	// adaptive margin. Flat windows keep their panel sizing. r__svp_supersample renders it larger than
	// the lens on screen (SSAA): the lens shader averages the texels each screen pixel covers, so thin
	// foliage stays stable while the magnified view moves, with no temporal blur. The cap grows with it.
	if (!settings.upscale && !settings.flatWindow && settings.scopeResolution > 0.f && frame.displayDisc > 1.0f)
	{
		float ss = settings.supersample;
		if (ss < 1.0f) ss = 1.0f;
		if (ss > 2.0f) ss = 2.0f;
		unsigned want = unsigned(frame.displayDisc * settings.scopeResolution * ss) & ~1u;
		if (want < 256) want = 256;
		const unsigned cap = unsigned(frame.displayCap * ss) & ~1u;
		if (cap >= 256 && want > cap) want = cap;
		return want;
	}
	if (!settings.upscale)
	{
		unsigned base = frame.baseHeight;
		if (settings.flatWindow && frame.disc > 1.0f)
		{
			unsigned want = unsigned(frame.disc) & ~1u;
			const unsigned cap = frame.displayHeight & ~1u;
			if (want > cap) want = cap;
			if (want > base) base = want;
		}
		else if (settings.adaptiveResolution > 0.f)
		{
			if (frame.disc > 1.0f)
			{
				unsigned want = unsigned(frame.disc * settings.adaptiveResolution) & ~1u;
				if (want < 256) want = 256;
				if (settings.adaptiveGrow)
				{
					const unsigned cap = frame.displayHeight & ~1u;
					base = (want > cap) ? cap : want;
				}
				else if (want < base)
					base = want;
			}
		}
		float ss = settings.supersample;
		if (ss < 1.0f) ss = 1.0f;
		if (ss > 2.0f) ss = 2.0f;
		if (base == frame.baseHeight && ss <= 1.0f)
			return frame.baseHeight;
		unsigned e = unsigned(base * ss) & ~1u;
		return (e < 2) ? 2 : e;
	}
	float eff = settings.renderScale;
	if (eff < 0.5f) eff = 0.5f;
	if (eff > 1.0f) eff = 1.0f;
	if (eff >= 1.0f)
		return frame.baseHeight;
	unsigned e = unsigned(frame.baseHeight * eff) & ~1u;
	if (e < 2) e = 2;
	return e;
}

// Can the live target serve this size? Building one is a whole second render target set and a
// hitch, and Scope Resolution asks for a different size per lens. grow = keep any target at least
// as big (the scope then renders at that size: sharper, costs GPU like the largest lens seen);
// otherwise only the exact size. Square targets only: the scope camera takes its aspect from the
// wanted size (svp_camera.cpp), so a flat panel target must keep its exact shape.
inline bool Reusable(const TargetSize& have, const TargetSize& want, bool grow)
{
	const bool square = have.width == have.height && want.width == want.height;
	if (grow && square)
		return have.width >= want.width;
	return have.width == want.width && have.height == want.height;
}
inline TargetSize Size(const TargetSettings& settings, const TargetFrame& frame)
{
	// Round up to avoid reallocating the chain for small changes in lens size.
	unsigned side = (RenderExtent(settings, frame) + 31u) & ~31u;
	if (side < 64) side = 64;
	TargetSize result{side, side};
	if (settings.flatWindow && frame.panelAspect > 1.01f)
	{
		result.height = (unsigned(side / frame.panelAspect) + 31u) & ~31u;
		if (result.height < 64) result.height = 64;
	}
	return result;
}
}
