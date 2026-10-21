#pragma once
#include <cstdint>
#include <cstring>

namespace ReticleAtlas
{
// Reads the glow-size hint only. Shader validation remains authoritative for
// the descriptor and tile layout. Unrecognized headers return zero; a missing
// glow-size field retains the format default of one.
inline float GlowSize(const std::uint8_t* data, std::uint64_t length)
{
	// The atlas header is row 0 of mip 0, the descriptor follows from row 1 in rows of desc_width texels. An
	// RGBA8 atlas holds them in texels with R in the low byte; BC5 uses 4x4
	// blocks whose endpoints carry the four bytes in order R0, G0, R1, G1.
	float size = 0.f;
	auto read32 = [&](std::uint64_t offset)
	{
		std::uint32_t v = 0;
		if (offset + 4 <= length)
			std::memcpy(&v, data + offset, 4);
		return v;
	};
	const std::uint32_t width = read32(16);
	const bool dds = read32(0) == 0x20534444 /* "DDS " */ && width >= 8 && width <= 16384;
	const bool rgba8 =
		dds && (read32(80) & 0x40) && read32(88) == 32 && read32(92) == 0x000000FF && read32(96) == 0x0000FF00 && read32(100) == 0x00FF0000;
	const bool bc5 = dds && (read32(80) & 0x4) && read32(84) == 0x30315844 /* "DX10" */ && read32(128) == 83;
	auto texel = [&](std::uint64_t x, std::uint64_t y, std::uint8_t(&out)[4])
	{
		const std::uint64_t offset = rgba8 ? 128 + (y * width + x) * 4 : 148 + (y * (width / 4) + x) * 16;
		if (offset + (rgba8 ? 4 : 16) > length)
			return false;
		const std::uint8_t* t = data + offset;
		out[0] = t[0];
		out[1] = t[rgba8 ? 1 : 8];
		out[2] = t[rgba8 ? 2 : 1];
		out[3] = t[rgba8 ? 3 : 9];
		return true;
	};
	std::uint8_t t0[4], t1[4], t2[4], t4[4], t[4];
	if ((rgba8 || bc5) && texel(0, 0, t0) && texel(1, 0, t1) && texel(2, 0, t2) && texel(4, 0, t4) && !std::memcmp(t0, "RMSD", 4) &&
		!std::memcmp(t1, "FATL", 4) && (t2[0] == (bc5 ? 4 : 3) || t2[0] == (bc5 ? 6 : 5) || t2[0] == (bc5 ? 8 : 7)) && t4[0] > 0)
	{
		const std::uint32_t k = 13 >> 2, desc_width = t4[0];
		size = texel(k % desc_width, 1 + k / desc_width, t) && t[13 & 3] ? t[13 & 3] / 32.f : 1.f;
	}
	return size;
}
}
