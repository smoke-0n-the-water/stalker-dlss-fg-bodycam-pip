#pragma once

// Profiler backends
#define PROFILER_NONE   (0)
#define PROFILER_OPTICK (1)

// Set active profiler backend.
//
// NOTE on the valueless defines in the vcxproj files: the ProfiledDX11 / Verified*
// configurations pass plain "XRCORE_PROFILER" with no value. MSVC (and gcc/clang)
// give such a symbol the value 1, so the guard below does NOT fire and the test
// "XRCORE_PROFILER == PROFILER_OPTICK" reduces to 1 == (1) -- true. Those configs
// therefore enable Optick by accident rather than by intent, and would silently
// stop working if PROFILER_OPTICK were ever renumbered. Do not copy that pattern:
// pass the value explicitly, e.g.
//     /DXRCORE_PROFILER=PROFILER_OPTICK
// which is what the DX11-AVX configurations do via the MSBuild property
// XrProfilerDefines (empty by default -> PROFILER_NONE, i.e. an uninstrumented
// build identical to the shipping one):
//     msbuild engine-vs2022.sln /p:Configuration=DX11-AVX ^
//             /p:XrProfilerDefines=XRCORE_PROFILER=PROFILER_OPTICK
#if !defined(XRCORE_PROFILER)
    #define XRCORE_PROFILER PROFILER_NONE
//  #define XRCORE_PROFILER PROFILER_OPTICK
#endif

// Implement profiler macro interface
#if XRCORE_PROFILER == PROFILER_OPTICK
#	include "../3rd party/optick-git/src/optick.h"
#	define PROF_THREAD(Name) OPTICK_THREAD(Name)
#	define PROF_START_CAPTURE(...) OPTICK_START_CAPTURE(__VA_ARGS__)
#	define PROF_STOP_CAPTURE() OPTICK_STOP_CAPTURE()
#	define PROF_SAVE_CAPTURE(Name) OPTICK_SAVE_CAPTURE(Name)
// Capture modes for PROF_START_CAPTURE.
//   LIGHT = instrumentation markers + tags only. No ETW, so no Administrator
//           rights needed and no kernel tracing session is opened.
//   FULL  = Optick's own default: adds autosampling, context switches, syscalls
//           and other-process events. All of those are ETW and REQUIRE the game
//           to run elevated; without elevation the tracer silently collects
//           nothing while the instrumentation part still works.
// (the casts are needed because Mode::Type members OR together as int)
#	define PROF_MODE_LIGHT ((::Optick::Mode::Type)(::Optick::Mode::INSTRUMENTATION | ::Optick::Mode::TAGS))
#	define PROF_MODE_FULL  ((::Optick::Mode::Type)(::Optick::Mode::DEFAULT))
#	define PROF_IS_ACTIVE() (::Optick::IsActive())
#	define PROF_FRAME(Name) OPTICK_FRAME(Name)
// Variadic: a lot of call sites use the bare PROF_EVENT(), which OPTICK_EVENT
// supports (the event is then named after the enclosing function). Declaring a
// single parameter here made every one of those a C4003 warning.
#	define PROF_EVENT(...) OPTICK_EVENT(__VA_ARGS__)
#	define PROF_EVENT_DYNAMIC(...)	 static ::Optick::EventDescription* OPTICK_CONCAT(autogen_description_, __LINE__) = nullptr; \
							 OPTICK_CONCAT(autogen_description_, __LINE__) = ::Optick::CreateDescription(OPTICK_FUNC, __FILE__, __LINE__, ##__VA_ARGS__); \
							 ::Optick::Event OPTICK_CONCAT(autogen_event_, __LINE__)( *(OPTICK_CONCAT(autogen_description_, __LINE__)) ); 
#	define START_PROFILE(a) { PROF_EVENT(a)
#	define STOP_PROFILE		}
#else
#	define START_PROFILE(a) {
#	define STOP_PROFILE		}

#	define PROF_THREAD(Name)
#	define PROF_START_CAPTURE(...)
#	define PROF_STOP_CAPTURE()
#	define PROF_SAVE_CAPTURE(Name)
#	define PROF_MODE_LIGHT (0)
#	define PROF_MODE_FULL  (0)
#	define PROF_IS_ACTIVE() (false)
#	define PROF_FRAME(Name)
#	define PROF_EVENT(Name)
#	define PROF_EVENT_DYNAMIC(...) {};
#endif