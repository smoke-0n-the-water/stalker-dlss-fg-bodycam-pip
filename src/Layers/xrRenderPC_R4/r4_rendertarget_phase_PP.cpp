#include "stdafx.h"
#ifdef XR_DX12_BRIDGE
#include "Dlss/FrameGeneration.h"
#endif
#include "r4_rendertarget.h"
#include "../../xrEngine/CustomHUD.h"
#include "../../xrEngine/igame_persistent.h"
#include "../../xrEngine/environment.h"

void CRenderTarget::u_calc_tc_noise(Fvector2& p0, Fvector2& p1)
{
	CTexture* T = RCache.get_ActiveTexture(2);
	VERIFY2(T, "Texture #3 in noise shader should be setted up");
	u32 tw = iCeil(float(T->get_Width()) * param_noise_scale + EPS_S);
	u32 th = iCeil(float(T->get_Height()) * param_noise_scale + EPS_S);
	VERIFY2(tw && th, "Noise scale can't be zero in any way");

	// calculate shift from FPSes
	im_noise_time -= Device.fTimeDelta;
	if (im_noise_time < 0)
	{
		im_noise_shift_w = ::Random.randI(tw ? tw : 1);
		im_noise_shift_h = ::Random.randI(th ? th : 1);
		float fps_time = 1 / param_noise_fps;
		while (im_noise_time < 0) im_noise_time += fps_time;
	}

	u32 shift_w = im_noise_shift_w;
	u32 shift_h = im_noise_shift_h;
	float start_u = (float(shift_w) + .5f) / (tw);
	float start_v = (float(shift_h) + .5f) / (th);
	u32 _w = Device.dwWidth;
	u32 _h = Device.dwHeight;
	u32 cnt_w = _w / tw;
	u32 cnt_h = _h / th;
	float end_u = start_u + float(cnt_w) + 1;
	float end_v = start_v + float(cnt_h) + 1;

	p0.set(start_u, start_v);
	p1.set(end_u, end_v);
}

void CRenderTarget::u_calc_tc_duality_ss(Fvector2& r0, Fvector2& r1, Fvector2& l0, Fvector2& l1)
{
	// Calculate ordinaty TCs from blur and SS
	float tw = float(dwWidth);
	float th = float(dwHeight);
	if (dwHeight != Device.dwHeight) param_blur = 1.f;
	Fvector2 shift, p0, p1;
	shift.set(.5f / tw, .5f / th);
	shift.mul(param_blur);
	p0.set(.5f / tw, .5f / th).add(shift);
	p1.set((tw + .5f) / tw, (th + .5f) / th).add(shift);

	// Calculate Duality TC
	float shift_u = param_duality_h * .5f;
	float shift_v = param_duality_v * .5f;

	r0.set(p0.x, p0.y);
	r1.set(p1.x - shift_u, p1.y - shift_v);
	l0.set(p0.x + shift_u, p0.y + shift_v);
	l1.set(p1.x, p1.y);
}

BOOL CRenderTarget::u_need_PP()
{
	bool _blur = (param_blur > 0.001f);
	bool _gray = (param_gray > 0.001f);
	bool _noise = (param_noise > 0.001f);
	bool _dual = (param_duality_h > 0.001f) || (param_duality_v > 0.001f);

	// bool	_menu_pp= g_pGamePersistent?g_pGamePersistent->OnRenderPPUI_query():false;

	bool _cbase = false;
	{
		int _r = color_get_R(param_color_base);
		_r = _abs(_r - int(0x7f));
		int _g = color_get_G(param_color_base);
		_g = _abs(_g - int(0x7f));
		int _b = color_get_B(param_color_base);
		_b = _abs(_b - int(0x7f));
		if (_r > 2 || _g > 2 || _b > 2) _cbase = true;
	}
	bool _cadd = false;
	{
		//int		_r	= color_get_R(param_color_add)	;
		//int		_g	= color_get_G(param_color_add)	;
		//int		_b	= color_get_B(param_color_add)	;
		//if (_r>2 || _g>2 || _b>2)	_cadd	= true	;
		int _r = _abs((int)(param_color_add.x * 255));
		int _g = _abs((int)(param_color_add.y * 255));
		int _b = _abs((int)(param_color_add.z * 255));
		if (_r > 2 || _g > 2 || _b > 2) _cadd = true;
	}
	return _blur || _gray || _noise || _dual || _cbase || _cadd || u_need_CM();
}

