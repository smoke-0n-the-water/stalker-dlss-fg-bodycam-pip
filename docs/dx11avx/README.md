# Building AnomalyDX11AVX.exe

Since quark-151 every project builds `/arch:AVX` (not AVX2), the DX12 exe included, so the
DX11-AVX exe is no longer the only choice for CPUs without AVX2 (Intel Sandy/Ivy Bridge, AMD FX):
the DX12 exe runs there too. DX11-AVX remains for players who cannot run DX12.

Build it as any other configuration, from a clean `_build` (incremental LTCG builds have broken boot):

```bash
MSBuild.exe src/engine-vs2022.sln -p:Configuration=DX11-AVX -p:Platform=x64 -m
```

`avx_only.props` (`-p:ForceImportBeforeCppTargets=<repo>/docs/dx11avx/avx_only.props`) was needed while
the projects defaulted to AVX2. It is harmless now and kept for older branches.

Hand-written AVX2 or FMA intrinsics must sit behind `#if defined(__AVX2__)` with an AVX or scalar
`#else` (see xrPhysics/AVX2Math.h, xrTheora_Surface.cpp, xrImage_Resampler.cpp, tntQAVI.cpp, min_obb.cpp,
xrCPU_Pipe/xrSkin2W_AVX2.cpp). After building, disassemble the exe and check that AVX2/FMA/BMI
instructions appear only in runtime-dispatched code (MaskedOcclusionCulling*, `__std_*`, compiler
`__isa_available` paths such as snap_usedef and svp_native_schema_hash). `vpermilps` on ymm is AVX.
