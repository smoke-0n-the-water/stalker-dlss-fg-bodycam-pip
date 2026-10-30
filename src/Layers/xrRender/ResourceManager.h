// TextureManager.h: interface for the CTextureManager class.
//
//////////////////////////////////////////////////////////////////////

#ifndef ResourceManagerH
#define ResourceManagerH
#pragma once

#include	"shader.h"
#if defined(USE_DX10) || defined(USE_DX11)
#include "texture_load_lifetime.h"
#endif
#include	"tss_def.h"
#include	"TextureDescrManager.h"
// refs
struct lua_State;

class dx10ConstantBuffer;

// Phase 2: one tex_residency.ltx class ([weapon], [character], ...). Each folder matches a whole
// path segment of the texture name ("act" matches act\... and ...\act\..., not "impact"). age is
// how long undrawn before it demotes to floor via a Phase 1 swap; hold is how long after a
// promote it may not demote again, so textures going in and out of view don't ping-pong.
struct TexResClass
{
	sh_list folders;
	u32 age_ms = 120000;
	u32 hold_ms = 300000;
	u32 floor_lod = 2;
};

// defs
class ECORE_API CResourceManager
{
private:
	struct str_pred
	{
		IC bool operator()(LPCSTR x, LPCSTR y) const
		{
			return xr_strcmp(x, y) < 0;
		}
	};

	struct texture_detail
	{
		const char* T;
		R_constant_setup* cs;
	};

public:
	DEFINE_MAP_PRED(const char*, IBlender*, map_Blender, map_BlenderIt, str_pred);
	DEFINE_MAP_PRED(const char*, CTexture*, map_Texture, map_TextureIt, str_pred);
	DEFINE_MAP_PRED(const char*, CMatrix*, map_Matrix, map_MatrixIt, str_pred);
	DEFINE_MAP_PRED(const char*, CConstant*, map_Constant, map_ConstantIt, str_pred);
	DEFINE_MAP_PRED(const char*, CRT*, map_RT, map_RTIt, str_pred);
	//	DX10 cut DEFINE_MAP_PRED(const char*,CRTC*,			map_RTC,		map_RTCIt,			str_pred);
	DEFINE_MAP_PRED(const char*, SVS*, map_VS, map_VSIt, str_pred);
#if defined(USE_DX10) || defined(USE_DX11)
	DEFINE_MAP_PRED(const char*,SGS*,			map_GS,			map_GSIt,			str_pred);
#endif	//	USE_DX10
#ifdef USE_DX11
	DEFINE_MAP_PRED(const char*, SHS*,			map_HS,			map_HSIt,			str_pred);
	DEFINE_MAP_PRED(const char*, SDS*,			map_DS,			map_DSIt,			str_pred);
	DEFINE_MAP_PRED(const char*, SCS*,			map_CS,			map_CSIt,			str_pred);
#endif

	DEFINE_MAP_PRED(const char*, SPS*, map_PS, map_PSIt, str_pred);
	DEFINE_MAP_PRED(const char*, texture_detail, map_TD, map_TDIt, str_pred);
private:
	// data
	map_Blender m_blenders;
	map_Texture m_textures;
	map_Matrix m_matrices;
	map_Constant m_constants;
	map_RT m_rtargets;
	//	DX10 cut map_RTC												m_rtargets_c;
	map_VS m_vs;
	map_PS m_ps;
#if defined(USE_DX10) || defined(USE_DX11)
	map_GS												m_gs;
#endif	//	USE_DX10
	map_TD m_td;

	xr_vector<SState*> v_states;
	xr_vector<SDeclaration*> v_declarations;
	xr_vector<SGeometry*> v_geoms;
	xr_vector<R_constant_table*> v_constant_tables;

#if defined(USE_DX10) || defined(USE_DX11)
	xr_vector<dx10ConstantBuffer*>						v_constant_buffer;
	xr_vector<SInputSignature*>							v_input_signature;
#endif	//	USE_DX10

	// lists
	xr_vector<STextureList*> lst_textures;
	xr_vector<SMatrixList*> lst_matrices;
	xr_vector<SConstantList*> lst_constants;

	// main shader-array
	xr_vector<SPass*> v_passes;
	xr_vector<ShaderElement*> v_elements;
	xr_vector<Shader*> v_shaders;

