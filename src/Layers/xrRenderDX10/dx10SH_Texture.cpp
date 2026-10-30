#include "stdafx.h"
#pragma hdrstop

#include "../xrRender/ResourceManager.h"

void fix_texture_name(LPSTR fn);

#ifndef _EDITOR
#include "../../xrEngine/render.h"
#endif

#include "../../xrEngine/tntQAVI.h"
#include "../../xrEngine/xrTheora_Surface.h"
#include "../xrRender/gifPlayer.h"

#include "../xrRender/dxRenderDeviceRender.h"

#include "StateManager/dx10ShaderResourceStateCache.h"

#include <chrono>

#if RENDER == R_R4
#include "../xrRenderPC_R4/r4_reticle_vector.h"
#endif

#define		PRIORITY_HIGH	12
#define		PRIORITY_NORMAL	8
#define		PRIORITY_LOW	4

// Background PPL task group used to (re)load textures off the calling thread.
// Defined in dx10ResourceManager_Resources.cpp; CResourceManager::_CreateTexture
// dispatches brand-new textures' initial Load() through it whenever the device is
// ready. apply_load() below reuses the same queue for evicted textures instead of
// calling Load() inline.
extern xr_task_group textures_load_tasks;

namespace
{
// Binds a view at an engine stage index (see CTexture::ResourceShaderType).
void bind_srv(u32 dwStage, ID3DShaderResourceView* view)
{
	if (dwStage < CTexture::rstVertex)
		SRVSManager.SetPSResource(dwStage, view);
	else if (dwStage < CTexture::rstGeometry)
		SRVSManager.SetVSResource(dwStage - CTexture::rstVertex, view);
	else if (dwStage < CTexture::rstHull)
		SRVSManager.SetGSResource(dwStage - CTexture::rstGeometry, view);
#ifdef USE_DX11
	else if (dwStage < CTexture::rstDomain)
		SRVSManager.SetHSResource(dwStage - CTexture::rstHull, view);
	else if (dwStage < CTexture::rstCompute)
		SRVSManager.SetDSResource(dwStage - CTexture::rstDomain, view);
	else if (dwStage < CTexture::rstInvalid)
		SRVSManager.SetCSResource(dwStage - CTexture::rstCompute, view);
#endif
	else
		VERIFY("Invalid stage");
}

// Waits out an in-flight load and reports how long the calling thread was held.
void wait_timed(const CTexture* T)
{
	if (!T->IsLoading())
		return;
	const auto start = std::chrono::steady_clock::now();
	while (T->IsLoading())
		SwitchToThread();
	const auto held = std::chrono::steady_clock::now() - start;
	DEV->NoteTextureWait(T, (u64)std::chrono::duration_cast<std::chrono::microseconds>(held).count());
}

// Textures whose missing frames would show: sky and weather, engine lookup tables, render targets.
// UI is not in the list: a weapon icon stalled the frame 40 ms on a weapon swap, a blank icon for a
// frame is the better trade.
bool must_wait(const shared_str& name)
{
	LPCSTR n = name.c_str();
	if (!n)
		return true;
	return strncmp(n, "sky", 3) == 0 || strncmp(n, "shaders", 7) == 0 || strchr(n, '$') != nullptr;
}

// Phase 0 accounting: true byte size of a 2D/array/cube resource at its actual width/height/mip
// count (post LOD-skip), independent of flags.MemoryUsage (a legacy 27-bit estimate derived from
// the source file's on-disk size, which overcounts - see docs/TEXTURE-STREAMING-PLAN.md).
u64 compute_true_bytes(const D3D_TEXTURE2D_DESC& desc)
{
	if (!desc.Width || !desc.Height || !desc.MipLevels)
		return 0;

	u32 block_w = 1, block_h = 1, block_bytes = 0, texel_bytes = 0;
	switch (desc.Format)
	{
	case DXGI_FORMAT_BC1_TYPELESS: case DXGI_FORMAT_BC1_UNORM: case DXGI_FORMAT_BC1_UNORM_SRGB:
	case DXGI_FORMAT_BC4_TYPELESS: case DXGI_FORMAT_BC4_UNORM: case DXGI_FORMAT_BC4_SNORM:
		block_w = block_h = 4; block_bytes = 8;
		break;
	case DXGI_FORMAT_BC2_TYPELESS: case DXGI_FORMAT_BC2_UNORM: case DXGI_FORMAT_BC2_UNORM_SRGB:
	case DXGI_FORMAT_BC3_TYPELESS: case DXGI_FORMAT_BC3_UNORM: case DXGI_FORMAT_BC3_UNORM_SRGB:
	case DXGI_FORMAT_BC5_TYPELESS: case DXGI_FORMAT_BC5_UNORM: case DXGI_FORMAT_BC5_SNORM:
	case DXGI_FORMAT_BC6H_TYPELESS: case DXGI_FORMAT_BC6H_UF16: case DXGI_FORMAT_BC6H_SF16:
	case DXGI_FORMAT_BC7_TYPELESS: case DXGI_FORMAT_BC7_UNORM: case DXGI_FORMAT_BC7_UNORM_SRGB:
		block_w = block_h = 4; block_bytes = 16;
		break;
	case DXGI_FORMAT_R32G32B32A32_TYPELESS: case DXGI_FORMAT_R32G32B32A32_FLOAT:
	case DXGI_FORMAT_R32G32B32A32_UINT: case DXGI_FORMAT_R32G32B32A32_SINT:
		texel_bytes = 16;
		break;
	case DXGI_FORMAT_R32G32B32_TYPELESS: case DXGI_FORMAT_R32G32B32_FLOAT:
	case DXGI_FORMAT_R32G32B32_UINT: case DXGI_FORMAT_R32G32B32_SINT:
		texel_bytes = 12;
		break;
	case DXGI_FORMAT_R16G16B16A16_TYPELESS: case DXGI_FORMAT_R16G16B16A16_FLOAT:
	case DXGI_FORMAT_R16G16B16A16_UNORM: case DXGI_FORMAT_R16G16B16A16_UINT:
	case DXGI_FORMAT_R16G16B16A16_SNORM: case DXGI_FORMAT_R16G16B16A16_SINT:
	case DXGI_FORMAT_R32G32_TYPELESS: case DXGI_FORMAT_R32G32_FLOAT:
	case DXGI_FORMAT_R32G32_UINT: case DXGI_FORMAT_R32G32_SINT:
		texel_bytes = 8;
		break;
	case DXGI_FORMAT_R8G8B8A8_TYPELESS: case DXGI_FORMAT_R8G8B8A8_UNORM: case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
	case DXGI_FORMAT_R8G8B8A8_UINT: case DXGI_FORMAT_R8G8B8A8_SNORM: case DXGI_FORMAT_R8G8B8A8_SINT:
	case DXGI_FORMAT_B8G8R8A8_TYPELESS: case DXGI_FORMAT_B8G8R8A8_UNORM: case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
	case DXGI_FORMAT_R10G10B10A2_TYPELESS: case DXGI_FORMAT_R10G10B10A2_UNORM: case DXGI_FORMAT_R10G10B10A2_UINT:
	case DXGI_FORMAT_R16G16_TYPELESS: case DXGI_FORMAT_R16G16_FLOAT: case DXGI_FORMAT_R16G16_UNORM:
	case DXGI_FORMAT_R16G16_UINT: case DXGI_FORMAT_R16G16_SNORM: case DXGI_FORMAT_R16G16_SINT:
	case DXGI_FORMAT_R32_TYPELESS: case DXGI_FORMAT_R32_FLOAT: case DXGI_FORMAT_R32_UINT: case DXGI_FORMAT_R32_SINT:
	case DXGI_FORMAT_D32_FLOAT: case DXGI_FORMAT_R24G8_TYPELESS: case DXGI_FORMAT_D24_UNORM_S8_UINT:
		texel_bytes = 4;
		break;
	case DXGI_FORMAT_R8G8_TYPELESS: case DXGI_FORMAT_R8G8_UNORM: case DXGI_FORMAT_R8G8_UINT:
	case DXGI_FORMAT_R8G8_SNORM: case DXGI_FORMAT_R8G8_SINT:
	case DXGI_FORMAT_R16_TYPELESS: case DXGI_FORMAT_R16_FLOAT: case DXGI_FORMAT_R16_UNORM:
	case DXGI_FORMAT_R16_UINT: case DXGI_FORMAT_R16_SNORM: case DXGI_FORMAT_R16_SINT: case DXGI_FORMAT_D16_UNORM:
		texel_bytes = 2;
		break;
	case DXGI_FORMAT_R8_TYPELESS: case DXGI_FORMAT_R8_UNORM: case DXGI_FORMAT_R8_UINT:
	case DXGI_FORMAT_R8_SNORM: case DXGI_FORMAT_R8_SINT: case DXGI_FORMAT_A8_UNORM:
		texel_bytes = 1;
		break;
	default:
		// Unhandled format: fall back to a conservative RGBA8 estimate rather than reporting zero,
		// so an unlisted format shows up as a plausible number instead of silently vanishing from the dump.
		texel_bytes = 4;
		break;
	}

	u64 bytes = 0;
	u32 w = desc.Width, h = desc.Height;
	for (u32 mip = 0; mip < desc.MipLevels; ++mip)
	{
		if (block_bytes)
		{
			const u32 bw = _max(1u, (w + block_w - 1) / block_w);
			const u32 bh = _max(1u, (h + block_h - 1) / block_h);
			bytes += u64(bw) * bh * block_bytes;
		}
		else
		{
			bytes += u64(w) * h * texel_bytes;
		}
		w = _max(1u, w / 2);
		h = _max(1u, h / 2);
	}
	return bytes * _max(1u, u32(desc.ArraySize));
}
}

