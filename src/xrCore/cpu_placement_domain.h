#pragma once
// Which logical processors the engine runs on (cpu_placement.cpp). Kept free of Windows
// calls so tools/cpu_placement/domain_test.cpp can check it on made-up CPU topologies.
#include <cstdint>

namespace cpu_placement
{
namespace domain_choice
{
constexpr std::uint32_t max_lps = 64;

inline std::uint32_t lp_count(std::uint64_t mask)
{
    std::uint32_t n = 0;
    for (; mask; mask &= mask - 1)
        ++n;
    return n;
}

struct result
{
    std::uint64_t domain; // where the engine runs
    std::uint32_t best_lp; // a logical processor of the chosen last-level cache
    bool confined; // domain is one last-level cache, not every usable LP
};

// usable: logical processors the process may use. Per logical processor: cache_of =
// last-level cache index, l3_of = its size in bytes (0 = unknown), rank_of = SchedulingClass.
//
// The engine is kept on one last-level cache only when that cache is LARGER than every
// other one: an X3D part whose V-Cache CCD the AMD driver keeps unparked for games. With
// several caches of equal size (5900X, 5950X, 7900X, 7950X, 9900X, 9950X) one cache is just
// half the CPU, and the pool, driver and frame generation threads lost the other half
// (v0.5.0 to v0.6, low FPS on AMD reported 2026-11-13); there every usable LP is kept.
// A small largest cache (Zen 5c cluster split, LP E-cores) would starve the pool: keep all.
inline result choose(std::uint64_t usable, const std::uint8_t* cache_of, const std::uint32_t* l3_of,
    const std::uint8_t* rank_of)
{
    // the largest L3, then the best ranked core, then the larger domain
    std::uint64_t best_domain = 0;
    std::uint32_t best_lp = 0;
    std::uint8_t best_rank = 0;
    for (std::uint32_t lp = 0; lp < max_lps; ++lp)
    {
        if (!(usable & (1ull << lp)))
            continue;
        std::uint64_t mask = 0;
        std::uint8_t rank = 0;
        for (std::uint32_t other = 0; other < max_lps; ++other)
            if ((usable & (1ull << other)) && cache_of[other] == cache_of[lp])
            {
                mask |= 1ull << other;
                if (rank_of[other] > rank)
                    rank = rank_of[other];
            }
        if (!best_domain || l3_of[lp] > l3_of[best_lp] ||
            (l3_of[lp] == l3_of[best_lp] && (rank > best_rank || (rank == best_rank && lp_count(mask) > lp_count(best_domain)))))
        {
            best_domain = mask;
            best_lp = lp;
            best_rank = rank;
        }
    }

    bool strictly_largest = true;
    for (std::uint32_t lp = 0; lp < max_lps; ++lp)
        if ((usable & (1ull << lp)) && !(best_domain & (1ull << lp)) && l3_of[lp] >= l3_of[best_lp])
            strictly_largest = false;

    const bool confine = best_domain != usable && strictly_largest && lp_count(best_domain) * 2 >= lp_count(usable);
    return {confine ? best_domain : usable, best_lp, confine};
}
} // namespace domain_choice
} // namespace cpu_placement
