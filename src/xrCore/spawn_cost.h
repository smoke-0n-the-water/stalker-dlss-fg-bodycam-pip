#pragma once
#include <chrono>

// Main-thread time split of one object spawn, logged as [SpawnTime] by CLevel::cl_Process_Spawn.
// A Scope only counts on a thread that has a Frame open, and time is exclusive: a nested scope
// pauses its parent, so the parts never overlap.
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
}
