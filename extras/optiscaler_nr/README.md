# OptiScaler NR config (DLSS 5 / Neural Rendering)

The `OptiScaler.ini` shipped in STEP 6 of the share pack, for
[wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass](https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass)
**v0.8.10** (standard build). OptiScaler binaries and the NVIDIA NR runtime are not in this repo.

It is the stock v0.8.10 ini with 11 values changed, applied by `configure_optiscaler_v08.py`:

| Section | Key | Value | Why |
| --- | --- | --- | --- |
| Upscalers | Dx11Upscaler | `dlss_12` | both exes render in DX11; `dlss_12` is the only DX11 path that runs NR |
| FrameGen | Enabled / FGInput / FGOutput | `false` / `nofg` / `nofg` | OptiScaler FG crashes GAMMA at boot; frame gen belongs to the engine's DX12 bridge |
| Spoofing | StreamlineSpoofing | `false` | default `true` spoofs the GPU inside `slInit`, which is the engine's call |
| Spoofing | Dxgi | `false` | pinned, already the NVIDIA default |
| Log | LogToFile / LogLevel | `false` / `2` | no continuous log during play |
| DlssNr | Enabled / RunBeforeSR / Passes | `true` / `true` / `1` | NR on the pre-upscale image, one pass |

0.8.0 removed `[FrameGen] External`, which is what kept 0.7.6 out of the DX12 exe's Streamline frame gen.
The two `Spoofing` pins plus FG pinned off replace it. Verified with `AnomalyDX12.exe`: DLSS-G 2x and NR
ran together, NR created through the direct compatibility runtime at about 4.1 ms/frame on an RTX 5080.

```
python configure_optiscaler_v08.py path\to\fresh\OptiScaler.ini
```

Known issue: on quit, the engine's crash handler can fire after device teardown. OptiScaler's log ends at
`DlssNr_Dx12::Retire ... retaining retired GPU owner until recordings finish; 1 waiting`.
