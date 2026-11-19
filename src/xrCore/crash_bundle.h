#pragma once

#include <Windows.h>
#include <stdio.h>
#include <wchar.h>

// A crash bundle: one folder holding copies of the logs and the dump of a failed session.
// For crash handlers, so only Win32 file calls and fixed buffers, under SEH. It copies, never moves.
namespace CrashBundle
{
inline const wchar_t* BaseName(const wchar_t* path)
{
    const wchar_t* name = path;
    for (const wchar_t* c = path; *c; ++c)
        if (*c == L'\\' || *c == L'/')
            name = c + 1;
    return name;
}

// Creates <baseDirectory>\crash_<yyyy-mm-dd_hh-mm-ss> (local time) and copies into it gameLog (a full
// path, may be empty) and each of files from errorDirectory. A missing source file is skipped.
// bundle gets the folder path, empty when it could not be created.
inline bool Make(const wchar_t* baseDirectory, const wchar_t* errorDirectory, const wchar_t* gameLog,
    const wchar_t* const* files, unsigned fileCount, wchar_t* bundle, size_t bundleCapacity)
{
    bundle[0] = 0;
    __try
    {
        SYSTEMTIME now = {};
        GetLocalTime(&now);
        if (_snwprintf_s(bundle, bundleCapacity, _TRUNCATE, L"%s\\crash_%04u-%02u-%02u_%02u-%02u-%02u",
                baseDirectory, now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond) < 0 ||
            (!CreateDirectoryW(bundle, nullptr) && GetLastError() != ERROR_ALREADY_EXISTS))
        {
            bundle[0] = 0;
            return false;
        }
        wchar_t from[MAX_PATH] = {}, to[MAX_PATH] = {};
        if (gameLog && *gameLog && _snwprintf_s(to, MAX_PATH, _TRUNCATE, L"%s\\%s", bundle, BaseName(gameLog)) >= 0)
            CopyFileW(gameLog, to, FALSE);
        for (unsigned index = 0; index < fileCount; ++index)
            if (_snwprintf_s(from, MAX_PATH, _TRUNCATE, L"%s\\%s", errorDirectory, files[index]) >= 0 &&
                _snwprintf_s(to, MAX_PATH, _TRUNCATE, L"%s\\%s", bundle, files[index]) >= 0)
                CopyFileW(from, to, FALSE);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}
}
