// dxRender_Visual.cpp: implementation of the dxRender_Visual class.
//
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#pragma hdrstop

#ifndef _EDITOR
#	include "../../xrEngine/render.h"
#endif // #ifndef _EDITOR

#include "fbasicvisual.h"
#include "../../xrEngine/fmesh.h"
#include "dxRenderDeviceRender.h"

//////////////////////////////////////////////////////////////////////
// Process-wide cache of shaders built by runtime SetShaderTexture swaps
//////////////////////////////////////////////////////////////////////
// CResourceManager::_cpp_Create compiles all six shader elements before it looks for an equal
// shader, so every swap the per-visual shader_swaps list misses pays a full blender build. Weapon
// HUD models are recreated per draw, so scripts that swap materials on weapon change (3DSS marker
// normalize, magnifiers, canted irons) rebuilt the same shaders on every swap: 35-110 ms hitches.
// Key = what decides the compiled result here: names, HUD context and the visual's skinning mode
// (the VS variant). Only runtime swaps use it (not model loading), so it holds at most
// kMaxEntries shaders; it is cleared on level unload, device reset and device destroy.
int ps_r__shader_swap_cache = 1;

namespace
{
struct SShaderSwapCacheEntry
{
	shared_str shader;
	shared_str texture;
	bool hud;
	s32 skinning;
	ref_shader built;
	u64 last_use;
};

struct SShaderSwapCache
{
	xrSRWLock lock;
	xr_vector<SShaderSwapCacheEntry> entries;
	u64 use_counter = 0;
	u64 hits = 0;
	u64 misses = 0;
	u64 build_ticks = 0;
	u64 max_build_ticks = 0;
};

constexpr size_t kMaxShaderSwapCacheEntries = 256;

SShaderSwapCache& shader_swap_cache()
{
	// Never destroyed: holds ref_shaders, which must not be released after the resource manager.
	static SShaderSwapCache* cache = xr_new<SShaderSwapCache>();
	return *cache;
}
}

void ShaderSwapCache_Clear()
{
	SShaderSwapCache& cache = shader_swap_cache();
	xr_vector<SShaderSwapCacheEntry> released;
	{
		xrSRWLockGuard guard(cache.lock);
		released.swap(cache.entries);
	}
	// ref_shaders are released here, outside the cache lock.
}

void ShaderSwapCache_Report()
{
	SShaderSwapCache& cache = shader_swap_cache();
	xrSRWLockGuard guard(cache.lock, true);
	const double freq = CPU::qpc_freq ? static_cast<double>(CPU::qpc_freq) : 1.0;
	const u64 lookups = cache.hits + cache.misses;
	Msg("[shader swap cache] %s, entries %u/%u, hits %llu, misses %llu (%.1f%% hit), built %.1f ms total, "
		"%.2f ms max, %.2f ms avg per build",
		ps_r__shader_swap_cache ? "on" : "off",
		static_cast<u32>(cache.entries.size()), static_cast<u32>(kMaxShaderSwapCacheEntries),
		static_cast<unsigned long long>(cache.hits), static_cast<unsigned long long>(cache.misses),
		lookups ? 100.0 * static_cast<double>(cache.hits) / static_cast<double>(lookups) : 0.0,
		static_cast<double>(cache.build_ticks) * 1000.0 / freq,
		static_cast<double>(cache.max_build_ticks) * 1000.0 / freq,
		cache.misses ? static_cast<double>(cache.build_ticks) * 1000.0 / freq / static_cast<double>(cache.misses) : 0.0);
}

void ShaderSwapCache_ResetStats()
{
	SShaderSwapCache& cache = shader_swap_cache();
	xrSRWLockGuard guard(cache.lock);
	cache.hits = cache.misses = cache.build_ticks = cache.max_build_ticks = 0;
}

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

IRender_Mesh::~IRender_Mesh()
{
	_RELEASE(p_rm_Vertices);
	_RELEASE(p_rm_Indices);
}

dxRender_Visual::dxRender_Visual()
{
	Type = 0;
	shader = 0;
	vis.clear();
}

dxRender_Visual::~dxRender_Visual()
{
}

void dxRender_Visual::Release()
{
}

//CStatTimer						tscreate;

void dxRender_Visual::Load(const char* N, IReader* data, u32)
{
	dbg_name = N;
	dbg_id = 1;
	skinning = Engine.External.GetSkinningMode();
	hud = ::Render->hud_loading;

	// header
	VERIFY(data);
	ogf_header hdr;
	if (data->r_chunk_safe(OGF_HEADER, &hdr, sizeof(hdr)))
	{
		R_ASSERT2(hdr.format_version==xrOGF_FormatVersion, "Invalid visual version");
		Type = hdr.type;
		//if (hdr.shader_id)	shader	= ::Render->getShader	(hdr.shader_id);
		if (hdr.shader_id) shader = ::RImplementation.getShader(hdr.shader_id);
		vis.box.set(hdr.bb.min, hdr.bb.max);
		vis.sphere.set(hdr.bs.c, hdr.bs.r);
	}
	else
	{
		FATAL("Invalid visual");
	}

	// Shader
	if (data->find_chunk(OGF_TEXTURE))
	{
		string256 fnT, fnS;
		data->r_stringZ(fnT, sizeof(fnT));
		data->r_stringZ(fnS, sizeof(fnS));
		dbg_shader_def = fnS;
		dbg_texture_def = fnT;
		// Load path: build without the runtime swap cache (see SetShaderTextureImpl).
		if (!dbg_shader.equal(dbg_shader_def) || !dbg_texture.equal(dbg_texture_def))
			SetShaderTextureImpl(*dbg_shader_def, *dbg_texture_def, false);
	}

	// desc
#ifdef _EDITOR
    if (data->find_chunk(OGF_S_DESC)) 
	    desc.Load		(*data);
#endif
}