bool CRenderTarget::u_need_CM()
{
	return (param_color_map_influence > 0.001f);
}

struct TL_2c3uv
{
	Fvector4 p;
	u32 color0;
	u32 color1;
	Fvector2 uv [3];
	IC void set(float x, float y, u32 c0, u32 c1, float u0, float v0, float u1, float v1, float u2, float v2)
	{
		p.set(x, y, EPS_S, 1.f);
		color0 = c0;
		color1 = c1;
		uv[0].set(u0, v0);
		uv[1].set(u1, v1);
		uv[2].set(u2, v2);
	}
};

ref_rt& CRenderTarget::PostprocessColor()
{
	return dlss::Configured() ? rt_dlss_post_color : (RImplementation.o.dx10_msaa ? rt_Generic : rt_Color);
}

ref_rt& CRenderTarget::PostprocessSource()
{
	return dlss::Configured() ? rt_dlss_post_source : rt_Generic_0;
}

// Fills the zero motion-vector pixels the shader pack left with camera-only
// vectors rebuilt from the scene depth; the SSS buffer stays untouched.
ref_rt& CRenderTarget::phase_upscaler_camera_mv()
{
	if (this != RImplementation.TargetMain || !s_upscaler_camera_mv || !rt_upscaler_camera_mv
		|| ps_r__upscaler_camera_mv <= 0 || !dlss::Active())
		return rt_ssfx_motion_vectors;

	D3D_VIEWPORT saved[1];
	UINT savedCount = 1;
	HW.pContext->RSGetViewports(&savedCount, saved);

	u_setrt(rt_upscaler_camera_mv, nullptr, nullptr, nullptr);
	RImplementation.rmNormal();
	RCache.set_CullMode(CULL_NONE);
	RCache.set_Stencil(FALSE);
	RCache.set_ColorWriteEnable();
	set_viewport_size(HW.pContext, float(dlss::RenderWidth()), float(dlss::RenderHeight()));
	u32 offset;
	const float w = float(dlss::RenderWidth()), h = float(dlss::RenderHeight());
	FVF::TL* vertices = (FVF::TL*)RCache.Vertex.Lock(4, g_combine->vb_stride, offset);
	vertices[0].set(0, h, EPS_S, 1, 0xffffffff, 0, 1);
	vertices[1].set(0, 0, EPS_S, 1, 0xffffffff, 0, 0);
	vertices[2].set(w, h, EPS_S, 1, 0xffffffff, 1, 1);
	vertices[3].set(w, 0, EPS_S, 1, 0xffffffff, 1, 0);
	RCache.Vertex.Unlock(4, g_combine->vb_stride);
	RCache.set_Element(s_upscaler_camera_mv->E[0]);
	RCache.set_c("upscaler_camera_mv_mode", float(ps_r__upscaler_camera_mv), 0.f, 0.f, 0.f);
	RCache.set_Geometry(g_combine);
	RCache.Render(D3DPT_TRIANGLELIST, offset, 0, 4, 0, 2);

	HW.pContext->RSSetViewports(savedCount, saved);
	if (!reported_camera_mv)
	{
		reported_camera_mv = true;
		Msg("[Upscaler] camera MV fallback active: mode=%d%s", ps_r__upscaler_camera_mv,
			ps_r__upscaler_camera_mv == 1 ? " (filling zero vectors)" : " (camera-only)");
	}
	return rt_upscaler_camera_mv;
}
void CRenderTarget::phase_dlss_postprocess()
{
#ifdef XR_DX12_BRIDGE
    // Main target only. fg::CaptureScene guards with IsSVPFrame(), but upstream
    // reaches this function for the main target alone, while our base also runs
    // it for the SVP/scope target - and that is a different test from the
    // m_render_pass_is_svp one phase_combine uses to gate phase_pp.
    if (m_is_main_target)
        fg::CaptureScene();
#endif
	const auto sceneJitter = dlss::RasterJitter();
	// The stock TAA path excludes the already-composited PiP lens. Keep that
	// contract with temporal upscalers too, without overwriting glass tags in
	// the motion buffer (NVG and physical-glass consumers still need those).
	// (shared "Bodycam DLSS Scope Fix"; main-target guard added because this tree's
	// dlss::Configured() does not check the target itself)
	const bool resolveScope = dlss::Configured() && this == RImplementation.TargetMain && rt_dlss_scope_mask &&
		s_dlss_scope_resolve && Device.true_pip_on && Device.m_SecondViewport.IsSVPActive() &&
		!RImplementation.GMBase.RGraph.mapScopeHUDSorted.empty();
	if (resolveScope)
	{
		EnsureScopeShaders();
		const float clear[4] = {0, 0, 0, 0};
		HW.pContext->ClearRenderTargetView(rt_dlss_scope_mask->pRT, clear);
		u_setrt(rt_dlss_scope_mask, nullptr, nullptr, nullptr);
		RCache.set_CullMode(CULL_NONE);
		RCache.set_Stencil(FALSE);
		draw_scope(s_svp_taa_stamp, []()
		{
			RCache.set_c("scope_phase", 0);
			RCache.set_ColorWriteEnable();
		});
		// Unbind the mask before sampling it after reconstruction.
		u_setrt(rt_Color, nullptr, nullptr, nullptr);
	}
	const bool dlssOutput = dlss::Evaluate(rt_Color->pSurface, phase_upscaler_camera_mv()->pSurface);
	dlss::EndScene();
	if (!dlss::Configured()) return;

	// Separate display-resolution overlay buffers. Never feed screen-locked
	// distortion, NV noise or fake scopes back into the scene's DLSS history.
	u_setrt(rt_dlss_post_source, nullptr, nullptr, nullptr);
	RImplementation.rmNormal();
	RCache.set_CullMode(CULL_NONE);
	RCache.set_Stencil(FALSE);
	RCache.set_ColorWriteEnable();
	u32 offset;
	const float w = float(Device.dwWidth), h = float(Device.dwHeight);
	FVF::TL* vertices = (FVF::TL*)RCache.Vertex.Lock(4, g_combine->vb_stride, offset);
	vertices[0].set(0, h, EPS_S, 1, 0xffffffff, 0, 1);
	vertices[1].set(0, 0, EPS_S, 1, 0xffffffff, 0, 0);
	vertices[2].set(w, h, EPS_S, 1, 0xffffffff, 1, 1);
	vertices[3].set(w, 0, EPS_S, 1, 0xffffffff, 1, 0);
	RCache.Vertex.Unlock(4, g_combine->vb_stride);
	// Fuse optional CAS into the existing resolve draw: no extra target or copy.
	// Zero retains the original copy shader; fallback/scope frames are unsharpened.
	const bool sharpen = dlssOutput && ps_r_dlss_sharpness > 0.0f;
	// r_upscaler_debug: 1 shows the upscaler's input, 2 its motion vectors. DLSS
	// still evaluates, so its history stays valid when the view is switched off.
	const u32 element = ps_r_upscaler_debug == 1 ? 1 : ps_r_upscaler_debug == 2 ? 3 :
		dlssOutput ? (sharpen ? 2 : 0) : 1;
	RCache.set_Element(s_dlss_copy->E[element]);
	if (element == 2) RCache.set_c("dlss_sharpening", ps_r_dlss_sharpness, 0.f, 0.f, 0.f);
	RCache.set_Geometry(g_combine);
	RCache.Render(D3DPT_TRIANGLELIST, offset, 0, 4, 0, 2);

	if (resolveScope && dlssOutput)
	{
		RCache.set_Element(s_dlss_scope_resolve->E[0]);
		RCache.set_c("dlss_scope_jitter", sceneJitter.x / dlss::RenderWidth(),
			sceneJitter.y / dlss::RenderHeight(), 0.f, 0.f);
		RCache.Render(D3DPT_TRIANGLELIST, offset, 0, 4, 0, 2);
	}
	// Lens flares are additive, depth-free sprites that cover the HUD. In the scene
	// they would be reprojected with the hands' motion vectors and reconstructed as
	// blocks, so draw them here at display resolution without jitter.
	// Main view only. Upstream reaches this path solely for the main target; our
	// base also runs the DLSS postprocess for the SVP/scope target, and drawing
	// flares there replaces the bound geometry mid-pass and faults in phase_pp.
	if (m_is_main_target && ps_r2_anomaly_flags.test(R2_AN_FLAG_FLARES) && ps_r2_heatvision == 0)
		g_pGamePersistent->Environment().RenderFlares();

	// Only defer direct UI draws when wearable surfaces were found in this view.
	// A normal weapon/device must not trigger an additional native depth pass.
	const bool renderHudUi = RImplementation.GMBase.RGraph.hasNativeHudAttachments &&
		g_hud && g_hud->RenderActiveItemUIQuery();
	if (renderHudUi || !RImplementation.GMBase.RGraph.mapHUDNativeUi.empty())
	{
		if (!reported_native_ui)
		{
			Msg("[Upscaler] HUD UI drawn after reconstruction: native=%ux%u, scene=%ux%u, meshes=%u, item_ui=%u",
				Device.dwWidth, Device.dwHeight, dlss::RenderWidth(), dlss::RenderHeight(),
				unsigned(RImplementation.GMBase.RGraph.mapHUDNativeUi.size()), unsigned(renderHudUi));
			reported_native_ui = true;
		}
		// Reproject the render-sized scene depth into the native depth buffer
		// before drawing the unjittered HUD screens.
		u_setrt(rt_dlss_post_source, nullptr, nullptr, HW.pBaseZB);
		// The flares above replace the geometry, so re-make the fullscreen quad --
		// but only where the flares actually ran. Upstream reaches this path for the
		// main target alone; our base also runs it for the SVP/scope target, where
		// the quad from the resolve draw above is still bound, as it was before this
		// merge. Taking a second lock there is new behaviour on a path upstream
		// never exercises, and that path is where phase_pp faults.
		u32 uiOffset = offset;
		if (m_is_main_target)
		{
			FVF::TL* uiQuad = (FVF::TL*)RCache.Vertex.Lock(4, g_combine->vb_stride, uiOffset);
			uiQuad[0].set(0, h, EPS_S, 1, 0xffffffff, 0, 1);
			uiQuad[1].set(0, 0, EPS_S, 1, 0xffffffff, 0, 0);
			uiQuad[2].set(w, h, EPS_S, 1, 0xffffffff, 1, 1);
			uiQuad[3].set(w, 0, EPS_S, 1, 0xffffffff, 1, 0);
			RCache.Vertex.Unlock(4, g_combine->vb_stride);
			// Upstream added this bind for the fresh quad; pre-merge this block
			// relied on the geometry already bound, which is what the SVP path
			// still needs here.
			RCache.set_Geometry(g_combine);
		}
		RCache.set_Element(s_dlss_ui_depth->E[0]);
		RCache.set_c("dlss_ui_depth_params", float(dlss::RenderWidth()) / w,
			float(dlss::RenderHeight()) / h, sceneJitter.x, sceneJitter.y);
		RCache.set_ZFunc(D3DCMP_ALWAYS);
		RCache.set_ColorWriteEnable(0);
		RCache.Render(D3DPT_TRIANGLELIST, uiOffset, 0, 4, 0, 2);
		RCache.set_ColorWriteEnable();
		RCache.set_CullMode(CULL_CCW);
		RImplementation.GMBase.r_dsgraph_render_native_ui(renderHudUi);
	}

	if (ps_r2_mask_control.x > 0)
	{
		phase_gasmask_dudv();
		if (ps_r2_drops_control.x > 0) phase_gasmask_drops();
	}
	if (ps_r2_nightvision > 0) phase_nightvision();
	if (ps_r2_heatvision > 0) phase_heatvision();
	if (scope_fake_enabled) phase_fakescope();
}

