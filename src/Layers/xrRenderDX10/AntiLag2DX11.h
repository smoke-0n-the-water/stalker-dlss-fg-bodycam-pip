#pragma once

namespace antilag2_dx11
{
    void Initialize();
    void DeInitialize();
    void Update(bool enabled, unsigned int maxFps);
    bool IsSupported();
    bool IsActive();
}
