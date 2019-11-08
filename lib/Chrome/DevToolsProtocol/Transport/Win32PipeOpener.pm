package Win32::InheritHandles;
use strict;
#use Win32::API;

our $VERSION = '0.39';

# This only works with Windows version 8+ (Vista onwards)

1;

__END__

// https://github.com/rprichard/win32-console-docs/blob/master/src/HandleTests/CreateProcess_InheritList.cc
// https://devblogs.microsoft.com/oldnewthing/20111216-00/?p=8873

BOOL CreateProcessWithExplicitHandles(
  __in_opt     LPCTSTR lpApplicationName,
  __inout_opt  LPTSTR lpCommandLine,
  __in_opt     LPSECURITY_ATTRIBUTES lpProcessAttributes,
  __in_opt     LPSECURITY_ATTRIBUTES lpThreadAttributes,
  __in         BOOL bInheritHandles,
  __in         DWORD dwCreationFlags,
  __in_opt     LPVOID lpEnvironment,
  __in_opt     LPCTSTR lpCurrentDirectory,
  __in         LPSTARTUPINFO lpStartupInfo,
  __out        LPPROCESS_INFORMATION lpProcessInformation,
    // here is the new stuff
  __in         DWORD cHandlesToInherit,
  __in_ecount(cHandlesToInherit) HANDLE *rgHandlesToInherit)
{
 BOOL fSuccess;
 BOOL fInitialized = FALSE;
 SIZE_T size = 0;
 LPPROC_THREAD_ATTRIBUTE_LIST lpAttributeList = NULL;
 fSuccess = cHandlesToInherit < 0xFFFFFFFF / sizeof(HANDLE) &&
            lpStartupInfo->cb == sizeof(*lpStartupInfo);
 if (!fSuccess) {
  SetLastError(ERROR_INVALID_PARAMETER);
 }
 if (fSuccess) {
  fSuccess = InitializeProcThreadAttributeList(NULL, 1, 0, &size) ||
             GetLastError() == ERROR_INSUFFICIENT_BUFFER;
 }
 if (fSuccess) {
  lpAttributeList = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>
                                (HeapAlloc(GetProcessHeap(), 0, size));
  fSuccess = lpAttributeList != NULL;
 }
 if (fSuccess) {
  fSuccess = InitializeProcThreadAttributeList(lpAttributeList,
                    1, 0, &size);
 }
 if (fSuccess) {
  fInitialized = TRUE;
  fSuccess = UpdateProcThreadAttribute(lpAttributeList,
                    0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                    rgHandlesToInherit,
                    cHandlesToInherit * sizeof(HANDLE), NULL, NULL);
 }
 if (fSuccess) {
  STARTUPINFOEX info;
  ZeroMemory(&info, sizeof(info));
  info.StartupInfo = *lpStartupInfo;
  info.StartupInfo.cb = sizeof(info);
  info.lpAttributeList = lpAttributeList;
  fSuccess = CreateProcess(lpApplicationName,
                           lpCommandLine,
                           lpProcessAttributes,
                           lpThreadAttributes,
                           bInheritHandles,
                           dwCreationFlags | EXTENDED_STARTUPINFO_PRESENT,
                           lpEnvironment,
                           lpCurrentDirectory,
                           &info.StartupInfo,
                           lpProcessInformation);
 }
 if (fInitialized) DeleteProcThreadAttributeList(lpAttributeList);
 if (lpAttributeList) HeapFree(GetProcessHeap(), 0, lpAttributeList);
 return fSuccess;
}
