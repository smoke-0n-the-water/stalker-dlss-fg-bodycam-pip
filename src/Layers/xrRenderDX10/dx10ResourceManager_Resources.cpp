#include "stdafx.h"
#pragma hdrstop

#pragma warning(disable:4995)
#include <d3dx9.h>
#ifndef _EDITOR
#pragma comment( lib, "d3dx9.lib"		)
#include "../../xrEngine/render.h"
#endif
#pragma warning(default:4995)

#include <D3DX10Core.h>

#include "../xrRender/ResourceManager.h"
#include "../xrRender/tss.h"
#include "../xrRender/blenders/blender.h"
#include "../xrRender/blenders/blender_recorder.h"

#include "../xrRenderDX10/dx10BufferUtils.h"
#include "../xrRenderDX10/dx10ConstantBuffer.h"

#include "../xrRender/ShaderResourceTraits.h"
#include "../../xrCore/_std_extensions.h" // timestamp() for the tex_res_dump CSV filename
#ifndef _EDITOR
#include "../../xrEngine/render.h" // RImplementation, for the Phase 1 swap worker's texture_load() call
#endif

#ifdef USE_DX11
SHS* CResourceManager::_CreateHS(LPCSTR Name)
{
	return CreateShader<SHS>(Name);
}

void CResourceManager::_DeleteHS(const SHS* HS)
{
	DestroyShader(HS);
}

SDS* CResourceManager::_CreateDS(LPCSTR Name)
{
	return CreateShader<SDS>(Name);
}

void CResourceManager::_DeleteDS(const SDS* DS)
{
	DestroyShader(DS);
}

SCS* CResourceManager::_CreateCS(LPCSTR Name)
{
	return CreateShader<SCS>(Name);
}

void CResourceManager::_DeleteCS(const SCS* CS)
{
	DestroyShader(CS);
}
#endif	//	USE_DX10

void fix_texture_name(LPSTR fn);

template <class T>
BOOL reclaim(xr_vector<T*>& vec, const T* ptr)
{
	xr_vector<T*>::iterator it = vec.begin();
	xr_vector<T*>::iterator end = vec.end();
	for (; it != end; it++)
		if (*it == ptr)
		{
			vec.erase(it);
			return TRUE;
		}
	return FALSE;
}

//--------------------------------------------------------------------------------------------------------------
SState* CResourceManager::_CreateState(SimulatorStates& state_code)
{
	xrCriticalSectionGuard guard(creationGuard);

	// Search equal state-code 
	for (u32 it = 0; it < v_states.size(); it++)
	{
		SState* C = v_states[it];;
		SimulatorStates& base = C->state_code;
		if (base.equal(state_code)) return C;
	}

	// Create New
	v_states.push_back(xr_new<SState>());
	v_states.back()->dwFlags |= xr_resource_flagged::RF_REGISTERED;
#if defined(USE_DX10) || defined(USE_DX11)
	v_states.back()->state = ID3DState::Create(state_code);
#else	//	USE_DX10
	v_states.back()->state			= state_code.record();
#endif	//	USE_DX10
	v_states.back()->state_code = state_code;
	return v_states.back();
}

