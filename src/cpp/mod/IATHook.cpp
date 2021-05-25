#include <stddef.h>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "IATHook.h"

static void *RVA(void *base, size_t offset)
{
	return static_cast<unsigned char*>(base) + offset;
}

static const void *RVA(const void *base, size_t offset)
{
	return static_cast<const unsigned char*>(base) + offset;
}

static const IMAGE_DATA_DIRECTORY *GetIATDirectoryData(const void *pDLL)
{
	const IMAGE_DOS_HEADER *pDOSHeader = static_cast<const IMAGE_DOS_HEADER*>(pDLL);
	if (pDOSHeader->e_magic != IMAGE_DOS_SIGNATURE)
		return nullptr;

	const IMAGE_NT_HEADERS *pPEHeader = static_cast<const IMAGE_NT_HEADERS*>(RVA(pDLL, pDOSHeader->e_lfanew));
	if (pPEHeader->Signature != IMAGE_NT_SIGNATURE)
		return nullptr;

#ifdef _WIN64
	if (pPEHeader->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC)
		return nullptr;
#else
	if (pPEHeader->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC)
		return nullptr;
#endif

	if (pPEHeader->OptionalHeader.NumberOfRvaAndSizes <= IMAGE_DIRECTORY_ENTRY_IAT)
		return nullptr;

	const IMAGE_DATA_DIRECTORY *pIATData = &pPEHeader->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IAT];
	if (pIATData->VirtualAddress == 0 || pIATData->Size == 0)
		return nullptr;

	return pIATData;
}

static bool ReplaceIATEntry(void **pEntry, void *pNewFunc)
{
	DWORD oldProtection;

	if (VirtualProtect(pEntry, sizeof (void*), PAGE_EXECUTE_READWRITE, &oldProtection) == 0)
		return false;

	(*pEntry) = pNewFunc;

	if (VirtualProtect(pEntry, sizeof (void*), oldProtection, &oldProtection) == 0)
		return false;

	return true;
}

bool IATHookByAddress(void *pDLL, void *pFunc, void *pNewFunc)
{
	if (!pDLL || !pFunc)
	{
		return false;
	}

	const IMAGE_DATA_DIRECTORY *pIATData = GetIATDirectoryData(pDLL);
	if (!pIATData)
	{
		SetLastError(ERROR_INVALID_MODULETYPE);
		return false;
	}

	// Import Address Table
	void **pIAT = static_cast<void**>(RVA(pDLL, pIATData->VirtualAddress));

	// number of functions in the IAT
	const size_t entryCount = pIATData->Size / sizeof (void*);

	bool found = false;

	// find the target function in the IAT and hook it
	for (size_t i = 0; i < entryCount; i++)
	{
		if (pIAT[i] == pFunc)
		{
			found = true;

			// hook the function
			if (!ReplaceIATEntry(&pIAT[i], pNewFunc))
			{
				return false;
			}
		}
	}

	if (!found)
	{
		SetLastError(ERROR_PROC_NOT_FOUND);
		return false;
	}

	return true;
}
