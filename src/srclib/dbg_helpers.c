/*!
 * \brief   he file contains debugging helpers implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2010-03-05
            \endverbatim
 * Copyright: (c) Alexander Egorov 2009-2015
 */

#include "targetver.h"
#include <stdio.h>
#include "dbg_helpers.h"

#define DBG_HELP_DLL "DBGHELP.DLL"
#define DUMP_FILE_NAME PROGRAM_NAME ".exe.dmp"
#define DUMP_FUNCTION "MiniDumpWriteDump"
#define UNHANDLED_EXCEPTION_OCCURRED " An unhandled exception occurred. "

 /*
    dbg_ - public members
    prdbg_ - private members
 */

void prdbg_print_win32_error(const char* message);

LONG WINAPI dbg_top_level_filter(struct _EXCEPTION_POINTERS* p_exception_info)
{
    LONG result = EXCEPTION_CONTINUE_SEARCH;    // finalize process in standard way by default
    HMODULE hDll = NULL;
    MINIDUMP_EXCEPTION_INFORMATION exInfo = { 0 };
    BOOL isOK = FALSE;
    MINIDUMPWRITEDUMP pfnDump = NULL;
    HANDLE hFile = NULL;

    hDll = LoadLibraryA(DBG_HELP_DLL);

    if (hDll == NULL) {
        prdbg_print_win32_error(" Cannot load dll " DBG_HELP_DLL);
        return result;
    }
    // get func address
    pfnDump = (MINIDUMPWRITEDUMP)GetProcAddress(hDll, DUMP_FUNCTION);
    if (!pfnDump) {
        prdbg_print_win32_error(" Cannot get address of " DUMP_FUNCTION " function");
        return result;
    }

    hFile = CreateFileA(DUMP_FILE_NAME,
                        GENERIC_WRITE,
                        0,
                        NULL,
                        CREATE_ALWAYS,
                        FILE_ATTRIBUTE_NORMAL,
                        NULL);

    if (hFile == INVALID_HANDLE_VALUE) {
        prdbg_print_win32_error(UNHANDLED_EXCEPTION_OCCURRED "Error on creating dump file: " DUMP_FILE_NAME);
        return result;
    }

    exInfo.ThreadId = GetCurrentThreadId();
    exInfo.ExceptionPointers = p_exception_info;
    exInfo.ClientPointers = 0;

    // Write pDumpFile
    isOK = pfnDump(GetCurrentProcess(),
                   GetCurrentProcessId(), hFile, MiniDumpNormal, &exInfo, NULL, NULL);
    if (isOK) {
        printf_s(UNHANDLED_EXCEPTION_OCCURRED "Dump saved to: %s", DUMP_FILE_NAME);
        result = EXCEPTION_EXECUTE_HANDLER;
    } else {
        prdbg_print_win32_error(UNHANDLED_EXCEPTION_OCCURRED "Error saving dump file: " DUMP_FILE_NAME);
    }
    CloseHandle(hFile);
    return result;
}

void prdbg_print_win32_error(const char* message)
{
    DWORD errorCode = 0;
    void* buffer = NULL;

    __try {
        errorCode = GetLastError();
        FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS |
                       FORMAT_MESSAGE_MAX_WIDTH_MASK | FORMAT_MESSAGE_ALLOCATE_BUFFER,
                       NULL, errorCode, MAKELANGID(LANG_NEUTRAL,
                                                   SUBLANG_DEFAULT), (char*)&buffer, 0, NULL);
        printf_s("%s. Windows error %#x: %s", message, errorCode, (char*)buffer);
    } __finally {
        if (buffer != NULL) {
            LocalFree(buffer);
        }
    }
}
