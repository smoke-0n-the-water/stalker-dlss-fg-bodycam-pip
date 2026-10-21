function normal(shader, t_base, t_second, t_detail)
    shader:begin("stub_screen_space", "dlss_scope_resolve")
        :zb(false, false)
        :blend(true, blend.srcalpha, blend.invsrcalpha)
    shader:dx10texture("s_image", "$user$albedo")
    shader:dx10texture("dlss_scope_mask", "$user$dlss_scope_mask")
    shader:dx10sampler("smp_rtlinear")
end