void resptrcode_texture::create(LPCSTR _name)
{
	PROF_EVENT("resptrcode_texture::create");
	_set(DEV->_CreateTexture(_name));
}


//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////
CTexture::CTexture()
{
	pSurface = NULL;
	m_pSRView = NULL;
	pAVI = NULL;
	pTheora = NULL;
    gifPlayer = nullptr;
	desc_cache = 0;
	ZeroMemory(&desc, sizeof(desc));
	seqMSPF = 0;
	flags.MemoryUsage = 0;
	flags.bLoaded = false;
	flags.bLoading = false;
	flags.bUser = false;
	flags.seqCycles = FALSE;
	flags.bLoadedAsStaging = FALSE;
	m_material = 1.0f;
	bind = xr_make_delegate(this, &CTexture::apply_load);
}

CTexture::~CTexture()
{
	Unload();

	// release external reference
	DEV->_DeleteTexture(this);
}

void CTexture::surface_set(ID3DBaseTexture* surf)
{
	while (IsLoading())
	{
		SwitchToThread();
	}

	if (cName.size() && strstr(cName.c_str(), "$user$"))
		flags.bUser = true;
	if (surf) surf->AddRef();
	_RELEASE(pSurface);
	_RELEASE(m_pSRView);

	pSurface = surf;

	if (pSurface)
	{
		desc_update(); // also recomputes TrueBytes from the new desc

		D3D_RESOURCE_DIMENSION type;
		pSurface->GetType(&type);

		if (D3D_RESOURCE_DIMENSION_TEXTURE2D == type)
		{
			D3D_SHADER_RESOURCE_VIEW_DESC ViewDesc;

			if (desc.MiscFlags & D3D_RESOURCE_MISC_TEXTURECUBE)
			{
				ViewDesc.ViewDimension = D3D_SRV_DIMENSION_TEXTURECUBE;
				ViewDesc.TextureCube.MostDetailedMip = 0;
				ViewDesc.TextureCube.MipLevels = desc.MipLevels;
			}
			else
			{
				if (desc.SampleDesc.Count <= 1)
				{
					ViewDesc.ViewDimension = D3D_SRV_DIMENSION_TEXTURE2D;
					ViewDesc.Texture2D.MostDetailedMip = 0;
					ViewDesc.Texture2D.MipLevels = desc.MipLevels;
				}
				else
				{
					ViewDesc.ViewDimension = D3D_SRV_DIMENSION_TEXTURE2DMS;
					ViewDesc.Texture2D.MostDetailedMip = 0;
					ViewDesc.Texture2D.MipLevels = desc.MipLevels;
				}
			}

			ViewDesc.Format = DXGI_FORMAT_UNKNOWN;

			switch (desc.Format)
			{
			case DXGI_FORMAT_R24G8_TYPELESS:
				ViewDesc.Format = DXGI_FORMAT_R24_UNORM_X8_TYPELESS;
				break;
			case DXGI_FORMAT_R32_TYPELESS:
				ViewDesc.Format = DXGI_FORMAT_R32_FLOAT;
				break;
			}

			// this would be supported by DX10.1 but is not needed for stalker
			// if( ViewDesc.Format != DXGI_FORMAT_R24_UNORM_X8_TYPELESS )
			if ((desc.SampleDesc.Count <= 1) || (ViewDesc.Format != DXGI_FORMAT_R24_UNORM_X8_TYPELESS))
				CHK_DX(HW.pDevice->CreateShaderResourceView(pSurface, &ViewDesc, &m_pSRView));
			else
				m_pSRView = 0;
		}
		else
			CHK_DX(HW.pDevice->CreateShaderResourceView(pSurface, NULL, &m_pSRView));
	}
}

