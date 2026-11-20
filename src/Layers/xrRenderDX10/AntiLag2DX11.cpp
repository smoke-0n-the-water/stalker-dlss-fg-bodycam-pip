#include <windows.h>
#include <d3d11.h>
#include <stdlib.h>
#include <cstdint>
#include "../../../sdk/AntiLag2/ffx_antilag2_dx11.h"
#include "AntiLag2DX11.h"

namespace
{
AMD::AntiLag2DX11::Context s_ctx{};
bool s_supported = false;
bool s_active = false;
} // namespace

namespace antilag2_dx11
{
void Initialize()
{
    if (s_supported)
    {
        DeInitialize();
    }

    s_ctx = {};
    const HRESULT hr = AMD::AntiLag2DX11::Initialize(&s_ctx);
    s_supported = (hr == S_OK);
    s_active = false;
}

void DeInitialize()
{
    if (s_supported)
    {
        AMD::AntiLag2DX11::DeInitialize(&s_ctx);
    }

    s_ctx = {};
    s_supported = false;
    s_active = false;
}

void Update(bool enabled, unsigned int maxFps)
{
    if (!s_supported)
    {
        s_active = false;
        return;
    }

    s_active = enabled;
    AMD::AntiLag2DX11::Update(&s_ctx, enabled, enabled ? maxFps : 0u);
}

bool IsSupported()
{
    return s_supported;
}

bool IsActive()
{
    return s_supported && s_active;
}
} // namespace antilag2_dx11
