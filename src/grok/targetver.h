#pragma once

// Including SDKDDKVer.h defines the highest available Windows platform.

// If you wish to build your application for a previous Windows platform, include WinSDKVer.h and
// set the _WIN32_WINNT macro to the platform you wish to support before including SDKDDKVer.h.

#ifdef _MSC_VER
#include <SDKDDKVer.h>
#endif

#define PRODUCT_VERSION "0.2.2"
#define PROGRAM_NAME "grok"
#define APP_NAME "Grok regexp macro processor " PRODUCT_VERSION
#ifdef _MSC_VER
#define PROG_EXE PROGRAM_NAME ".exe"
#else
#define PROG_EXE PROGRAM_NAME
#endif