ID3DBaseTexture* CTexture::surface_get()
{
	wait_timed(this);
	if (flags.bLoadedAsStaging)
		ProcessStaging();

	if (pSurface) pSurface->AddRef();
	return pSurface;
}

void CTexture::ApplySwap()
{
	// Render-thread only (called from CResourceManager::ApplyTextureSwaps(), at frame start).
	// PendingSurface/PendingSRView were built on a worker without touching the live
	// pSurface/m_pSRView, so there is nothing here that races a concurrent Apply()/bind.
	if (!PendingSurface)
		return;

	if (!flags.bLoaded)
	{
		// Unloaded (e.g. VRAM pressure) while the swap was in flight: drop the result.
		_RELEASE(PendingSurface);
		_RELEASE(PendingSRView);
		swapQueued.store(false, std::memory_order_release);
		return;
	}

	ID3DBaseTexture* old_surface = pSurface;
	ID3DShaderResourceView* old_srv = m_pSRView;

	pSurface = PendingSurface;
	m_pSRView = PendingSRView;
	RequestedLod = PendingLod;
	PendingSurface = nullptr;
	PendingSRView = nullptr;

	desc_cache = 0; // force a fresh desc_update() for the resource that just landed
	desc_update(); // also recomputes TrueBytes from the new desc
	flags.MemoryUsage = u32(TrueBytes); // legacy 27-bit estimate; same truncation risk as Load() already has

	_RELEASE(old_surface);
	_RELEASE(old_srv);
	swapQueued.store(false, std::memory_order_release);
}

