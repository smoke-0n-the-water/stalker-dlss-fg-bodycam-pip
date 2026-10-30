#pragma once
#include <chrono>

// Main-thread time split of one object spawn ([SpawnTime], CLevel::cl_Process_Spawn) or one weapon
// HUD load ([HudTime], attachable_hud_item::load). A Scope only counts on a thread that has a Frame
// open, and time is exclusive: a nested scope pauses its parent, so the parts never overlap.
namespace spawn_cost
{
enum Part
{
	Lua,       // script binder net_spawn and the callbacks it fires
	Sound,     // sound files loaded from disk
	Model,     // visual instancing
	ModelLoad, // visual loaded from disk (not prefetched)
	Count
};

struct Frame
{
	u64 us[Count] = {};
	u32 n[Count] = {};
	int part = -1;
	std::chrono::steady_clock::time_point since;
};

inline thread_local Frame* t_frame = nullptr;

inline u64 elapsed_us(std::chrono::steady_clock::time_point from, std::chrono::steady_clock::time_point to)
{
	return (u64)std::chrono::duration_cast<std::chrono::microseconds>(to - from).count();
}

class Scope
{
	Frame* frame;
	int prev = -1;

public:
	explicit Scope(Part part) : frame(t_frame)
	{
		if (!frame)
			return;
		const auto now = std::chrono::steady_clock::now();
		if (frame->part >= 0)
			frame->us[frame->part] += elapsed_us(frame->since, now);
		prev = frame->part;
		frame->part = part;
		frame->n[part]++;
		frame->since = now;
	}

	~Scope()
	{
		if (!frame)
			return;
		const auto now = std::chrono::steady_clock::now();
		frame->us[frame->part] += elapsed_us(frame->since, now);
		frame->part = prev;
		frame->since = now;
	}

	Scope(const Scope&) = delete;
	Scope& operator=(const Scope&) = delete;
};

// Thread storage, not the stack: xrGame builds without unwind semantics, so if an exception ever
// skipped ~Owner the frame pointer must not dangle. The worst case is logging stops.
inline thread_local Frame t_owner_frame;

// Opens the Frame for the outermost timed operation on this thread and logs it as "[tag] name"
// when it held the thread at least threshold_ms. Nested operations add to the outer one.
class Owner
{
	const char* tag;
	const char* name;
	u32 threshold_ms;
	bool owner = false;
	std::chrono::steady_clock::time_point start;

public:
	Owner(const char* t, const char* n, u32 threshold) : tag(t), name(n), threshold_ms(threshold)
	{
		if (!threshold_ms || t_frame)
			return;
		owner = true;
		t_owner_frame = Frame();
		start = t_owner_frame.since = std::chrono::steady_clock::now();
		t_frame = &t_owner_frame;
	}

	~Owner()
	{
		if (!owner)
			return;
		t_frame = nullptr;
		const u64 total = elapsed_us(start, std::chrono::steady_clock::now());
		if (total < u64(threshold_ms) * 1000)
			return;
		const u64* us = t_owner_frame.us;
		const u64 parts = us[Lua] + us[Sound] + us[Model] + us[ModelLoad];
		Msg("! [%s] %s: %.1f ms = lua %.1f, sound %.1f (%u files), model %.1f, model load %.1f (%u files), other %.1f",
			tag, name, total / 1000.f, us[Lua] / 1000.f, us[Sound] / 1000.f, t_owner_frame.n[Sound],
			us[Model] / 1000.f, us[ModelLoad] / 1000.f, t_owner_frame.n[ModelLoad],
			(total > parts ? total - parts : 0) / 1000.f);
	}

	Owner(const Owner&) = delete;
	Owner& operator=(const Owner&) = delete;
};
}