	xr_vector<ref_texture> m_necessary;
#if defined(USE_DX10) || defined(USE_DX11)
    TextureLoadLifetime::Queue<ref_texture> pendingTextureLoads;
    xr_vector<ref_texture> prefetchedTextures;
    // Phase 1 LOD swap primitive: textures whose worker reload finished, waiting for the
    // render thread to install them, and the selftest's pending demote->promote deadlines.
    xrCriticalSection swapGuard;
    xr_vector<ref_texture> readySwaps;
    xr_vector<std::pair<u32, ref_texture>> selftestPromoteAt;
    // Phase 2: classes parsed from tex_residency.ltx, loaded lazily on first ClassifyTexture()
    // call. Deliberately its OWN lock, not creationGuard: ClassifyTexture() runs from every
    // texture's PostLoad(), often from many worker threads in parallel during a level's mass
    // texture load, and creationGuard is the same lock _CreateTexture() needs for every new
    // texture - sharing it serialized classification against texture creation itself and
    // stalled level loads. m_tex_res_classes is written once, then read-only: safe to read
    // without any lock once the ready flag is set.
    xrCriticalSection texResInitGuard;
    std::atomic<bool> m_tex_res_classes_ready{false};
    xr_vector<TexResClass> m_tex_res_classes;
#endif
	// misc
	xrCriticalSection creationGuard;

public:
	CTextureDescrMngr m_textures_description;
	xr_vector<std::pair<shared_str, R_constant_setup*>> v_constant_setup;
	lua_State* LSVM;
	BOOL bDeferredLoad;
private:
	void LS_Load();
	void LS_Unload();
public:
	// Miscelaneous
	void _ParseList(sh_list& dest, LPCSTR names);
	IBlender* _GetBlender(LPCSTR Name);
	IBlender* _FindBlender(LPCSTR Name);
	void _GetMemoryUsage(u32& m_base, u32& c_base, u32& m_lmaps, u32& c_lmaps);
	void _DumpMemoryUsage();
	//.	BOOL							_GetDetailTexture	(LPCSTR Name, LPCSTR& T, R_constant_setup* &M);

	map_Blender& _GetBlenders() { return m_blenders; }

	// Debug
	void DBG_VerifyGeoms();
	void DBG_VerifyTextures();

	// Editor cooperation
	void ED_UpdateBlender(LPCSTR Name, IBlender* data);
#ifdef _EDITOR
	void							ED_UpdateTextures	(AStringVec* names);
#endif

	// Low level resource creation
#if defined(USE_DX10) || defined(USE_DX11)
    ref_texture _CreateTexture(LPCSTR Name);
    void QueueTextureLoad(const ref_texture& texture);
    void CollectTextureLoads();
    void PrefetchTexture(LPCSTR name);
    void ReleasePrefetchedTextures();
    void DrainTextureLoads(bool close=false);
#else
    CTexture* _CreateTexture(LPCSTR Name);
#endif
	CTexture* _FindTexture(LPCSTR Name);
	void _DeleteTexture(const CTexture* T);

	CMatrix* _CreateMatrix(LPCSTR Name);
	void _DeleteMatrix(const CMatrix* M);

	CConstant* _CreateConstant(LPCSTR Name);
	void _DeleteConstant(const CConstant* C);

	R_constant_table* _CreateConstantTable(R_constant_table& C);
	void _DeleteConstantTable(const R_constant_table* C);

#if defined(USE_DX10) || defined(USE_DX11)
	dx10ConstantBuffer*				_CreateConstantBuffer(ID3DShaderReflectionConstantBuffer* pTable);
	void							_DeleteConstantBuffer(const dx10ConstantBuffer* pBuffer);

	SInputSignature*				_CreateInputSignature(ID3DBlob* pBlob);
	void							_DeleteInputSignature(const SInputSignature* pSignature);
#endif	//	USE_DX10

#ifdef USE_DX11
	CRT*							_CreateRT			(LPCSTR Name, u32 w, u32 h,	D3DFORMAT f, u32 SampleCount = 1, bool useUAV=false );
#else
	CRT* _CreateRT(LPCSTR Name, u32 w, u32 h, D3DFORMAT f, u32 SampleCount = 1);
#endif
	void _DeleteRT(const CRT* RT);

	//	DX10 cut CRTC*							_CreateRTC			(LPCSTR Name, u32 size,	D3DFORMAT f);
	//	DX10 cut void							_DeleteRTC			(const CRTC*	RT	);
#if defined(USE_DX10) || defined(USE_DX11)
	SGS*							_CreateGS			(LPCSTR Name);
	void							_DeleteGS			(const SGS*	GS	);
#endif	//	USE_DX10

#ifdef USE_DX11
	SHS*							_CreateHS			(LPCSTR Name);
	void							_DeleteHS			(const SHS*	HS	);

	SDS*							_CreateDS			(LPCSTR Name);
	void							_DeleteDS			(const SDS*	DS	);

    SCS*							_CreateCS			(LPCSTR Name);
	void							_DeleteCS			(const SCS*	CS	);
#endif	//	USE_DX10

	SPS* _CreatePS(LPCSTR Name);
	void _DeletePS(const SPS* PS);

	SVS* _CreateVS(LPCSTR Name);
	void _DeleteVS(const SVS* VS);