void CTexture::PostLoad()
{
	// Phase 2: classify once per load. DEV->ClassifyTexture() lazy-loads tex_residency.ltx on
	// its own first call; safe here since nothing on this thread already holds creationGuard.
	if (ResClass == -2)
		ResClass = DEV->ClassifyTexture(cName);

	if (pTheora) bind = xr_make_delegate(this, &CTexture::apply_theora);
	else if (pAVI) bind = xr_make_delegate(this, &CTexture::apply_avi);
	else if (!seqDATA.empty()) bind = xr_make_delegate(this, &CTexture::apply_seq);
	else if (gifPlayer) bind = xr_make_delegate(this, &CTexture::apply_gif);
	else bind = xr_make_delegate(this, &CTexture::apply_normal);
}

void CTexture::apply_load(u32 dwStage)
{
    if (!flags.bLoaded)
    {
        // Never loaded, or just dropped by EvictStalledTextures(). Load() ends up in
        // D3DX11CreateTextureFromMemory, which races the resource thread if run inline
        // here (this can run on the render thread mid-gameplay just as easily as on a
        // loading-screen thread during level load - neither is safe in the MT build).
        // Queue the (re)load the same way _CreateTexture() does for new textures instead;
        // bLoading guards against re-queuing every call while that's in flight.
        if (!IsLoading())
        {
#ifdef DEBUG
            Msg("* [TexReload] queued: %s", cName.c_str());
#endif // DEBUG
            DEV->QueueTextureLoad(ref_texture(this));
        }
        // apply_normal() either binds nothing for this call (r__tex_nowait) or waits
        // out the load, so this never touches D3D resources that are being created
        // concurrently. Once the queued Load() completes, PostLoad() re-points
        // `bind` at the real apply_* handler and subsequent calls stop landing here.
        apply_normal(dwStage);
        return;
    }

    PostLoad();
    if (bind == xr_make_delegate(this, &CTexture::apply_load))
    {
        // This should not happen - if bind is still apply_load, fall back to apply_normal
        // which will just apply the (potentially unloaded) surface
        apply_normal(dwStage);
    }
    else
    {
        bind(dwStage);
    }
};

void CTexture::ProcessStaging()
{
	VERIFY(pSurface);
	VERIFY(flags.bLoadedAsStaging);

	ID3DBaseTexture* pTargetSurface = 0;

	D3D_RESOURCE_DIMENSION type;
	pSurface->GetType(&type);

	switch (type)
	{
	case D3D_RESOURCE_DIMENSION_TEXTURE2D:
		{
			ID3DTexture2D* T = (ID3DTexture2D*)pSurface;
			D3D_TEXTURE2D_DESC TexDesc;
			T->GetDesc(&TexDesc);
			TexDesc.Usage = D3D_USAGE_DEFAULT;
			TexDesc.BindFlags = D3D_BIND_SHADER_RESOURCE;
			TexDesc.CPUAccessFlags = 0;

			T = 0;

			CHK_DX(HW.pDevice->CreateTexture2D( &TexDesc, // Texture desc
				NULL, // Initial data
				&T )); // [out] Texture

			pTargetSurface = T;
		}
		break;
	case D3D_RESOURCE_DIMENSION_TEXTURE3D:
		{
			ID3DTexture3D* T = (ID3DTexture3D*)pSurface;
			D3D_TEXTURE3D_DESC TexDesc;
			T->GetDesc(&TexDesc);
			TexDesc.Usage = D3D_USAGE_DEFAULT;
			TexDesc.BindFlags = D3D_BIND_SHADER_RESOURCE;
			TexDesc.CPUAccessFlags = 0;

			T = 0;

			CHK_DX(HW.pDevice->CreateTexture3D( &TexDesc, // Texture desc
				NULL, // Initial data
				&T )); // [out] Texture

			pTargetSurface = T;
		}
		break;
	default:
		VERIFY(!"CTexture::ProcessStaging unsupported dimensions.");
	}

	HW.pContext->CopyResource(pTargetSurface, pSurface);
	/*
	for( int i=0; i<iNumSubresources; ++i)
	{
		HW.pDevice->CopySubresourceRegion(
			pTargetSurface,
			i,
			0,
			0,
			0,
			pSurface,
			i,
			0
			);
	}
	*/


	flags.bLoadedAsStaging = FALSE;

	//	Check if texture was not copied _before_ it was converted.
	ULONG RefCnt = pSurface->Release();
	pSurface = 0;

	VERIFY(!RefCnt);

	surface_set(pTargetSurface);

	_RELEASE(pTargetSurface);
}

