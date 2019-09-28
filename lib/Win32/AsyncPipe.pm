#define _XP_SUPPORT_

struct IO_COUNT 
{
    HANDLE _hFile;
    HANDLE _hEvent;
    LONG _dwIoCount;

    IO_COUNT()
    {
        _dwIoCount = 1;
        _hEvent = 0;
    }

    ~IO_COUNT()
    {
        if (_hEvent)
        {
            CloseHandle(_hEvent);
        }
    }

    ULONG Create(HANDLE hFile);

    void BeginIo()
    {
        InterlockedIncrement(&_dwIoCount);
    }

    void EndIo()
    {
        if (!InterlockedDecrement(&_dwIoCount))
        {
            SetEvent(_hEvent);
        }
    }

    void Wait()
    {
        WaitForSingleObject(_hEvent, INFINITE);
    }
};


struct U_IRP : OVERLAPPED 
{
    enum { read, write };

    IO_COUNT* _pIoObject;
    ULONG _code;
    LONG _dwRef;
    char _buffer[256];

    void AddRef()
    {
        InterlockedIncrement(&_dwRef);
    }

    void Release()
    {
        if (!InterlockedDecrement(&_dwRef)) delete this;
    }

    U_IRP(IO_COUNT* pIoObject) : _pIoObject(pIoObject)
    {
        _dwRef = 1;
        pIoObject->BeginIo();
        RtlZeroMemory(static_cast<OVERLAPPED*>(this), sizeof(OVERLAPPED));
    }

    ~U_IRP()
    {
        _pIoObject->EndIo();
    }

    ULONG CheckIoResult(BOOL fOk)
    {
        if (fOk)
        {
#ifndef _XP_SUPPORT_
            OnIoComplete(NOERROR, InternalHigh);
#endif
            return NOERROR;
        }

        ULONG dwErrorCode = GetLastError();

        if (dwErrorCode != ERROR_IO_PENDING)
        {
            OnIoComplete(dwErrorCode, 0);
        }

        return dwErrorCode;
    }

    ULONG Read()
    {
        _code = read;

        AddRef();

        return CheckIoResult(ReadFile(_pIoObject->_hFile, _buffer, sizeof(_buffer), 0, this));
    }

    ULONG Write(const void* pvBuffer, ULONG cbBuffer)
    {
        _code = write;

        AddRef();

        return CheckIoResult(WriteFile(_pIoObject->_hFile, pvBuffer, cbBuffer, 0, this));
    }

    VOID OnIoComplete(DWORD dwErrorCode, DWORD_PTR dwNumberOfBytesTransfered)
    {
        switch (_code)
        {
        case read:
            if (dwErrorCode == NOERROR)
            {
                if (dwNumberOfBytesTransfered)
                {
                    if (int cchWideChar = MultiByteToWideChar(CP_OEMCP, 0, _buffer, (ULONG)dwNumberOfBytesTransfered, 0, 0))
                    {
                        PWSTR wz = (PWSTR)alloca(cchWideChar * sizeof(WCHAR));

                        if (MultiByteToWideChar(CP_OEMCP, 0, _buffer, (ULONG)dwNumberOfBytesTransfered, wz, cchWideChar))
                        {
                            if (int cbMultiByte = WideCharToMultiByte(CP_ACP, 0, wz, cchWideChar, 0, 0, 0, 0))
                            {
                                PSTR sz = (PSTR)alloca(cbMultiByte);

                                if (WideCharToMultiByte(CP_ACP, 0, wz, cchWideChar, sz, cbMultiByte, 0, 0))
                                {
                                    DbgPrint("%.*s", cbMultiByte, sz);
                                }
                            }
                        }
                    }
                }
                Read();
            }
            break;
        case write:
            break;
        default:
            __debugbreak();
        }

        Release();

        if (dwErrorCode)
        {
            DbgPrint("[%u]: error=%u\n", _code, dwErrorCode);
        }
    }