void CRenderTarget::phase_pp()
{
	phase_dlss_postprocess();
	// combination/postprocess
#ifdef XR_DX12_BRIDGE
	// Backstop only. The real crash here was NOT a null RTV: HW.secret_pBaseRT
	// held a one-time UpdateViews snapshot of m_slots[...].view11 while the
	// bridge rotates and releases that view every frame, so SetActive restored
	// a FREED pointer into HW.pBaseRT and d3d11.dll faulted reading it (read of
	// 0x16D; the log's teardown line read refCount:pBaseRT 0xF999999A, i.e.
	// dangling, not null - which is why this test never fired). Fixed by having
	// AcquirePresentationFrame track the snapshot, and by nulling it at the
	// release sites. Keep this guard for the window where it is legitimately
	// null; the next AcquirePresentationFrame republishes a valid view.
	if (!HW.pBaseRT)
	{
		static bool reported = false;
		if (!reported) { Msg("! [DX12 bridge] no presentation RTV this frame; skipping phase_pp"); reported = true; }
		return;
	}
#endif
	u_setrt(Device.dwWidth, Device.dwHeight, HW.pBaseRT,NULL,NULL, HW.pBaseZB);
	RImplementation.rmNormal();
	//	Element 0 for for normal post-process
	//	Element 4 for color map post-process
	bool bCMap = u_need_CM();
	//RCache.set_Element	(s_postprocess->E[bCMap ? 4 : 0]);
	if (dlss::Configured())
	{
		RCache.set_Element(s_dlss_postprocess->E[bCMap ? 4 : 0]);
	}
	else if (!RImplementation.o.dx10_msaa)
	{
		//		RCache.set_Shader	(s_postprocess	);
		RCache.set_Element(s_postprocess->E[bCMap ? 4 : 0]);
	}
	else
	{
		//		RCache.set_Shader( s_postprocess_msaa );
		RCache.set_Element(s_postprocess_msaa->E[bCMap ? 4 : 0]);
	}

	int gblend = clampr(iFloor((1 - param_gray) * 255.f), 0, 255);
	int nblend = clampr(iFloor((1 - param_noise) * 255.f), 0, 255);
	u32 p_color = subst_alpha(param_color_base, nblend);
	u32 p_gray = subst_alpha(param_color_gray, gblend);
	Fvector p_brightness = param_color_add;
	// Msg				("param_gray:%f(%d),param_noise:%f(%d)",param_gray,gblend,param_noise,nblend);
	// Msg				("base: %d,%d,%d",	color_get_R(p_color),		color_get_G(p_color),		color_get_B(p_color));
	// Msg				("gray: %d,%d,%d",	color_get_R(p_gray),		color_get_G(p_gray),		color_get_B(p_gray));
	// Msg				("add:  %d,%d,%d",	color_get_R(p_brightness),	color_get_G(p_brightness),	color_get_B(p_brightness));

	// Draw full-screen quad textured with our scene image
	u32 Offset;
	float _w = float(Device.dwWidth);
	float _h = float(Device.dwHeight);

	Fvector2 n0, n1, r0, r1, l0, l1;
	u_calc_tc_duality_ss(r0, r1, l0, l1);
	u_calc_tc_noise(n0, n1);

	// Fill vertex buffer
	float du = ps_r1_pps_u, dv = ps_r1_pps_v;
	TL_2c3uv* pv = (TL_2c3uv*)RCache.Vertex.Lock(4, g_postprocess.stride(), Offset);
	pv->set(du + 0, dv + float(_h), p_color, p_gray, r0.x, r1.y, l0.x, l1.y, n0.x, n1.y);
	pv++;
	pv->set(du + 0, dv + 0, p_color, p_gray, r0.x, r0.y, l0.x, l0.y, n0.x, n0.y);
	pv++;
	pv->set(du + float(_w), dv + float(_h), p_color, p_gray, r1.x, r1.y, l1.x, l1.y, n1.x, n1.y);
	pv++;
	pv->set(du + float(_w), dv + 0, p_color, p_gray, r1.x, r0.y, l1.x, l0.y, n1.x, n0.y);
	pv++;
	RCache.Vertex.Unlock(4, g_postprocess.stride());

	// Actual rendering
	static shared_str s_brightness = "c_brightness";
	static shared_str s_colormap = "c_colormap";
	RCache.set_c(s_brightness, p_brightness.x, p_brightness.y, p_brightness.z, 0);
	RCache.set_c(s_colormap, param_color_map_influence, param_color_map_interpolate, 0, 0);
	RCache.set_Geometry(g_postprocess);
	RCache.Render(D3DPT_TRIANGLELIST, Offset, 0, 4, 0, 2);
}