void CTexture::Apply(u32 dwStage)
{
	wait_timed(this);
	dwLastUsedFrame = RDEVICE.dwFrame;
	dwLastUsedTime = RDEVICE.dwTimeGlobal;

	if (flags.bLoadedAsStaging)
		ProcessStaging();

	// Phase 2: a classified texture that was demoted for being idle is back in use - queue a
	// promote. Cheap for the common case (RequestedLod is 0 for almost everything); the actual
	// swap work happens on a worker, and QueueTextureSwap's own guards make repeat calls free.
	if (RequestedLod && ResClass >= 0 && !swapQueued.load(std::memory_order_relaxed))
		DEV->QueueTextureSwap(ref_texture(this), 0);

	//if( !RImplementation.o.dx10_msaa )
	//   VERIFY( !((!pSurface)^(!m_pSRView)) );	//	Both present or both missing
	//else
	//{
	//if( ((!pSurface)^(!m_pSRView)) )
	//   return;
	//}

	bind_srv(dwStage, m_pSRView);
}

void CTexture::apply_theora(u32 dwStage)
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	if (pTheora->Update(m_play_time != 0xFFFFFFFF ? m_play_time : Device.dwTimeContinual))
	{
		D3D_RESOURCE_DIMENSION type;
		pSurface->GetType(&type);
		R_ASSERT(D3D_RESOURCE_DIMENSION_TEXTURE2D == type);
		ID3DTexture2D* T2D = (ID3DTexture2D*)pSurface;
		D3D_MAPPED_TEXTURE2D mapData;
		RECT rect;
		rect.left = 0;
		rect.top = 0;
		rect.right = pTheora->Width(true);
		rect.bottom = pTheora->Height(true);

		u32 _w = pTheora->Width(false);

		//R_CHK				(T2D->LockRect(0,&R,&rect,0));
#ifdef USE_DX11
		R_CHK(HW.pContext->Map(T2D, 0, D3D_MAP_WRITE_DISCARD, 0, &mapData));
#else
		R_CHK(T2D->Map(0,D3D_MAP_WRITE_DISCARD,0,&mapData));
#endif
		//R_ASSERT			(R.Pitch == int(pTheora->Width(false)*4));
		R_ASSERT(mapData.RowPitch == int(pTheora->Width(false)*4));
		int _pos = 0;
		pTheora->DecompressFrame((u32*)mapData.pData, _w - rect.right, _pos);
		VERIFY(u32(_pos) == rect.bottom*_w);
		//R_CHK				(T2D->UnlockRect(0));
#ifdef USE_DX11
		HW.pContext->Unmap(T2D, 0);
#else
		T2D->Unmap(0);
#endif
	}
	Apply(dwStage);
	//CHK_DX(HW.pDevice->SetTexture(dwStage,pSurface));
};

void CTexture::apply_avi(u32 dwStage)
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	if (pAVI->NeedUpdate())
	{
		D3D_RESOURCE_DIMENSION type;
		pSurface->GetType(&type);
		R_ASSERT(D3D_RESOURCE_DIMENSION_TEXTURE2D == type);
		ID3DTexture2D* T2D = (ID3DTexture2D*)pSurface;
		D3D_MAPPED_TEXTURE2D mapData;

		// AVI
		//R_CHK	(T2D->LockRect(0,&R,NULL,0));
#ifdef USE_DX11
		R_CHK(HW.pContext->Map(T2D, 0, D3D_MAP_WRITE_DISCARD, 0, &mapData));
#else
		R_CHK(T2D->Map(0,D3D_MAP_WRITE_DISCARD,0,&mapData));
#endif
		R_ASSERT(mapData.RowPitch == int(pAVI->m_dwWidth*4));
		BYTE* ptr;
		pAVI->GetFrame(&ptr);
		CopyMemory(mapData.pData, ptr, pAVI->m_dwWidth*pAVI->m_dwHeight*4);
		//R_CHK	(T2D->UnlockRect(0));
#ifdef USE_DX11
		HW.pContext->Unmap(T2D, 0);
#else
		T2D->Unmap(0);
#endif
	}
	//CHK_DX(HW.pDevice->SetTexture(dwStage,pSurface));
	Apply(dwStage);
};

void CTexture::apply_seq(u32 dwStage)
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	// SEQ
	u32 frame = Device.dwTimeContinual / seqMSPF; //Device.dwTimeGlobal
	u32 frame_data = seqDATA.size();
	if (flags.seqCycles)
	{
		u32 frame_id = frame % (frame_data * 2);
		if (frame_id >= frame_data) frame_id = (frame_data - 1) - (frame_id % frame_data);
		pSurface = seqDATA[frame_id];
		m_pSRView = m_seqSRView[frame_id];
	}
	else
	{
		u32 frame_id = frame % frame_data;
		pSurface = seqDATA[frame_id];
		m_pSRView = m_seqSRView[frame_id];
	}
	//CHK_DX(HW.pDevice->SetTexture(dwStage,pSurface));
	Apply(dwStage);
};