    static VOID WINAPI _OnIoComplete(
        DWORD dwErrorCode,
        DWORD_PTR dwNumberOfBytesTransfered,
        LPOVERLAPPED lpOverlapped
        )
    {
        static_cast<U_IRP*>(lpOverlapped)->OnIoComplete(RtlNtStatusToDosError(dwErrorCode), dwNumberOfBytesTransfered);
    }
};

ULONG IO_COUNT::Create(HANDLE hFile)
{
    _hFile = hFile;
    // error in declaration LPOVERLAPPED_COMPLETION_ROUTINE : 
    // second parameter must be DWORD_PTR but not DWORD
    return BindIoCompletionCallback(hFile, (LPOVERLAPPED_COMPLETION_ROUTINE)U_IRP::_OnIoComplete, 0) && 
#ifndef _XP_SUPPORT_
        SetFileCompletionNotificationModes(hFile, FILE_SKIP_COMPLETION_PORT_ON_SUCCESS) &&
#endif
        (_hEvent = CreateEvent(0, TRUE, FALSE, 0)) ? NOERROR : GetLastError();
}

void ChildTest()
{
    static const WCHAR name[] = L"\\\\?\\pipe\\somename";

    HANDLE hFile = CreateNamedPipeW(name, 
        PIPE_ACCESS_DUPLEX|FILE_READ_DATA|FILE_WRITE_DATA|FILE_FLAG_OVERLAPPED, 
        PIPE_TYPE_BYTE|PIPE_READMODE_BYTE, 1, 0, 0, 0, 0);

    if (hFile != INVALID_HANDLE_VALUE)
    {
        IO_COUNT obj;

        if (obj.Create(hFile) == NOERROR)
        {
            BOOL fOk = FALSE;

            SECURITY_ATTRIBUTES sa = { sizeof(sa), 0, TRUE };

            STARTUPINFOW si = { sizeof(si) };
            PROCESS_INFORMATION pi;

            si.dwFlags = STARTF_USESTDHANDLES;

            si.hStdError = CreateFileW(name, FILE_GENERIC_READ|FILE_GENERIC_WRITE, 
                FILE_SHARE_READ|FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, 0);

            if (si.hStdError != INVALID_HANDLE_VALUE)
            {
                si.hStdInput = si.hStdOutput = si.hStdError;

                WCHAR ApplicationName[MAX_PATH];
                if (GetEnvironmentVariableW(L"ComSpec", ApplicationName, RTL_NUMBER_OF(ApplicationName)))
                {
                    if (CreateProcessW(ApplicationName, 0, 0, 0, TRUE, 0, 0, 0, &si, &pi))
                    {
                        CloseHandle(pi.hThread);
                        CloseHandle(pi.hProcess);
                        fOk = TRUE;
                    }
                }

                CloseHandle(si.hStdError);
            }

            if (fOk)
            {
                STATIC_ASTRING(help_and_exit, "help\r\nexit\r\n");

                U_IRP* p;

                if (p = new U_IRP(&obj))
                {
                    p->Read();
                    p->Release();
                }

                obj.EndIo();

                //++ simulate user commands
                static PCSTR commands[] = { "help\r\n", "ver\r\n", "dir\r\n", "exit\r\n" };
                ULONG n = RTL_NUMBER_OF(commands);
                PCSTR* psz = commands;
                do 
                {
                    if (MessageBoxW(0,0, L"force close ?", MB_YESNO) == IDYES)
                    {
                        DisconnectNamedPipe(hFile);
                        break;
                    }
                    if (p = new U_IRP(&obj))
                    {
                        PCSTR command = *psz++;
                        p->Write(command, (ULONG)strlen(command) * sizeof(CHAR));
                        p->Release();
                    }    
                } while (--n);
                //--

                obj.Wait();
            }
        }

        CloseHandle(hFile);
    }
}