//--DSR-- HeatVision_start
CTexture* dxRender_Visual::GetTexture()
{
	Shader* pSh = shader._get();
	if (pSh == 0) 
		return 0;

	ShaderElement* pShE = pSh->E[0]._get();
	if (pShE == 0 || pShE->passes.empty()) 
		return 0;

	SPass* pPass = pShE->passes[0]._get();
	if (pPass == 0)
		return 0;

	STextureList* pTexList = pPass->T._get();
	if (pTexList == 0 || pTexList->empty()) 
		return 0;

	return pTexList->at(0).second._get();
}

void dxRender_Visual::MarkAsHot(bool is_hot) 
{
	auto texture = GetTexture();
	if (texture)
		texture->m_is_hot = is_hot;
}
//--DSR-- HeatVision_end

//--DSR-- SilencerOverheat_start
void dxRender_Visual::MarkAsGlowing(bool is_glowing)
{
	auto texture = GetTexture();
	if (texture)
		texture->m_is_glowing = is_glowing;
}
//--DSR-- SilencerOverheat_end

void dxRender_Visual::SetShaderTexture(LPCSTR s_shader, LPCSTR s_texture)
{
	SetShaderTextureImpl(s_shader, s_texture, true);
}

void dxRender_Visual::SetShaderTextureImpl(LPCSTR s_shader, LPCSTR s_texture, bool use_swap_cache)
{
	if (s_shader && strlen(s_shader))
	{
		char* shader = xr_strdup(s_shader);
		char* no_shadow = strstr(shader, "$no_shadows");

		if (no_shadow)
		{
			flags.set(IRenderVisualFlags::eNoShadow, TRUE);
			*no_shadow = 0;
		}
		else
			flags.set(IRenderVisualFlags::eNoShadow, FALSE);

		dbg_shader = shader;
		xr_delete(shader);
	}

	if (s_texture && strlen(s_texture))
	{
		dbg_texture = s_texture;
	}

	for (const SShaderSwap& swap : shader_swaps)
	{
		if (swap.hud == hud && swap.shader.equal(dbg_shader) && swap.texture.equal(dbg_texture) && swap.built)
		{
			shader = swap.built;
			return;
		}
	}

	constexpr size_t max_shader_swaps = 4;
	const bool global_cache = use_swap_cache && ps_r__shader_swap_cache;
	if (global_cache)
	{
		SShaderSwapCache& cache = shader_swap_cache();
		xrSRWLockGuard guard(cache.lock);
		for (SShaderSwapCacheEntry& entry : cache.entries)
		{
			if (entry.hud == hud && entry.skinning == skinning && entry.shader.equal(dbg_shader) &&
				entry.texture.equal(dbg_texture) && entry.built)
			{
				entry.last_use = ++cache.use_counter;
				++cache.hits;
				shader = entry.built;
				if (shader_swaps.size() >= max_shader_swaps)
					shader_swaps.erase(shader_swaps.begin());
				shader_swaps.push_back({ dbg_shader, dbg_texture, hud, shader });
				return;
			}
		}
	}

	const u64 build_started = global_cache ? CPU::QPC() : 0;
	Engine.External.SetSkinningMode(skinning);
    	bool prev_hud = ::Render->hud_loading;
    	::Render->hud_loading = hud;
    	shader.create(*dbg_shader, *dbg_texture);
    	::Render->hud_loading = prev_hud;

	if (shader_swaps.size() >= max_shader_swaps)
		shader_swaps.erase(shader_swaps.begin());
	shader_swaps.push_back({ dbg_shader, dbg_texture, hud, shader });

	if (global_cache && shader)
	{
		const u64 build_ticks = CPU::QPC() - build_started;
		SShaderSwapCache& cache = shader_swap_cache();
		ref_shader evicted;
		xrSRWLockGuard guard(cache.lock);
		++cache.misses;
		cache.build_ticks += build_ticks;
		cache.max_build_ticks = _max(cache.max_build_ticks, build_ticks);
		if (cache.entries.size() >= kMaxShaderSwapCacheEntries)
		{
			auto oldest = std::min_element(cache.entries.begin(), cache.entries.end(),
				[](const SShaderSwapCacheEntry& left, const SShaderSwapCacheEntry& right)
				{
					return left.last_use < right.last_use;
				});
			// keep the evicted ref alive until the guard is gone (release outside the lock)
			evicted = oldest->built;
			cache.entries.erase(oldest);
		}
		cache.entries.push_back({ dbg_shader, dbg_texture, hud, skinning, shader, ++cache.use_counter });
	}
}

void dxRender_Visual::ResetShaderTexture()
{
	if (!dbg_shader.equal(dbg_shader_def) || !dbg_texture.equal(dbg_texture_def))
		SetShaderTexture(*dbg_shader_def, *dbg_texture_def);
}

#define PCOPY(a)	a = pFrom->a

void dxRender_Visual::Copy(dxRender_Visual* pFrom)
{
	PCOPY(Type);
	PCOPY(shader);
	PCOPY(vis);
#ifdef _EDITOR
	PCOPY(desc);
#endif
	PCOPY(flags);
	PCOPY(dbg_id);
	PCOPY(dbg_name);
	PCOPY(dbg_shader);
	PCOPY(dbg_shader_def);
	PCOPY(dbg_texture);
	PCOPY(dbg_texture_def);
	PCOPY(skinning);
    PCOPY(hud);
}