void CTexture::apply_gif(u32 dwStage)
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	if (gifPlayer->UpdateFrame())
	{
        const CGIFAnimationPlayer::Frame* const gifFrame = gifPlayer->GetActiveFrame();
        R_ASSERT(gifFrame);

        pSurface = gifFrame->surface;
        m_pSRView = gifFrame->srv;
	}
	Apply(dwStage);
}

void CTexture::apply_normal(u32 dwStage)
{
	if (ps_r__tex_nowait && IsLoading() && !must_wait(cName))
	{
		// Still loading on a worker: draw this frame without it rather than stall the render thread.
		bind_srv(dwStage, nullptr);
		DEV->NoteTextureDeferred();
		return;
	}
	//CHK_DX(HW.pDevice->SetTexture(dwStage,pSurface));
	Apply(dwStage);
};

void CTexture::Preload()
{
	if (!Core.ParamsData.test(ECoreParams::r4_dev))
	{
	m_bumpmap = DEV->m_textures_description.GetBumpName(cName);
	}
	m_material = DEV->m_textures_description.GetMaterial(cName);
}

void CTexture::Load()
{
	PROF_EVENT("CTexture::Load");

	if (flags.bLoaded || flags.bLoading) return;
	flags.bLoading = true;
	flags.bLoaded = false;
	desc_cache = 0;
	if (pSurface)
	{
		flags.bLoading = false;
		flags.bLoaded = true;
		return;
	}

	flags.bUser = false;
	flags.MemoryUsage = 0;
	TrueBytes = 0; // reset on every (re)load - the seq branch below accumulates into it
	if (0 == stricmp(*cName, "$null"))
	{
		flags.bLoading = false;
		flags.bLoaded = true;
		return;
	}
	if (0 != strstr(*cName, "$user$"))
	{
		flags.bUser = true;
		flags.bLoading = false;
		flags.bLoaded = true;
		return;
	}

	Preload();

	bool bCreateView = true;

	// Check for OGM
	string_path fn;
	if (FS.exist(fn, "$game_textures$", *cName, ".ogm"))
	{
		// AVI
		pTheora = xr_new<CTheoraSurface>();
		m_play_time = 0xFFFFFFFF;

		if (!pTheora->Load(fn))
		{
			xr_delete(pTheora);
			FATAL("Can't open video stream");
		}
		else
		{
			flags.MemoryUsage = pTheora->Width(true) * pTheora->Height(true) * 4;
			TrueBytes = flags.MemoryUsage; // video overlay, not worth a separate desc query
			pTheora->Play(TRUE, Device.dwTimeContinual);

			// Now create texture
			ID3DTexture2D* pTexture = 0;
			u32 _w = pTheora->Width(false);
			u32 _h = pTheora->Height(false);

			//			HRESULT hrr = HW.pDevice->CreateTexture(
			//				_w, _h, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &pTexture, NULL );
			D3D_TEXTURE2D_DESC desc;
			desc.Width = _w;
			desc.Height = _h;
			desc.MipLevels = 1;
			desc.ArraySize = 1;
			desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
			desc.SampleDesc.Count = 1;
			desc.SampleDesc.Quality = 0;
			desc.Usage = D3D_USAGE_DYNAMIC;
			desc.BindFlags = D3D_BIND_SHADER_RESOURCE;
			desc.CPUAccessFlags = D3D_CPU_ACCESS_WRITE;
			desc.MiscFlags = 0;
			HRESULT hrr = HW.pDevice->CreateTexture2D(&desc, 0, &pTexture);

			pSurface = pTexture;
			if (FAILED(hrr))
			{
				FATAL("Invalid video stream");
				R_CHK(hrr);
				xr_delete(pTheora);
				pSurface = 0;
				m_pSRView = 0;
			}
			else
			{
				CHK_DX(HW.pDevice->CreateShaderResourceView(pSurface, 0, &m_pSRView));
			}
		}
	}
	else if (FS.exist(fn, "$game_textures$", *cName, ".avi"))
	{
		// AVI
		pAVI = xr_new<CAviPlayerCustom>();

		if (!pAVI->Load(fn))
		{
			xr_delete(pAVI);
			FATAL("Can't open video stream");
		}
		else
		{
			flags.MemoryUsage = pAVI->m_dwWidth * pAVI->m_dwHeight * 4;
			TrueBytes = flags.MemoryUsage; // video overlay, not worth a separate desc query

			// Now create texture
			ID3DTexture2D* pTexture = 0;
			//HRESULT hrr = HW.pDevice->CreateTexture(
			//pAVI->m_dwWidth,pAVI->m_dwHeight,1,0,D3DFMT_A8R8G8B8,D3DPOOL_MANAGED,
			//	&pTexture,NULL
			//	);
			D3D_TEXTURE2D_DESC desc;
			desc.Width = pAVI->m_dwWidth;
			desc.Height = pAVI->m_dwHeight;
			desc.MipLevels = 1;
			desc.ArraySize = 1;
			desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
			desc.SampleDesc.Count = 1;
			desc.SampleDesc.Quality = 0;
			desc.Usage = D3D_USAGE_DYNAMIC;
			desc.BindFlags = D3D_BIND_SHADER_RESOURCE;
			desc.CPUAccessFlags = D3D_CPU_ACCESS_WRITE;
			desc.MiscFlags = 0;
			HRESULT hrr = HW.pDevice->CreateTexture2D(&desc, 0, &pTexture);

			pSurface = pTexture;
			if (FAILED(hrr))
			{
				FATAL("Invalid video stream");
				R_CHK(hrr);
				xr_delete(pAVI);
				pSurface = 0;
				m_pSRView = 0;
			}
			else
			{
				CHK_DX(HW.pDevice->CreateShaderResourceView(pSurface, 0, &m_pSRView));
			}
		}
	}
	else if (FS.exist(fn, "$game_textures$", *cName, ".seq"))
	{
		// Sequence
		string256 buffer;
		IReader* _fs = FS.r_open(fn);

		flags.seqCycles = FALSE;
		_fs->r_string(buffer, sizeof(buffer));
		if (0 == stricmp(buffer, "cycled"))
		{
			flags.seqCycles = TRUE;
			_fs->r_string(buffer, sizeof(buffer));
		}
		u32 fps = atoi(buffer);
		seqMSPF = 1000 / fps;

		// Resolved name of each seqDATA entry. A frame file that repeats is loaded once:
		// later entries share its surface and view, each holding its own reference, so
		// Unload() still releases every entry once. MemoryUsage counts it once.
		xr_vector<shared_str> seq_names;
		while (!_fs->eof())
		{
			_fs->r_string(buffer, sizeof(buffer));
			_Trim(buffer);
			if (buffer[0])
			{
				string_path resolved;
				xr_strcpy(resolved, buffer);
				fix_texture_name(resolved);
				xr_strlwr(resolved);
				const shared_str name = resolved;

				const auto it = std::find(seq_names.begin(), seq_names.end(), name);
				if (it != seq_names.end())
				{
					const size_t first = it - seq_names.begin();
					seqDATA.push_back(seqDATA[first]);
					seqDATA.back()->AddRef();
					m_seqSRView.push_back(m_seqSRView[first]);
					if (m_seqSRView.back())
						m_seqSRView.back()->AddRef();
					seq_names.push_back(name);
					continue;
				}

				// Load another texture
				u32 mem = 0;
				pSurface = ::RImplementation.texture_load(buffer, mem);
				if (pSurface)
				{
					// pSurface->SetPriority	(PRIORITY_LOW);
					seqDATA.push_back(pSurface);
					m_seqSRView.push_back(0);
					HW.pDevice->CreateShaderResourceView(seqDATA.back(), NULL, &m_seqSRView.back());
					flags.MemoryUsage += mem;
					TrueBytes += mem; // sequence frames, not worth a per-frame desc query
					seq_names.push_back(name);
				}
			}
		}
		pSurface = 0;
		FS.r_close(_fs);
	}
    else if (FS.exist(fn, "$game_textures$", *cName, ".gif"))
    {
        gifPlayer = xr_new<CGIFAnimationPlayer>();
        if (!gifPlayer->Load(fn))
        {
            xr_delete(gifPlayer);
            pSurface = nullptr;
            m_pSRView = nullptr;
        }
        else
        {
            flags.MemoryUsage = gifPlayer->GetUsedMemory();
            TrueBytes = flags.MemoryUsage; // animated UI texture, not worth a separate desc query

            gifPlayer->Play();

            const CGIFAnimationPlayer::Frame* const gifFrame = gifPlayer->GetActiveFrame();
            pSurface = gifFrame->surface;
            m_pSRView = gifFrame->srv;
        }
    }
	else
	{
		// Normal texture
		u32 mem = 0;
#if RENDER == R_R4
		// Vector reticle: built from <name>.svg when that is the texture's source (r4_reticle_vector.cpp)
		float glow_size = 0.f;
		pSurface = reticle_vector_texture_load(*cName, mem, glow_size);
		if (pSurface)
			reticle_glow_size = glow_size;
		else
#endif
		//pSurface = ::RImplementation.texture_load	(*cName,mem);
		pSurface = ::RImplementation.texture_load(*cName, mem, true, (int)RequestedLod);

		if (GetUsage() == D3D_USAGE_STAGING)
		{
			flags.bLoadedAsStaging = TRUE;
			bCreateView = false;
		}

		// Calc memory usage and preload into vid-mem
		if (pSurface)
		{
			// pSurface->SetPriority	(PRIORITY_NORMAL);
			flags.MemoryUsage = mem;

			// Phase 0 accounting: true bytes from the resource just created, at its actual
			// mip count/LOD. Can't go through desc_update() here - flags.bLoading is still
			// set and desc_update() would spin forever waiting on IsLoading() on this very
			// thread - so query the fresh pSurface directly instead.
			D3D_RESOURCE_DIMENSION rtype;
			pSurface->GetType(&rtype);
			if (D3D_RESOURCE_DIMENSION_TEXTURE2D == rtype)
			{
				D3D_TEXTURE2D_DESC d;
				((ID3DTexture2D*)pSurface)->GetDesc(&d);
				TrueBytes = compute_true_bytes(d);
			}
		}
		
		if (pSurface && bCreateView)
			CHK_DX(HW.pDevice->CreateShaderResourceView(pSurface, NULL, &m_pSRView));
	}
	PostLoad();
	flags.bLoading = false;
	flags.bLoaded = true;
}

