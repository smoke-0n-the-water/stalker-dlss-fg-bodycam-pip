# Building AnomalyDX11AVX.exe (the no-AVX2 fallback)

The DX11-AVX exe exists for CPUs without AVX2 (Intel Sandy/Ivy Bridge, AMD FX).
Since the Quark merge most projects default to `/arch:AVX2`, so build it with the
override, from a clean `_build` (incremental LTCG builds have broken boot):

```bash
MSBuild.exe src/engine-vs2022.sln -p:Configuration=DX11-AVX -p:Platform=x64 -m "-p:ForceImportBeforeCppTargets=<repo>/docs/dx11avx/avx_only.props"
```

Hand-written AVX2 intrinsics must sit behind `#if defined(__AVX2__)` with a scalar
`#else` (see xrPhysics/AVX2Math.h, xrTheora_Surface.cpp, xrImage_Resampler.cpp,
tntQAVI.cpp, min_obb.cpp). After building, disassemble the exe and check that
AVX2/FMA/BMI instructions appear only in runtime-dispatched code
(MaskedOcclusionCulling*, xrSkin*_AVX2, `__std_*`, compiler `__isa_available` paths).
