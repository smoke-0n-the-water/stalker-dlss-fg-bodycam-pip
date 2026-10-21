#include "stdafx.h"
#include "r4_reticle_atlas.h"
#include "reticle_atlas.h"

// Authored glow size (descriptor byte 13, atlas formats 3-8),
// read once per texture from its file: 0 = not an atlas, else the scale on the glow lobes (1 when unset).
float reticle_atlas_glow_size(CTexture* texture)
{
	if (!texture || !texture->cName.size() || *texture->cName.c_str() == '$')
		return 0.f;
	float& size = texture->reticle_glow_size;
	if (size >= 0.f)
		return size;
	size = 0.f;
	string_path file;
	if (!FS.exist(file, "$game_textures$", texture->cName.c_str(), ".dds"))
		return size;
	IReader* F = FS.r_open(file);
	if (!F)
		return size;
	size = ReticleAtlas::GlowSize(static_cast<const u8*>(F->pointer()), u64(_max(F->length(), 0)));
	FS.r_close(F);
	return size;
}