void CTexture::Unload()
{
	while (IsLoading())
	{
		SwitchToThread();
	}

#if RENDER == R_R4
	// Reticle atlas: read the glow size again if this texture is loaded again.
	reticle_glow_size = -1.f;
#endif
	// Already unloaded or never loaded: no GPU resources to release.
	if (!flags.bLoaded)
		return;
#ifdef DEBUG
	string_path				msg_buff;
	xr_sprintf				(msg_buff,sizeof(msg_buff),"* Unloading texture [%s] pSurface RefCount=",cName.c_str());
#endif // DEBUG

	//.	if (flags.bLoaded)		Msg		("* Unloaded: %s",cName.c_str());

	flags.bLoaded = FALSE;
	flags.bLoadedAsStaging = FALSE;
	if (!seqDATA.empty())
	{
		for (u32 I = 0; I < seqDATA.size(); I++)
		{
			_RELEASE(seqDATA[I]);
			_RELEASE(m_seqSRView[I]);
		}
		seqDATA.clear();
		m_seqSRView.clear();
		pSurface = 0;
		m_pSRView = 0;
	}

    if (gifPlayer)
    {
        xr_delete(gifPlayer);
        pSurface = nullptr;
        m_pSRView = nullptr;
    }

#ifdef DEBUG
	_SHOW_REF		(msg_buff, pSurface);
#endif // DEBUG
	_RELEASE(pSurface);
	_RELEASE(m_pSRView);

	xr_delete(pAVI);
	xr_delete(pTheora);

	bind = xr_make_delegate(this, &CTexture::apply_load);
}