	SPass* _CreatePass(const SPass& proto);
	void _DeletePass(const SPass* P);

	// Shader compiling / optimizing
	SState* _CreateState(SimulatorStates& Code);
	void _DeleteState(const SState* SB);

	SDeclaration* _CreateDecl(D3DVERTEXELEMENT9* dcl);
	void _DeleteDecl(const SDeclaration* dcl);

	STextureList* _CreateTextureList(STextureList& L);
	void _DeleteTextureList(const STextureList* L);

	SMatrixList* _CreateMatrixList(SMatrixList& L);
	void _DeleteMatrixList(const SMatrixList* L);

	Shader* _CreateShader(Shader* InShader);

	SConstantList* _CreateConstantList(SConstantList& L);
	void _DeleteConstantList(const SConstantList* L);

	ShaderElement* _CreateElement(ShaderElement& L);
	void _DeleteElement(const ShaderElement* L);

	Shader* _cpp_Create(LPCSTR s_shader, LPCSTR s_textures = 0, LPCSTR s_constants = 0, LPCSTR s_matrices = 0);
	Shader* _cpp_Create(IBlender* B, LPCSTR s_shader = 0, LPCSTR s_textures = 0, LPCSTR s_constants = 0,
	                    LPCSTR s_matrices = 0);
	Shader* _lua_Create(LPCSTR s_shader, LPCSTR s_textures);
	BOOL _lua_HasShader(LPCSTR s_shader);

	CResourceManager() : bDeferredLoad(TRUE)
	{
	}

	~CResourceManager();

	void OnDeviceCreate(IReader* F);
	void OnDeviceCreate(LPCSTR name);
	void OnDeviceDestroy(BOOL bKeepTextures);

	void reset_begin();
	void reset_end();

	// Creation/Destroying
	Shader* Create(LPCSTR s_shader = 0, LPCSTR s_textures = 0, LPCSTR s_constants = 0, LPCSTR s_matrices = 0);
	Shader* Create(IBlender* B, LPCSTR s_shader = 0, LPCSTR s_textures = 0, LPCSTR s_constants = 0,
	               LPCSTR s_matrices = 0);
	void Delete(const Shader* S);

	void RegisterConstantSetup(LPCSTR name, R_constant_setup* s)
	{
		v_constant_setup.push_back(mk_pair(shared_str(name), s));
	}

	SGeometry* CreateGeom(D3DVERTEXELEMENT9* decl, ID3DVertexBuffer* vb, ID3DIndexBuffer* ib);
	SGeometry* CreateGeom(u32 FVF, ID3DVertexBuffer* vb, ID3DIndexBuffer* ib);
	void DeleteGeom(const SGeometry* VS);
	void DeferredLoad(BOOL E) { bDeferredLoad = E; }
	void DeferredUpload();
	void DeferredUnload();
	void UnloadAllTexturesOnLevelUnload();
	void Evict();
    void EvictStalledTextures();
    // Render-thread texture wait telemetry; ResidencyFrame() runs once per frame.
    void NoteTextureWait(const CTexture* T, u64 us);
    void NoteTextureDeferred();
    void ResidencyFrame();
    bool RelieveVramPressure(u64 usage, u64 budget); // true when it unloaded something
    // Phase 0 accounting: dump every tracked texture's true bytes/state to a CSV in $logs$.
    void DumpTextureResidency();
    // Phase 1 LOD swap primitive. QueueTextureSwap submits a worker reload at new_lod into
    // the texture's Pending* fields; ApplyTextureSwaps (render-thread only, called from
    // ResidencyFrame at frame start) installs a capped batch via CTexture::ApplySwap().
    bool QueueTextureSwap(const ref_texture& texture, u32 new_lod); // false: not queued (already pending/at lod)
    void ApplyTextureSwaps();
    void TexResSelftest(u32 count); // demotes then promotes back N loaded textures, console-driven
    // Phase 2: classes + idle demotion. ClassifyTexture lazy-loads tex_residency.ltx on first
    // call; PostLoad() caches the result on each CTexture. TexResClassIdleSweep (periodic, from
    // ResidencyFrame) demotes classified textures idle past their class's age.
    void LoadTexResidencyClasses(); // caller must hold texResInitGuard
    s8 ClassifyTexture(const shared_str& name);
    void TexResClassIdleSweep();
	void StoreNecessaryTextures();
	void DestroyNecessaryTextures();
	void Dump(bool bBrief);

private:
#ifdef USE_DX11
	map_DS	m_ds;
	map_HS	m_hs;
	map_CS	m_cs;

	template<typename T>
	T& GetShaderMap();

	template<typename T>
	T* CreateShader(const char* name);

	template<typename T>
	void DestroyShader(const T* sh);

#endif	//	USE_DX10
};

#endif //ResourceManagerH