void CResourceManager::_DeleteState(const SState* state)
{
	if (0 == (state->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(v_states, state)) return;
	Msg("! ERROR: Failed to find compiled stateblock");
}

//--------------------------------------------------------------------------------------------------------------
SPass* CResourceManager::_CreatePass(const SPass& proto)
{
	xrCriticalSectionGuard guard(creationGuard);
	for (u32 it = 0; it < v_passes.size(); it++)
		if (v_passes[it]->equal(proto))
			return v_passes[it];

	SPass* P = xr_new<SPass>();
	P->dwFlags |= xr_resource_flagged::RF_REGISTERED;
	P->state = proto.state;
	P->ps = proto.ps;
	P->vs = proto.vs;
	P->gs = proto.gs;
#ifdef USE_DX11
	P->hs = proto.hs;
	P->ds = proto.ds;
	P->cs = proto.cs;
#endif
	P->constants = proto.constants;
	P->T = proto.T;
#ifdef _EDITOR
	P->M						=	proto.M;
#endif
	P->C = proto.C;

	v_passes.push_back(P);
	return v_passes.back();
}

void CResourceManager::_DeletePass(const SPass* P)
{
	if (0 == (P->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(v_passes, P)) return;
	Msg("! ERROR: Failed to find compiled pass");
}

//--------------------------------------------------------------------------------------------------------------
SVS* CResourceManager::_CreateVS(LPCSTR _name)
{
	xrCriticalSectionGuard guard(creationGuard);
	xr_string res_name = _name;

	const int m_skinning = Engine.External.GetSkinningMode();
	if (m_skinning > 0)
	{
		res_name += "_" + xr_string::ToString(m_skinning);
	}

	LPCSTR name = res_name.c_str();
	LPSTR N = LPSTR(name);
	map_VS::iterator I = m_vs.find(N);
	if (I != m_vs.end()) return I->second;
	else
	{
		SVS* _vs = xr_new<SVS>();
		_vs->skinning = m_skinning;
		_vs->dwFlags |= xr_resource_flagged::RF_REGISTERED;
		m_vs.insert(mk_pair(_vs->set_name(name), _vs));
		//_vs->vs				= NULL;
		//_vs->signature		= NULL;
		if (0 == stricmp(_name, "null"))
		{
			return _vs;
		}

		string_path shName;
		{
			const char* pchr = strchr(_name, '(');
			ptrdiff_t size = pchr ? pchr - _name : xr_strlen(_name);
			strncpy(shName, _name, size);
			shName[size] = 0;
		}

		string_path cname;
		strconcat(sizeof(cname), cname, ::Render->getShaderPath(),/*_name*/shName, ".vs");
		FS.update_path(cname, "$game_shaders$", cname);
		//		LPCSTR						target		= NULL;

		// duplicate and zero-terminate
		IReader* file = FS.r_open(cname);
		//	TODO: DX10: HACK: Implement all shaders. Remove this for PS
		if (!file)
		{
			string1024 tmp;
			xr_sprintf(tmp, "DX10: %s is missing. Replace with stub_default.vs", cname);
			Msg(tmp);
			strconcat(sizeof(cname), cname, ::Render->getShaderPath(), "stub_default", ".vs");
			FS.update_path(cname, "$game_shaders$", cname);
			file = FS.r_open(cname);
		}
		u32 const size = file->length();
		char* const data = (LPSTR)_alloca(size + 1);
		CopyMemory(data, file->pointer(), size);
		data[size] = 0;
		FS.r_close(file);

		// Select target
		LPCSTR c_target = "vs_2_0";
		LPCSTR c_entry = "main";
		if (HW.Caps.geometry_major >= 2) c_target = "vs_2_0";
		else c_target = "vs_1_1";

		if (strstr(data, "main_vs_1_1"))
		{
			c_target = "vs_1_1";
			c_entry = "main_vs_1_1";
		}
		if (strstr(data, "main_vs_2_0"))
		{
			c_target = "vs_2_0";
			c_entry = "main_vs_2_0";
		}

		HRESULT const _hr = ::Render->shader_compile(name, (DWORD const*)data, size, c_entry, c_target,
		                                             D3D10_SHADER_PACK_MATRIX_ROW_MAJOR, (void*&)_vs);

		VERIFY(SUCCEEDED(_hr));

		CHECK_OR_EXIT(
			!FAILED(_hr),
			make_string("Shader compilation failed, check your log file for additional information.")
		);

		return _vs;
	}
}

void CResourceManager::_DeleteVS(const SVS* vs)
{
	if (0 == (vs->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	LPSTR N = LPSTR(*vs->cName);
	map_VS::iterator I = m_vs.find(N);
	if (I != m_vs.end())
	{
		m_vs.erase(I);
		xr_vector<SDeclaration*>::iterator iDecl;
		for (iDecl = v_declarations.begin(); iDecl != v_declarations.end(); ++iDecl)
		{
			xr_map<ID3DBlob*, ID3DInputLayout*>::iterator iLayout;
			iLayout = (*iDecl)->vs_to_layout.find(vs->signature->signature);
			if (iLayout != (*iDecl)->vs_to_layout.end())
			{
				//	Release vertex layout
				_RELEASE(iLayout->second);
				(*iDecl)->vs_to_layout.erase(iLayout);
			}
		}
		RCache.invalidate_layout_memo(); // a released layout must not survive as a memo hit
		return;
	}
	Msg("! ERROR: Failed to find compiled vertex-shader '%s'", *vs->cName);
}

//--------------------------------------------------------------------------------------------------------------
SPS* CResourceManager::_CreatePS(LPCSTR _name)
{
	xrCriticalSectionGuard guard(creationGuard);
	string_path name;
	xr_strcpy(name, _name);
	if (0 == ::Render->m_MSAASample) xr_strcat(name, "_0");
	if (1 == ::Render->m_MSAASample) xr_strcat(name, "_1");
	if (2 == ::Render->m_MSAASample) xr_strcat(name, "_2");
	if (3 == ::Render->m_MSAASample) xr_strcat(name, "_3");
	if (4 == ::Render->m_MSAASample) xr_strcat(name, "_4");
	if (5 == ::Render->m_MSAASample) xr_strcat(name, "_5");
	if (6 == ::Render->m_MSAASample) xr_strcat(name, "_6");
	if (7 == ::Render->m_MSAASample) xr_strcat(name, "_7");
	LPSTR N = LPSTR(name);
	map_PS::iterator I = m_ps.find(N);
	if (I != m_ps.end()) return I->second;
	else
	{
		SPS* _ps = xr_new<SPS>();
		_ps->dwFlags |= xr_resource_flagged::RF_REGISTERED;
		m_ps.insert(mk_pair(_ps->set_name(name), _ps));
		if (0 == stricmp(_name, "null"))
		{
			_ps->ps = NULL;
			return _ps;
		}

		string_path shName;
		const char* pchr = strchr(_name, '(');
		ptrdiff_t strSize = pchr ? pchr - _name : xr_strlen(_name);
		strncpy(shName, _name, strSize);
		shName[strSize] = 0;

		// Open file
		string_path cname;
		strconcat(sizeof(cname), cname, ::Render->getShaderPath(),/*_name*/shName, ".ps");
		FS.update_path(cname, "$game_shaders$", cname);

		// duplicate and zero-terminate
		IReader* file = FS.r_open(cname);
		//	TODO: DX10: HACK: Implement all shaders. Remove this for PS
		if (!file)
		{
			string1024 tmp;
			//	TODO: HACK: Test failure
			//Memory.mem_compact();
			xr_sprintf(tmp, "DX10: %s is missing. Replace with stub_default.ps", cname);
			Msg(tmp);
			strconcat(sizeof(cname), cname, ::Render->getShaderPath(), "stub_default", ".ps");
			FS.update_path(cname, "$game_shaders$", cname);
			file = FS.r_open(cname);
		}

		R_ASSERT2(file, cname);
		u32 const size = file->length();
		char* const data = (LPSTR)_alloca(size + 1);
		CopyMemory(data, file->pointer(), size);
		data[size] = 0;
		FS.r_close(file);

		// Select target
		LPCSTR c_target = "ps_2_0";
		LPCSTR c_entry = "main";
		if (strstr(data, "main_ps_1_1"))
		{
			c_target = "ps_1_1";
			c_entry = "main_ps_1_1";
		}
		if (strstr(data, "main_ps_1_2"))
		{
			c_target = "ps_1_2";
			c_entry = "main_ps_1_2";
		}
		if (strstr(data, "main_ps_1_3"))
		{
			c_target = "ps_1_3";
			c_entry = "main_ps_1_3";
		}
		if (strstr(data, "main_ps_1_4"))
		{
			c_target = "ps_1_4";
			c_entry = "main_ps_1_4";
		}
		if (strstr(data, "main_ps_2_0"))
		{
			c_target = "ps_2_0";
			c_entry = "main_ps_2_0";
		}

		HRESULT const _hr = ::Render->shader_compile(name, (DWORD const*)data, size, c_entry, c_target,
		                                             D3D10_SHADER_PACK_MATRIX_ROW_MAJOR, (void*&)_ps);

		VERIFY(SUCCEEDED(_hr));

		CHECK_OR_EXIT(
			!FAILED(_hr),
			make_string("Shader compilation failed, check your log file for additional information.")
		);

		return _ps;
	}
}

void CResourceManager::_DeletePS(const SPS* ps)
{
	if (0 == (ps->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	LPSTR N = LPSTR(*ps->cName);
	map_PS::iterator I = m_ps.find(N);
	if (I != m_ps.end())
	{
		m_ps.erase(I);
		return;
	}
	Msg("! ERROR: Failed to find compiled pixel-shader '%s'", *ps->cName);
}

//--------------------------------------------------------------------------------------------------------------
SGS* CResourceManager::_CreateGS(LPCSTR name)
{
	xrCriticalSectionGuard guard(creationGuard);
	LPSTR N = LPSTR(name);
	map_GS::iterator I = m_gs.find(N);
	if (I != m_gs.end()) return I->second;
	else
	{
		SGS* _gs = xr_new<SGS>();
		_gs->dwFlags |= xr_resource_flagged::RF_REGISTERED;
		m_gs.insert(mk_pair(_gs->set_name(name), _gs));
		if (0 == stricmp(name, "null"))
		{
			_gs->gs = NULL;
			return _gs;
		}

		// Open file
		string_path cname;
		strconcat(sizeof(cname), cname, ::Render->getShaderPath(), name, ".gs");
		FS.update_path(cname, "$game_shaders$", cname);

		// duplicate and zero-terminate
		IReader* file = FS.r_open(cname);
		//	TODO: DX10: HACK: Implement all shaders. Remove this for PS
		if (!file)
		{
			string1024 tmp;
			//	TODO: HACK: Test failure
			//Memory.mem_compact();
			xr_sprintf(tmp, "DX10: %s is missing. Replace with stub_default.gs", cname);
			Msg(tmp);
			strconcat(sizeof(cname), cname, ::Render->getShaderPath(), "stub_default", ".gs");
			FS.update_path(cname, "$game_shaders$", cname);
			file = FS.r_open(cname);
		}

		R_ASSERT2(file, cname);

		// Select target
		LPCSTR c_target = "gs_4_0";
		LPCSTR c_entry = "main";

		HRESULT const _hr = ::Render->shader_compile(name, (DWORD const*)file->pointer(), file->length(), c_entry,
		                                             c_target, D3D10_SHADER_PACK_MATRIX_ROW_MAJOR, (void*&)_gs);

		VERIFY(SUCCEEDED(_hr));

		FS.r_close(file);

		CHECK_OR_EXIT(
			!FAILED(_hr),
			make_string("Shader compilation failed, check your log file for additional information.")
		);

		return _gs;
	}
}

void CResourceManager::_DeleteGS(const SGS* gs)
{
	if (0 == (gs->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	LPSTR N = LPSTR(*gs->cName);
	map_GS::iterator I = m_gs.find(N);
	if (I != m_gs.end())
	{
		m_gs.erase(I);
		return;
	}
	Msg("! ERROR: Failed to find compiled geometry shader '%s'", *gs->cName);
}

//--------------------------------------------------------------------------------------------------------------
static BOOL dcl_equal(D3DVERTEXELEMENT9* a, D3DVERTEXELEMENT9* b)
{
	// check sizes
	u32 a_size = D3DXGetDeclLength(a);
	u32 b_size = D3DXGetDeclLength(b);
	if (a_size != b_size) return FALSE;
	return 0 == memcmp(a, b, a_size * sizeof(D3DVERTEXELEMENT9));
}

SDeclaration* CResourceManager::_CreateDecl(D3DVERTEXELEMENT9* dcl)
{
	xrCriticalSectionGuard guard(creationGuard);
	// Search equal code
	for (u32 it = 0; it < v_declarations.size(); it++)
	{
		SDeclaration* D = v_declarations[it];;
		if (dcl_equal(dcl, &*D->dcl_code.begin())) return D;
	}

	// Create _new
	SDeclaration* D = xr_new<SDeclaration>();
	u32 dcl_size = D3DXGetDeclLength(dcl) + 1;
	//	Don't need it for DirectX 10 here
	//CHK_DX					(HW.pDevice->CreateVertexDeclaration(dcl,&D->dcl));
	D->dcl_code.assign(dcl, dcl + dcl_size);
	dx10BufferUtils::ConvertVertexDeclaration(D->dcl_code, D->dx10_dcl_code);
	D->dwFlags |= xr_resource_flagged::RF_REGISTERED;
	v_declarations.push_back(D);
	return D;
}

void CResourceManager::_DeleteDecl(const SDeclaration* dcl)
{
	if (0 == (dcl->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(v_declarations, dcl)) return;
	Msg("! ERROR: Failed to find compiled vertex-declarator");
}

//--------------------------------------------------------------------------------------------------------------
R_constant_table* CResourceManager::_CreateConstantTable(R_constant_table& C)
{
	if (C.empty())		return NULL;

	xrCriticalSectionGuard guard(creationGuard);

	for (u32 it = 0; it < v_constant_tables.size(); it++)
		if (v_constant_tables[it]->equal(C))
			return v_constant_tables[it];

	auto NewElem = xr_new<R_constant_table>(C);
	//NewElem->_copy(C);
	NewElem->dwFlags |= xr_resource_flagged::RF_REGISTERED;
	v_constant_tables.push_back(NewElem);
	return NewElem;

	return v_constant_tables.back();
}

void CResourceManager::_DeleteConstantTable(const R_constant_table* C)
{
	if (0 == (C->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(v_constant_tables, C)) return;
	Msg("! ERROR: Failed to find compiled constant-table");
}

//--------------------------------------------------------------------------------------------------------------
#ifdef USE_DX11
CRT* CResourceManager::_CreateRT(LPCSTR Name, u32 w, u32 h, D3DFORMAT f, u32 SampleCount, bool useUAV)
#else
CRT* CResourceManager::_CreateRT(LPCSTR Name, u32 w, u32 h, D3DFORMAT f, u32 SampleCount)
#endif
{
	R_ASSERT(Name && Name[0] && w && h);

	// ***** first pass - search already created RT
	LPSTR N = LPSTR(Name);
	xrCriticalSectionGuard guard(creationGuard);
	map_RT::iterator I = m_rtargets.find(N);
	if (I != m_rtargets.end()) return I->second;
	else
	{
		CRT* RT = xr_new<CRT>();
		RT->dwFlags |= xr_resource_flagged::RF_REGISTERED;
		m_rtargets.insert(mk_pair(RT->set_name(Name), RT));
#ifdef USE_DX11
		if (Device.b_is_Ready) RT->create(Name, w, h, f, SampleCount, useUAV);
#else
		if (Device.b_is_Ready) RT->create(Name, w, h, f, SampleCount);
#endif
		return RT;
	}
}

void CResourceManager::_DeleteRT(const CRT* RT)
{
	if (0 == (RT->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	LPSTR N = LPSTR(*RT->cName);
	xrCriticalSectionGuard guard(creationGuard);
	map_RT::iterator I = m_rtargets.find(N);
	if (I != m_rtargets.end())
	{
		m_rtargets.erase(I);
		return;
	}
	Msg("! ERROR: Failed to find render-target '%s'", *RT->cName);
}

//--------------------------------------------------------------------------------------------------------------
void CResourceManager::DBG_VerifyGeoms()
{
	/*
	for (u32 it=0; it<v_geoms.size(); it++)
	{
	SGeometry* G					= v_geoms[it];

	D3DVERTEXELEMENT9		test	[MAX_FVF_DECL_SIZE];
	u32						size	= 0;
	G->dcl->GetDeclaration			(test,(unsigned int*)&size);
	u32 vb_stride					= D3DXGetDeclVertexSize	(test,0);
	u32 vb_stride_cached			= G->vb_stride;
	R_ASSERT						(vb_stride == vb_stride_cached);
	}
	*/
}

SGeometry* CResourceManager::CreateGeom(D3DVERTEXELEMENT9* decl, ID3DVertexBuffer* vb, ID3DIndexBuffer* ib)
{
	xrCriticalSectionGuard guard(creationGuard);
	R_ASSERT(decl && vb);

	SDeclaration* dcl = _CreateDecl(decl);
	u32 vb_stride = D3DXGetDeclVertexSize(decl, 0);

	// ***** first pass - search already loaded shader
	for (u32 it = 0; it < v_geoms.size(); it++)
	{
		SGeometry& G = *(v_geoms[it]);
		if ((G.dcl == dcl) && (G.vb == vb) && (G.ib == ib) && (G.vb_stride == vb_stride)) return v_geoms[it];
	}

	SGeometry* Geom = xr_new<SGeometry>();
	Geom->dwFlags |= xr_resource_flagged::RF_REGISTERED;
	Geom->dcl = dcl;
	Geom->vb = vb;
	Geom->vb_stride = vb_stride;
	Geom->ib = ib;
	v_geoms.push_back(Geom);
	return Geom;
}

SGeometry* CResourceManager::CreateGeom(u32 FVF, ID3DVertexBuffer* vb, ID3DIndexBuffer* ib)
{
	D3DVERTEXELEMENT9 dcl [MAX_FVF_DECL_SIZE];
	xrCriticalSectionGuard guard(creationGuard);
	CHK_DX(D3DXDeclaratorFromFVF(FVF,dcl));
	SGeometry* g = CreateGeom(dcl, vb, ib);
	return g;
}

void CResourceManager::DeleteGeom(const SGeometry* Geom)
{
	if (0 == (Geom->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(v_geoms, Geom)) return;
	Msg("! ERROR: Failed to find compiled geometry-declaration");
}

//--------------------------------------------------------------------------------------------------------------
xr_task_group textures_load_tasks;
ref_texture CResourceManager::_CreateTexture(LPCSTR _Name)
{
	PROF_EVENT("_CreateTexture");
	// DBG_VerifyTextures	();
	if (0 == xr_strcmp(_Name, "null")) return 0;
	//Msg("texture %s", _Name);
	R_ASSERT(_Name && _Name[0]);
	string_path Name;
	xr_strcpy(Name, _Name); //. andy if (strext(Name)) *strext(Name)=0;
	xrCriticalSectionGuard guard(creationGuard);
	fix_texture_name(Name);
	// ***** first pass - search already loaded texture
	LPSTR N = LPSTR(Name);
	map_TextureIt I = m_textures.find(N);
	if (I != m_textures.end()) return I->second;
	else
	{
		CTexture* T = xr_new<CTexture>();
		T->dwFlags |= xr_resource_flagged::RF_REGISTERED;
		m_textures.insert(mk_pair(T->set_name(Name), T));
		T->Preload();
        const ref_texture result(T); // Own caller result before any worker can complete.
        if (Device.b_is_Ready) QueueTextureLoad(result);
        return result;
	}
}

void CResourceManager::QueueTextureLoad(const ref_texture &texture) {
  if (!texture)
    return;
  bool expected = false;
  if (!texture->loadQueued.compare_exchange_strong(expected, true,
                                                   std::memory_order_acq_rel))
    return;
  const DWORD caller = GetCurrentThreadId();
  bool accepted = false;
  try {
    accepted = pendingTextureLoads.Submit(
        texture, texture._get(),
        [](auto work) { textures_load_tasks.run(work); },
        [caller](const ref_texture &owner) {
          if (caller != GetCurrentThreadId()) {
            PROF_THREAD("X-Ray PPL Thread")
          }
          try {
            owner->Load();
          } catch (...) {
            owner->flags.bLoading = false;
            owner->loadQueued.store(false, std::memory_order_release);
            throw;
          }
          owner->loadQueued.store(false, std::memory_order_release);
        });
  } catch (...) {
    texture->loadQueued.store(false, std::memory_order_release);
    throw;
  }
  if (!accepted)
    texture->loadQueued.store(false, std::memory_order_release);
}
void CResourceManager::PrefetchTexture(LPCSTR name) {
  const auto texture = _CreateTexture(name);
  xrCriticalSectionGuard guard(creationGuard);
  if (texture && std::find(prefetchedTextures.begin(), prefetchedTextures.end(),
                           texture) == prefetchedTextures.end())
    prefetchedTextures.push_back(texture);
}
void CResourceManager::ReleasePrefetchedTextures() {
  xrCriticalSectionGuard guard(creationGuard);
  prefetchedTextures.clear();
}
void CResourceManager::CollectTextureLoads() {
  xrCriticalSectionGuard guard(creationGuard);
  pendingTextureLoads.Collect();
}
void CResourceManager::DrainTextureLoads(bool close) {
  if (close)
    pendingTextureLoads.Close();
  textures_load_tasks.wait();
  CollectTextureLoads();
}

namespace
{
std::atomic<u64> s_wait_us{0};
std::atomic<u32> s_wait_count{0};
std::atomic<u32> s_deferred{0};
xrCriticalSection s_worst_lock;
u64 s_worst_us = 0;
shared_str s_worst_name;

u32 s_residency_frame = u32(-1);
u32 s_deferred_window = 0;
u32 s_deferred_next_ms = 0;
#ifdef USE_DX11
u32 s_vram_next_ms = 0;
u32 s_pressure_next_ms = 0;
u32 s_class_sweep_next_ms = 0;
u32 s_swap_installed = 0;
u32 s_swap_dropped = 0;
u32 s_swap_log_next_ms = 0;
bool s_pressure_warned = false;
IDXGIAdapter3* s_adapter3 = nullptr;
bool s_adapter3_tried = false;

bool query_local_vram(DXGI_QUERY_VIDEO_MEMORY_INFO& local)
{
	if (!s_adapter3_tried)
	{
		s_adapter3_tried = true;
		if (HW.m_pAdapter)
			HW.m_pAdapter->QueryInterface(__uuidof(IDXGIAdapter3), (void**)&s_adapter3);
	}
	return s_adapter3 && SUCCEEDED(s_adapter3->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &local));
}

// Textures VRAM pressure must never unload: sky and weather, engine lookup tables, UI, render targets.
bool residency_pinned(LPCSTR name)
{
	return strncmp(name, "sky", 3) == 0 || strncmp(name, "shaders", 7) == 0 || strncmp(name, "ui\\", 3) == 0 ||
		strncmp(name, "ui/", 3) == 0 || strchr(name, '$') != nullptr;
}
#endif
}

void CResourceManager::NoteTextureWait(const CTexture* T, u64 us)
{
	s_wait_us.fetch_add(us, std::memory_order_relaxed);
	s_wait_count.fetch_add(1, std::memory_order_relaxed);
	xrCriticalSectionGuard guard(s_worst_lock);
	if (us > s_worst_us)
	{
		s_worst_us = us;
		s_worst_name = T->cName;
	}
}

void CResourceManager::NoteTextureDeferred()
{
	s_deferred.fetch_add(1, std::memory_order_relaxed);
}

void CResourceManager::ResidencyFrame()
{
	// Render() can run more than once per frame (scope viewport); report once.
	if (s_residency_frame == Device.dwFrame)
		return;
	s_residency_frame = Device.dwFrame;

	// Phase 1: install any LOD swaps a worker finished, at frame start as the plan requires.
	ApplyTextureSwaps();

	const u64 waited = s_wait_us.exchange(0, std::memory_order_relaxed);
	const u32 waits = s_wait_count.exchange(0, std::memory_order_relaxed);
	u64 worst;
	shared_str worst_name;
	{
		xrCriticalSectionGuard guard(s_worst_lock);
		worst = s_worst_us;
		worst_name = s_worst_name;
		s_worst_us = 0;
		s_worst_name = nullptr;
	}
	if (ps_r__tex_wait_log && waited >= u64(ps_r__tex_wait_log) * 1000)
		Msg("! [TexWait] frame %u: render thread waited %.1f ms on %u texture load(s), longest %.1f ms: %s",
			Device.dwFrame, float(waited) / 1000.f, waits, float(worst) / 1000.f,
			worst_name.size() ? worst_name.c_str() : "?");

	// Deferred binds are expected while new textures stream in; summarise once a second.
	s_deferred_window += s_deferred.exchange(0, std::memory_order_relaxed);
	if (Device.dwTimeGlobal >= s_deferred_next_ms)
	{
		if (s_deferred_window)
			Msg("* [TexWait] last second: %u bind(s) drew without a still-loading texture instead of waiting",
				s_deferred_window);
		s_deferred_window = 0;
		s_deferred_next_ms = Device.dwTimeGlobal + 1000;
	}

#ifdef USE_DX11
	const u32 now = Device.dwTimeGlobal;
	const bool log_due = ps_r__tex_vram_log && now >= s_vram_next_ms;
	const bool check_due = ps_r__tex_res_budget_target && now >= s_pressure_next_ms;

	// Phase 2: idle-age demotion, independent of VRAM pressure. Runs every 5s once any class
	// is configured; before the first texture's PostLoad() lazy-loads tex_residency.ltx,
	// m_tex_res_classes is empty and this is a no-op.
	if (!m_tex_res_classes.empty() && now >= s_class_sweep_next_ms)
	{
		TexResClassIdleSweep();
		s_class_sweep_next_ms = now + 5000;
	}

	DXGI_QUERY_VIDEO_MEMORY_INFO local = {};
	if (!(log_due || check_due) || !query_local_vram(local))
		return;
	if (check_due)
	{
		// DXGI usage lagged an unload pass by tens of seconds in game, so passes a second apart kept
		// unloading while usage sat flat and then overshot the target. Give each pass time to land.
		const bool unloaded = RelieveVramPressure(local.CurrentUsage, local.Budget);
		s_pressure_next_ms = now + (unloaded ? 10000 : 1000);
	}
	if (!log_due)
		return;
	s_vram_next_ms = now + u32(ps_r__tex_vram_log) * 1000;
	u64 tex_bytes = 0;
	u32 tex_count = 0;
	{
		xrCriticalSectionGuard guard(creationGuard);
		for (const auto& entry : m_textures)
		{
			// Staging textures not drawn yet live in system RAM, not VRAM.
			if (!entry.second->flags.bLoaded || entry.second->flags.bLoadedAsStaging)
				continue;
			tex_bytes += entry.second->flags.MemoryUsage;
			++tex_count;
		}
	}
	const u64 mb = 1024 * 1024;
	// Usage above budget means the driver is paging video memory out to system RAM, a stutter source.
	Msg("%s [TexVRAM] usage %llu MB of budget %llu MB (%.0f%%), %u textures in VRAM %llu MB",
		local.CurrentUsage > local.Budget ? "!" : "*", local.CurrentUsage / mb, local.Budget / mb,
		local.Budget ? 100.0 * double(local.CurrentUsage) / double(local.Budget) : 0.0, tex_count, tex_bytes / mb);
#endif
}

bool CResourceManager::RelieveVramPressure(u64 usage, u64 budget)
{
#ifdef USE_DX11
	const u64 target = budget / 100 * u64(ps_r__tex_res_budget_target);
	if (usage <= target)
	{
		s_pressure_warned = false;
		return false;
	}
	const u64 mb = 1024 * 1024;
	// Aim 5% of the budget below the target so the pass does not fire again next second.
	const u64 want = _min(usage - target + budget / 20, u64(ps_r__tex_res_batch_mb) * mb);
	const u32 now = Device.dwTimeGlobal;
	const u32 idle_ms = u32(ps_r__tex_res_idle_s) * 1000;

	// Held throughout, as in EvictStalledTextures: no texture can be destroyed under us.
	xrCriticalSectionGuard guard(creationGuard);
	xr_vector<std::pair<u32, CTexture*>> idle; // (ms since last drawn, texture)
	for (const auto& entry : m_textures)
	{
		CTexture* T = entry.second;
		// Not drawn yet (staging) means system RAM; unloading it frees no VRAM.
		if (!T->flags.bLoaded || T->flags.bLoadedAsStaging || T->flags.bUser || T->IsLoading())
			continue;
		if (now - T->dwLastUsedTime < idle_ms || residency_pinned(entry.first))
			continue;
		idle.emplace_back(now - T->dwLastUsedTime, T);
	}
	std::sort(idle.begin(), idle.end(), [](const auto& a, const auto& b) { return a.first > b.first; });

	u64 freed = 0;
	u32 count = 0;
	u32 demoted = 0;
	u32 youngest = 0;
	for (const auto& [age, T] : idle)
	{
		if (freed >= want)
			break;
		if (T->swapQueued.load(std::memory_order_acquire))
			continue; // a swap is already in flight; it will land on its own
		const u64 bytes = T->TrueBytes ? T->TrueBytes : T->flags.MemoryUsage;
		// Phase 2: a classified texture demotes toward its floor instead of a full unload - it
		// keeps drawing (blurrier) rather than needing a fresh reload on next use.
		if (T->ResClass >= 0 && T->RequestedLod < m_tex_res_classes[T->ResClass].floor_lod)
		{
			if (!QueueTextureSwap(ref_texture(T), m_tex_res_classes[T->ResClass].floor_lod))
				continue;
			// A floor-2 demote keeps about 1/16 of the bytes.
			freed += bytes - bytes / 16;
			++demoted;
		}
		else
		{
			if (T->ResClass >= 0)
				continue; // already at its floor: leave it drawing, don't unload a class texture
			freed += bytes;
			// The next bind queues an async reload; r__tex_nowait keeps that from stalling the frame.
			T->Unload();
		}
		youngest = age;
		++count;
	}

	if (count)
		Msg("* [TexRes] VRAM %llu of %llu MB, over the %d%% target: unloaded %u idle texture(s) (%u demoted instead), ~%llu MB, idle %u-%u s",
			usage / mb, budget / mb, ps_r__tex_res_budget_target, count - demoted, demoted, freed / mb, youngest / 1000,
			idle.front().first / 1000);
	else if (!s_pressure_warned)
		Msg("! [TexRes] VRAM %llu of %llu MB, over the %d%% target, but no texture has been idle for %d s",
			usage / mb, budget / mb, ps_r__tex_res_budget_target, ps_r__tex_res_idle_s);
	s_pressure_warned = !count;
	return count != 0;
#else
	return false;
#endif
}

bool CResourceManager::QueueTextureSwap(const ref_texture& texture, u32 new_lod)
{
#ifdef USE_DX11
	if (!texture || !texture->flags.bLoaded || texture->IsLoading())
		return false;
	if (texture->RequestedLod == new_lod && texture->TrueBytes)
		return false; // already at that LOD

	// swapQueued stays set from here until the render thread installs or drops the result
	// (ApplySwap / ApplyTextureSwaps). Clearing it any earlier let a second request load the
	// texture again and overwrite PendingSurface, leaking the first one.
	bool expected = false;
	if (!texture->swapQueued.compare_exchange_strong(expected, true, std::memory_order_acq_rel))
		return false;

	CResourceManager* self = this;
	textures_load_tasks.run([texture, new_lod, self]()
	{
		PROF_THREAD("X-Ray PPL Thread")

		u32 mem = 0;
		ID3DBaseTexture* surf = ::RImplementation.texture_load(*texture->cName, mem, true, int(new_lod));
		ID3DShaderResourceView* srv = nullptr;
		if (surf)
			HW.pDevice->CreateShaderResourceView(surf, NULL, &srv);

		texture->PendingSurface = surf;
		texture->PendingSRView = srv;
		texture->PendingLod = new_lod;

		xrCriticalSectionGuard guard(self->swapGuard);
		self->readySwaps.push_back(texture);
	});
	return true;
#else
	return false;
#endif
}

void CResourceManager::ApplyTextureSwaps()
{
#ifdef USE_DX11
	xr_vector<ref_texture> batch;
	{
		xrCriticalSectionGuard guard(swapGuard);
		batch.swap(readySwaps);
	}

	if (!batch.empty())
	{
		u32 applied = 0;
		u64 applied_bytes = 0;
		const u64 mb = 1024 * 1024;
		const u64 cap_bytes = u64(ps_r__tex_res_swap_mb) * mb;
		xr_vector<ref_texture> deferred;
		for (const auto& texture : batch)
		{
			if (!texture->PendingSurface)
			{
				// The worker's load failed: nothing to install, release the request.
				_RELEASE(texture->PendingSRView);
				texture->swapQueued.store(false, std::memory_order_release);
				++s_swap_dropped;
				continue;
			}
			if ((applied >= u32(ps_r__tex_res_swaps_per_frame)) || (applied && applied_bytes >= cap_bytes))
			{
				deferred.push_back(texture);
				continue;
			}
			const u64 before = texture->TrueBytes;
			texture->ApplySwap();
			const u64 after = texture->TrueBytes;
			applied_bytes += (before > after) ? (before - after) : (after - before);
			++applied;
		}
		s_swap_installed += applied;
		if (!deferred.empty())
		{
			xrCriticalSectionGuard guard(swapGuard);
			readySwaps.insert(readySwaps.end(), deferred.begin(), deferred.end());
		}
	}

	if (Device.dwTimeGlobal >= s_swap_log_next_ms)
	{
		if (s_swap_installed || s_swap_dropped)
		{
			size_t waiting;
			{
				xrCriticalSectionGuard guard(swapGuard);
				waiting = readySwaps.size();
			}
			Msg("* [TexRes] last 10 s: %u LOD swap(s) installed, %u failed, %u waiting to install",
				s_swap_installed, s_swap_dropped, (u32)waiting);
		}
		s_swap_installed = 0;
		s_swap_dropped = 0;
		s_swap_log_next_ms = Device.dwTimeGlobal + 10000;
	}

	// Selftest: queue the promote-back-to-full-detail half once its demote has had time to land.
	xr_vector<ref_texture> due;
	{
		xrCriticalSectionGuard guard(swapGuard);
		for (size_t i = 0; i < selftestPromoteAt.size();)
		{
			if (Device.dwTimeGlobal >= selftestPromoteAt[i].first)
			{
				due.push_back(selftestPromoteAt[i].second);
				selftestPromoteAt.erase(selftestPromoteAt.begin() + i);
			}
			else
				++i;
		}
	}
	for (const auto& texture : due)
		QueueTextureSwap(texture, 0);
#endif
}

void CResourceManager::TexResSelftest(u32 count)
{
#ifdef USE_DX11
	xr_vector<ref_texture> picked;
	{
		xrCriticalSectionGuard guard(creationGuard);
		for (const auto& entry : m_textures)
		{
			CTexture* T = entry.second;
			if (!T->flags.bLoaded || T->flags.bLoadedAsStaging || T->flags.bUser || T->IsLoading())
				continue;
			if (residency_pinned(entry.first))
				continue;
			picked.emplace_back(T);
			if (picked.size() >= count)
				break;
		}
	}

	if (picked.empty())
	{
		Msg("! [TexRes] selftest: no eligible loaded texture found");
		return;
	}

	const u32 promote_at = Device.dwTimeGlobal + 2000;
	{
		xrCriticalSectionGuard guard(swapGuard);
		for (const auto& texture : picked)
			selftestPromoteAt.emplace_back(promote_at, texture);
	}

	Msg("* [TexRes] selftest: demoting %u texture(s) by 2 LOD, promoting back to full in ~2s - watch for a blank frame",
		(u32)picked.size());
	for (const auto& texture : picked)
		QueueTextureSwap(texture, texture->RequestedLod + 2);
#endif
}

void CResourceManager::LoadTexResidencyClasses()
{
	// Caller holds texResInitGuard.

	string_path fname;
	FS.update_path(fname, "$game_config$", "tex_residency.ltx");
	if (!FS.exist(fname))
	{
		Msg("* [TexRes] no tex_residency.ltx found, Phase 2 classes disabled");
		return;
	}

	CInifile* ini = CInifile::Create(fname);
	for (auto& sect : ini->sections())
	{
		LPCSTR folders_str = nullptr;
		if (!sect.line_exist("folders", &folders_str) || !folders_str || !folders_str[0])
			continue;

		TexResClass cls;
		_ParseList(cls.folders, folders_str);

		LPCSTR val = nullptr;
		if (sect.line_exist("age", &val) && val && val[0])
			cls.age_ms = u32(atoi(val)) * 1000;
		if (sect.line_exist("floor", &val) && val && val[0])
			cls.floor_lod = u32(atoi(val));

		Msg("* [TexRes] class [%s]: %u folder(s), age %us, floor lod %u", sect.Name.c_str(),
			(u32)cls.folders.size(), cls.age_ms / 1000, cls.floor_lod);
		m_tex_res_classes.push_back(cls);
	}
	CInifile::Destroy(ini);
}

s8 CResourceManager::ClassifyTexture(const shared_str& name)
{
#ifdef USE_DX11
	// Deliberately not creationGuard - see the field comment in ResourceManager.h. Once ready,
	// m_tex_res_classes is read-only, so the common case after the first few loads takes no
	// lock at all.
	if (!m_tex_res_classes_ready.load(std::memory_order_acquire))
	{
		xrCriticalSectionGuard guard(texResInitGuard);
		if (!m_tex_res_classes_ready.load(std::memory_order_relaxed))
		{
			LoadTexResidencyClasses();
			m_tex_res_classes_ready.store(true, std::memory_order_release);
		}
	}

	if (m_tex_res_classes.empty() || !name.c_str())
		return -1;

	// folders are lowercased by _ParseList; match against a lowercased copy of the name too
	// (cName isn't guaranteed lowercase - texture_load() only lowercases its own local copy).
	string_path lower;
	xr_strcpy(lower, name.c_str());
	strlwr(lower);

	for (size_t i = 0; i < m_tex_res_classes.size(); ++i)
	{
		for (const auto& folder : m_tex_res_classes[i].folders)
			if (strstr(lower, folder.c_str()))
				return s8(i);
	}
	return -1;
#else
	return -1;
#endif
}

void CResourceManager::TexResClassIdleSweep()
{
#ifdef USE_DX11
	// Each demote is a full reload on a worker; cap a sweep so a level change (everything idle
	// at once) can't flood the load queue. The rest go on the next sweep, 5 s later.
	const u32 max_per_sweep = u32(ps_r__tex_res_swaps_per_frame) * 8;
	u32 queued = 0;
	const u32 now = Device.dwTimeGlobal;
	xrCriticalSectionGuard guard(creationGuard);
	for (const auto& entry : m_textures)
	{
		if (queued >= max_per_sweep)
			break;
		CTexture* T = entry.second;
		if (!T->flags.bLoaded || T->flags.bLoadedAsStaging || T->flags.bUser || T->IsLoading())
			continue;
		if (T->ResClass < 0 || T->swapQueued.load(std::memory_order_relaxed))
			continue;
		const TexResClass& cls = m_tex_res_classes[T->ResClass];
		if (T->RequestedLod >= cls.floor_lod)
			continue; // already at or past floor
		if (now - T->dwLastUsedTime < cls.age_ms)
			continue; // still active
		if (QueueTextureSwap(ref_texture(T), cls.floor_lod))
			++queued;
	}
#endif
}

void CResourceManager::DumpTextureResidency()
{
#ifdef USE_DX11
	struct Row
	{
		shared_str name;
		bool loaded;
		bool staging;
		u32 width, height, mips, array_size;
		u32 format;
		u64 true_bytes;
		u32 legacy_bytes;
		u32 idle_ms;
		s8 res_class;
		u32 requested_lod;
	};

	xr_vector<Row> rows;
	const u32 now = Device.dwTimeGlobal;
	{
		xrCriticalSectionGuard guard(creationGuard);
		rows.reserve(m_textures.size());
		for (const auto& entry : m_textures)
		{
			const CTexture* T = entry.second;
			const D3D_TEXTURE2D_DESC& d = T->get_desc_nowait();
			Row row;
			row.name = entry.first;
			row.loaded = T->flags.bLoaded != 0;
			row.staging = T->flags.bLoadedAsStaging != 0;
			row.width = d.Width;
			row.height = d.Height;
			row.mips = d.MipLevels;
			row.array_size = d.ArraySize;
			row.format = (u32)d.Format;
			row.true_bytes = T->TrueBytes;
			row.legacy_bytes = T->flags.MemoryUsage;
			row.idle_ms = now - T->dwLastUsedTime;
			row.res_class = T->ResClass;
			row.requested_lod = T->RequestedLod;
			rows.push_back(row);
		}
	}

	string64 stamp;
	string_path fname, path;
	xr_sprintf(fname, sizeof(fname), "tex_res_dump_%s.csv", timestamp(stamp));
	FS.update_path(path, "$logs$", fname);

	IWriter* W = FS.w_open(path);
	if (!W)
	{
		Msg("! [TexRes] dump: could not open [%s]", path);
		return;
	}

	W->w_string("name,loaded,staging,width,height,mips,array_size,format,true_bytes,legacy_bytes,idle_s,class,req_lod");
	u64 total_true = 0, total_legacy = 0;
	u32 loaded_count = 0;
	string1024 line;
	for (const auto& row : rows)
	{
		xr_sprintf(line, sizeof(line), "%s,%d,%d,%u,%u,%u,%u,%u,%llu,%u,%.1f,%d,%u",
			row.name.c_str(), row.loaded ? 1 : 0, row.staging ? 1 : 0,
			row.width, row.height, row.mips, row.array_size, row.format,
			row.true_bytes, row.legacy_bytes, row.idle_ms / 1000.0f, row.res_class, row.requested_lod);
		W->w_string(line);
		if (row.loaded)
		{
			total_true += row.true_bytes;
			total_legacy += row.legacy_bytes;
			++loaded_count;
		}
	}
	FS.w_close(W);

	const u64 mb = 1024 * 1024;
	Msg("* [TexRes] dump: %u textures (%u loaded), true %llu MB, legacy %llu MB, wrote [%s]",
		(u32)rows.size(), loaded_count, total_true / mb, total_legacy / mb, path);
#endif
}

void CResourceManager::_DeleteTexture(const CTexture* T)
{
	// DBG_VerifyTextures	();

	if (0 == (T->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	LPSTR N = LPSTR(*T->cName);
	map_Texture::iterator I = m_textures.find(N);
	if (I != m_textures.end())
	{
		m_textures.erase(I);
		return;
	}
	Msg("! ERROR: Failed to find texture surface '%s'", *T->cName);
}

CTexture* CResourceManager::_FindTexture(LPCSTR _Name)
{
	if (!_Name || !_Name[0]) return 0;
	if (0 == xr_strcmp(_Name, "null")) return 0;

	string_path Name;
	xr_strcpy(Name, _Name);
	fix_texture_name(Name);

	xrCriticalSectionGuard guard(creationGuard);
	map_TextureIt I = m_textures.find(LPSTR(Name));
	return I != m_textures.end() ? I->second : 0;
}

#ifdef DEBUG
void	CResourceManager::DBG_VerifyTextures	()
{
	map_Texture::iterator I		= m_textures.begin	();
	map_Texture::iterator E		= m_textures.end	();
	for (; I!=E; I++) 
	{
		R_ASSERT(I->first);
		R_ASSERT(I->second);
		R_ASSERT(I->second->cName);
		R_ASSERT(0==xr_strcmp(I->first,*I->second->cName));
	}
}
#endif

//--------------------------------------------------------------------------------------------------------------
CMatrix* CResourceManager::_CreateMatrix(LPCSTR Name)
{
	R_ASSERT(Name && Name[0]);
	if (0 == stricmp(Name, "$null")) return NULL;

	LPSTR N = LPSTR(Name);
	xrCriticalSectionGuard guard(creationGuard);
	map_Matrix::iterator I = m_matrices.find(N);
	if (I != m_matrices.end()) return I->second;
	else
	{
		CMatrix* M = xr_new<CMatrix>();
		M->dwFlags |= xr_resource_flagged::RF_REGISTERED;
		M->dwReference.store(1, std::memory_order_relaxed);
		m_matrices.insert(mk_pair(M->set_name(Name), M));
		return M;
	}
}

void CResourceManager::_DeleteMatrix(const CMatrix* M)
{
	if (0 == (M->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	LPSTR N = LPSTR(*M->cName);
	map_Matrix::iterator I = m_matrices.find(N);
	if (I != m_matrices.end())
	{
		m_matrices.erase(I);
		return;
	}
	Msg("! ERROR: Failed to find xform-def '%s'", *M->cName);
}

//--------------------------------------------------------------------------------------------------------------
CConstant* CResourceManager::_CreateConstant(LPCSTR Name)
{
	R_ASSERT(Name && Name[0]);
	if (0 == stricmp(Name, "$null")) return NULL;

	LPSTR N = LPSTR(Name);
	xrCriticalSectionGuard guard(creationGuard);
	map_Constant::iterator I = m_constants.find(N);
	if (I != m_constants.end()) return I->second;
	else
	{
		CConstant* C = xr_new<CConstant>();
		C->dwFlags |= xr_resource_flagged::RF_REGISTERED;
		C->dwReference.store(1, std::memory_order_relaxed);
		m_constants.insert(mk_pair(C->set_name(Name), C));
		return C;
	}
}

void CResourceManager::_DeleteConstant(const CConstant* C)
{
	if (0 == (C->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	LPSTR N = LPSTR(*C->cName);
	map_Constant::iterator I = m_constants.find(N);
	if (I != m_constants.end())
	{
		m_constants.erase(I);
		return;
	}
	Msg("! ERROR: Failed to find R1-constant-def '%s'", *C->cName);
}

//--------------------------------------------------------------------------------------------------------------
bool cmp_tl(const std::pair<u32, ref_texture>& _1, const std::pair<u32, ref_texture>& _2)
{
	return _1.first < _2.first;
}

STextureList* CResourceManager::_CreateTextureList(STextureList& L)
{
	xrCriticalSectionGuard guard(creationGuard);
	std::sort(L.begin(), L.end(), cmp_tl);
	for (u32 it = 0; it < lst_textures.size(); it++)
	{
		STextureList* base = lst_textures[it];
		if (L.equal(*base)) return base;
	}
	STextureList* lst = xr_new<STextureList>(L);
	//lst->_copy(L);
	lst->dwFlags |= xr_resource_flagged::RF_REGISTERED;

	lst_textures.push_back(lst);
	return lst;
}

void CResourceManager::_DeleteTextureList(const STextureList* L)
{
	if (0 == (L->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(lst_textures, L)) return;
	Msg("! ERROR: Failed to find compiled list of textures");
}

//--------------------------------------------------------------------------------------------------------------
SMatrixList* CResourceManager::_CreateMatrixList(SMatrixList& L)
{
	BOOL bEmpty = TRUE;
	for (u32 i = 0; i < L.size(); i++)
		if (L[i])
		{
			bEmpty = FALSE;
			break;
		}
	if (bEmpty) return NULL;

	xrCriticalSectionGuard guard(creationGuard);

	for (u32 it = 0; it < lst_matrices.size(); it++)
	{
		SMatrixList* base = lst_matrices[it];
		if (L.equal(*base)) return base;
	}
	SMatrixList* lst = xr_new<SMatrixList>(L);
	//lst->_copy(L);

	lst->dwFlags |= xr_resource_flagged::RF_REGISTERED;
	lst_matrices.push_back(lst);
	return lst;
}

void CResourceManager::_DeleteMatrixList(const SMatrixList* L)
{
	if (0 == (L->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(lst_matrices, L)) return;
	Msg("! ERROR: Failed to find compiled list of xform-defs");
}

//--------------------------------------------------------------------------------------------------------------
SConstantList* CResourceManager::_CreateConstantList(SConstantList& L)
{
	BOOL bEmpty = TRUE;
	for (u32 i = 0; i < L.size(); i++)
		if (L[i])
		{
			bEmpty = FALSE;
			break;
		}
	if (bEmpty) return NULL;

	xrCriticalSectionGuard guard(creationGuard);

	for (u32 it = 0; it < lst_constants.size(); it++)
	{
		SConstantList* base = lst_constants[it];
		if (L.equal(*base)) return base;
	}
	SConstantList* lst = xr_new<SConstantList>(L);
	//lst->_copy(L);

	lst->dwFlags |= xr_resource_flagged::RF_REGISTERED;
	lst_constants.push_back(lst);
	return lst;
}

void CResourceManager::_DeleteConstantList(const SConstantList* L)
{
	if (0 == (L->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(lst_constants, L)) return;
	Msg("! ERROR: Failed to find compiled list of r1-constant-defs");
}

//--------------------------------------------------------------------------------------------------------------
dx10ConstantBuffer* CResourceManager::_CreateConstantBuffer(ID3DShaderReflectionConstantBuffer* pTable)
{
	VERIFY(pTable);
	xrCriticalSectionGuard guard(creationGuard);
	dx10ConstantBuffer* pTempBuffer = xr_new<dx10ConstantBuffer>(pTable);

	for (u32 it = 0; it < v_constant_buffer.size(); it++)
	{
		dx10ConstantBuffer* buf = v_constant_buffer[it];
		if (pTempBuffer->Similar(*buf))
		{
			xr_delete(pTempBuffer);
			return buf;
		}
	}

	pTempBuffer->dwFlags |= xr_resource_flagged::RF_REGISTERED;
	v_constant_buffer.push_back(pTempBuffer);
	return pTempBuffer;
}

//--------------------------------------------------------------------------------------------------------------
void CResourceManager::_DeleteConstantBuffer(const dx10ConstantBuffer* pBuffer)
{
	if (0 == (pBuffer->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(v_constant_buffer, pBuffer)) return;
	Msg("! ERROR: Failed to find compiled constant buffer");
}

//--------------------------------------------------------------------------------------------------------------
SInputSignature* CResourceManager::_CreateInputSignature(ID3DBlob* pBlob)
{
	VERIFY(pBlob);
	xrCriticalSectionGuard guard(creationGuard);

	for (u32 it = 0; it < v_input_signature.size(); it++)
	{
		SInputSignature* sign = v_input_signature[it];
		if ((pBlob->GetBufferSize() == sign->signature->GetBufferSize()) &&
			(!(memcmp(pBlob->GetBufferPointer(), sign->signature->GetBufferPointer(), pBlob->GetBufferSize()))))
		{
			return sign;
		}
	}

	SInputSignature* pSign = xr_new<SInputSignature>(pBlob);

	pSign->dwFlags |= xr_resource_flagged::RF_REGISTERED;
	v_input_signature.push_back(pSign);

	return pSign;
}

//--------------------------------------------------------------------------------------------------------------
void CResourceManager::_DeleteInputSignature(const SInputSignature* pSignature)
{
	if (0 == (pSignature->dwFlags & xr_resource_flagged::RF_REGISTERED)) return;
	xrCriticalSectionGuard guard(creationGuard);
	if (reclaim(v_input_signature, pSignature)) return;
	Msg("! ERROR: Failed to find compiled constant buffer");
}