void CTexture::desc_update()
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	desc_cache = pSurface;
	if (pSurface)
	{
		D3D_RESOURCE_DIMENSION type;
		pSurface->GetType(&type);
		if (D3D_RESOURCE_DIMENSION_TEXTURE2D == type)
		{
			ID3DTexture2D* T = (ID3DTexture2D*)pSurface;
			T->GetDesc(&desc);
			// Phase 0 accounting: true bytes from the resource actually created, at its
			// current mip count/LOD (see compute_true_bytes). Most textures never reach here
			// lazily (nothing calls get_Width()/get_Height() on them) - Load() sets TrueBytes
			// itself for the common path; this covers surface_set() callers and later queries.
			TrueBytes = compute_true_bytes(desc);
		}
		else
		{
			TrueBytes = 0;
		}
	}
	else
	{
		TrueBytes = 0;
	}
}

D3D_USAGE CTexture::GetUsage()
{
	D3D_USAGE res = D3D_USAGE_DEFAULT;

	if (pSurface)
	{
		D3D_RESOURCE_DIMENSION type;
		pSurface->GetType(&type);
		switch (type)
		{
		case D3D_RESOURCE_DIMENSION_TEXTURE1D:
			{
				ID3DTexture1D* T = (ID3DTexture1D*)pSurface;
				D3D_TEXTURE1D_DESC descr;
				T->GetDesc(&descr);
				res = descr.Usage;
			}
			break;

		case D3D_RESOURCE_DIMENSION_TEXTURE2D:
			{
				ID3DTexture2D* T = (ID3DTexture2D*)pSurface;
				D3D_TEXTURE2D_DESC descr;
				T->GetDesc(&descr);
				res = descr.Usage;
			}
			break;

		case D3D_RESOURCE_DIMENSION_TEXTURE3D:
			{
				ID3DTexture3D* T = (ID3DTexture3D*)pSurface;
				D3D_TEXTURE3D_DESC descr;
				T->GetDesc(&descr);
				res = descr.Usage;
			}
			break;

		default:
			VERIFY(!"Unknown texture format???");
		}
	}

	return res;
}

void CTexture::video_Play(BOOL looped, u32 _time)
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	if (pTheora) pTheora->Play(looped, (_time != 0xFFFFFFFF) ? (m_play_time = _time) : Device.dwTimeContinual);
}

void CTexture::video_Pause(BOOL state)
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	if (pTheora) pTheora->Pause(state);
}

void CTexture::video_Stop()
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	if (pTheora) pTheora->Stop();
}

BOOL CTexture::video_IsPlaying()
{
	while (IsLoading())
	{
		SwitchToThread();
	}
	return (pTheora) ? pTheora->IsPlaying() : FALSE;
}
