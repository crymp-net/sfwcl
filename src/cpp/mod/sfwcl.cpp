#include "Shared.h"
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <sstream>
#include "Mutex.h"
#include "Protect.h"
#include "RPC.h"
//#include <mutex>

#define CLIENT_BUILD 1001
//#define AUTO_UPDATE

#define WIN32_LEAN_AND_MEAN

#include <Windows.h>
#include <shellapi.h>

#include <CryModuleDefs.h>
#include <platform_impl.h>
#include <IGameFramework.h>
#include <ISystem.h>
#include <IScriptSystem.h>
#include <IConsole.h>
#include <I3DEngine.h>
#include <IGameRulesSystem.h>
#include <IFont.h>
#include <IUIDraw.h>
#include <IFlashPlayer.h>
#include <WinSock2.h>
#include <ShlObj.h>
#include "CPPAPI.h"
#include "Socket.h"
#include "Structs.h"
#include "IntegrityService.h"
#include "Atomic.h"

CPPAPI *luaApi=0;
Socket *socketApi=0;
ISystem *pSystem=0;
IConsole *pConsole=0;
GAME_32_6156 *pGameGlobal=0;
IGame *pGame = 0;
IScriptSystem *pScriptSystem=0;
IGameFramework *pGameFramework=0;
IFlashPlayer *pFlashPlayer=0;
RPC *rpc = 0;
//AsyncData *asyncQueue[MAX_ASYNC_QUEUE+1];
std::list<AsyncData*> asyncQueue;
Atomic<const char*> mapDlMessage(0);
std::map<std::string, std::string> asyncRetVal;
int asyncQueueIdx = 0;

int GAME_VER=6156;

Mutex g_mutex;
bool g_gameFilesWritable;
unsigned int g_objectsInQueue=0;

PFNSETUPDATEPROGRESSCALLBACK pfnSetUpdateProgressCallback = 0;
PFNDOWNLOADMAP pfnDownloadMap = 0;
PFNCANCELDOWNLOAD pfnCancelDownload = 0;

HMODULE hMapDlLib = 0;

void *m_ui;
char SvMaster[255]="m.crymp.net";

bool TestGameFilesWritable();
void OnUpdate(float frameTime);
void MemScan(void *base, int size);

void __stdcall MapDownloadUpdateProgress(const char *msg, bool error) {
	mapDlMessage.set(msg);
}

void InitGameObjects();

bool LoadScript(const char *name) {
	char *main = 0;
	int len = FileDecrypt(name, &main);
	if (len) {
		bool ok = true;
		if (pScriptSystem) {
			if (!pScriptSystem->ExecuteBuffer(main, len)) {
				ok = false;
			}
		}
		for (int i = 0; i < len; i++) main[i] = 0;
		delete[] main;
		main = 0;
		return ok;
	}
	return false;
}
void InitScripts() {
#ifdef PRERELEASE_BUILD
	FileEncrypt("Files\\Main.lua", "Files\\Main.bin");
	FileEncrypt("Files\\GameRules.lua", "Files\\GameRules.bin");
	FileEncrypt("Files\\IntegrityService.lua", "Files\\IntegrityService.bin");
#endif
	if (!LoadScript("Files\\Main.bin")) {
		//pSystem->Quit();
	}
	if (!LoadScript("Files\\IntegrityService.bin")) {
		//pSystem->Quit();
	}
}
void PostInitScripts() {
	ScriptAnyValue a;
	if (pScriptSystem->GetGlobalAny("g_gameRules", a) && a.table && a.GetVarType() == ScriptVarType::svtObject) {
		bool v = false;
		a.table->AddRef();
		if (!a.table->GetValue("IsModified", v)) {
			if (!LoadScript("Files\\GameRules.bin")) {
				pSystem->Quit();
			}
		}
		a.table->Release();
	}
}

void CommandClMaster(IConsoleCmdArgs *pArgs){
	if (pArgs->GetArgCount()>1)
	{
		const char *to=pArgs->GetCommandLine()+strlen(pArgs->GetArg(0))+1;
		strncpy(SvMaster, to, sizeof(SvMaster));
	}
	if (pScriptSystem->BeginCall("printf")) {
		char buff[50];
		sprintf(buff, "$0    cl_master = $6%s", SvMaster);
		pScriptSystem->PushFuncParam("%s");
		pScriptSystem->PushFuncParam(buff);
		pScriptSystem->EndCall();
	}
}
void CommandRldMaps(IConsoleCmdArgs *pArgs){
	ILevelSystem *pLevelSystem = pGameFramework->GetILevelSystem();
	if(pLevelSystem){
		pLevelSystem->Rescan();
	}
}

void OnUpdate(float frameTime) {
	bool eventFinished = false;

	static bool firstRun = true;
	if (firstRun) {
		firstRun = false;
		InitGameObjects();
	}

	for (std::list<AsyncData*>::iterator it = asyncQueue.begin(); g_objectsInQueue && it != asyncQueue.end(); it++) {
		g_mutex.Lock();
		AsyncData *obj = *it;
		if (obj) {
			if (obj->finished) {
				try {
					obj->postExec();
				}
				catch (std::exception& ex) {
					printf("postfn/Unhandled exception: %s", ex.what());
				}
				try {
					delete obj;
				}
				catch (std::exception& ex) {
					printf("delete/Unhandled exception: %s", ex.what());
				}
				eventFinished = true;
				g_objectsInQueue--;
				asyncQueue.erase(it);
				it--;
			} else if (obj->executing) {
				try {
					obj->onUpdate();
				}
				catch (std::exception& ex) {
					printf("progress_func/Unhandled exception: %s", ex.what());
				}
			}
		}
		g_mutex.Unlock();
	}
	static unsigned int localCounter = 0;
	if (eventFinished
#ifndef MAX_PERFORMANCE
		|| ((localCounter & 3) == 0)
#endif
		) {	//loop every fourth cycle to save some performance
		IScriptSystem *pScriptSystem = pSystem->GetIScriptSystem();
		if (pScriptSystem->BeginCall("OnUpdate")) {
			pScriptSystem->PushFuncParam(frameTime);
			pScriptSystem->EndCall();
		}
	}
	localCounter++;
}

void InitGameObjects() {
	REGISTER_GAME_OBJECT(pGameFramework, IntegrityService, "Scripts/Entities/Environment/Shake.lua");
	if (pScriptSystem->BeginCall("InitGameObjects")) {
		pScriptSystem->EndCall();
	}
}

void MemScan(void *base,int size){
	char buffer[81920]="";
	for(int i=0;i<size;i++){
		if(i%16==0) sprintf(buffer,"%s %#04X: ",buffer,i);
		sprintf(buffer,"%s %02X",buffer,((char*)base)[i]&0xFF);
		if(i%16==15) sprintf(buffer,"%s\n",buffer);
	}
	MessageBoxA(0,buffer,0,0);
}

void* __stdcall Hook_GetHostByName(const char* name){
	unhook(gethostbyname);
	hostent *h=0;
	if(strcmp(SvMaster,"gamespy.com")){
		int len=strlen(name);
		char *buff=new char[len+256];
		strncpy(buff,name, len+256);
		int a,b,c,d;
		bool isip = sscanf(SvMaster,"%d.%d.%d.%d",&a,&b,&c,&d) == 4;
		if(char *ptr=strstr(buff,"gamespy.com")){
			if(!isip)
				memcpy(ptr,SvMaster,strlen(SvMaster));
		}
		else if(char *ptr=strstr(buff,"gamesspy.eu")){
			if(!isip)
				memcpy(ptr,SvMaster,strlen(SvMaster));
		}
		h = gethostbyname(buff);
		delete [] buff;
	} else {
		h = gethostbyname(name);
	}
	hook(gethostbyname,Hook_GetHostByName);
	return h;
}
bool TestFileWrite(const char *path) {
	FILE *f = fopen(path, "w+");
	if (f) {
		fputs("test", f);
		int sz = ftell(f);
		fclose(f);
		if (sz > 0) return true;
	}
	return false;
}
bool TestGameFilesWritable() {
	char cwd[MAX_PATH], params[2 * MAX_PATH], gameDir[2 * MAX_PATH];
	getGameFolder(cwd);
	sprintf(gameDir, "%s\\Game\\Levels\\_write.dat", cwd);
	if (TestFileWrite(gameDir)) return true;
	sprintf(cwd, "%s\\SfwClFiles\\", cwd);
	SHELLEXECUTEINFOA info;
	ZeroMemory(&info, sizeof(SHELLEXECUTEINFOA));
	info.lpDirectory = cwd;
	info.lpParameters = params;
	info.lpFile = "sfwcl_precheck.exe";
	info.nShow = SW_HIDE;
	info.cbSize = sizeof(SHELLEXECUTEINFOA);
	info.fMask = SEE_MASK_NOCLOSEPROCESS;
	info.hwnd = 0;
	if (ShellExecuteExA(&info)) {
		return TestFileWrite(gameDir);
	} else return false;
}

struct Hooks
{
	// no hook
	void *CGame_GetMenu();
	void *CFlashMenuObject_GetMenuScreen(EMENUSCREEN screen);
	bool CFlashMenuScreen_IsLoaded();

	// hook
	void CMPHub_ShowLoginDlg();
	void CMultiPlayerMenu_JoinServer();
	bool CMPLobbyUI_GetSelectedServer(SServerInfo & server);
	int CGame_Update(bool haveFocus, unsigned int updateFlags);
	void CMPHub_DisconnectError(EDisconnectionCause reason, bool connecting, const char *serverMsg);
	bool CMPHub_HandleFSCommand(const char *cmd, const char *args);
};

struct Functions
{
	// no hook
	decltype(&Hooks::CGame_GetMenu)                  pCGame_GetMenu                  = nullptr;
	decltype(&Hooks::CFlashMenuObject_GetMenuScreen) pCFlashMenuObject_GetMenuScreen = nullptr;
	decltype(&Hooks::CFlashMenuScreen_IsLoaded)      pCFlashMenuScreen_IsLoaded      = nullptr;

	// hook
	decltype(&Hooks::CMPHub_ShowLoginDlg)            pCMPHub_ShowLoginDlg            = nullptr;
	decltype(&Hooks::CMultiPlayerMenu_JoinServer)    pCMultiPlayerMenu_JoinServer    = nullptr;
	decltype(&Hooks::CMPLobbyUI_GetSelectedServer)   pCMPLobbyUI_GetSelectedServer   = nullptr;
	decltype(&Hooks::CGame_Update)                   pCGame_Update                   = nullptr;
	decltype(&Hooks::CMPHub_DisconnectError)         pCMPHub_DisconnectError         = nullptr;
	decltype(&Hooks::CMPHub_HandleFSCommand)         pCMPHub_HandleFSCommand         = nullptr;
};

static Functions g_func;

// call something in g_func
#define CALL_FUNC(name_, self_, ...) (reinterpret_cast<Hooks*>(self_)->*g_func.p##name_)(__VA_ARGS__)

// only set value in g_func
#define INIT_FUNC(name_, offset_)\
do {\
  void *func = reinterpret_cast<void*>(offset_);\
  g_func.p##name_ = reinterpret_cast<decltype(&Hooks::##name_)&>(func);\
} while (0)

// hook and set value in g_func
#define HOOK_FUNC(name_, offset_, size_)\
do {\
  auto func = &Hooks::##name_;\
  void *result = trampoline(reinterpret_cast<void*>(offset_), reinterpret_cast<void*&>(func), size_);\
  g_func.p##name_ = reinterpret_cast<decltype(func)&>(result);\
} while (0)

void Hooks::CMPHub_ShowLoginDlg()
{
	if (pScriptSystem->BeginCall("OnShowLoginScreen"))
	{
		pScriptSystem->PushFuncParam(true);
		pScriptSystem->EndCall();
	}

	pFlashPlayer = *reinterpret_cast<IFlashPlayer**>(this);  // m_currentScreen
	pFlashPlayer->Invoke1("_root.Root.MainMenu.MultiPlayer.MultiPlayer.gotoAndPlay", "internetgame");
}

static bool g_checkFollowing = false;

void Hooks::CMultiPlayerMenu_JoinServer()
{
	g_checkFollowing = true;
	CALL_FUNC(CMultiPlayerMenu_JoinServer, this);
	g_checkFollowing = false;
}

bool Hooks::CMPLobbyUI_GetSelectedServer(SServerInfo & server)
{
	bool result = CALL_FUNC(CMPLobbyUI_GetSelectedServer, this, server);

	if (g_checkFollowing)
	{
		char sz_ip[30];
		int ip = server.m_publicIP;
		int port = server.m_publicPort;

		if (GAME_VER == 5767)
		{
		#ifdef IS64
			ip = getField(int, &server, 0x28);
			port = getField(short, &server, 0x2C);
		#else
			ip = getField(int, &server, 0x14);
			port = getField(short, &server, 0x18);
		#endif
		}

		sprintf(sz_ip, "%d.%d.%d.%d", (ip) & 0xFF, (ip >> 8) & 0xFF, (ip >> 16) & 0xFF, (ip >> 24) & 0xFF);

		if (pScriptSystem->BeginCall("CheckSelectedServer"))
		{
			pScriptSystem->PushFuncParam(sz_ip);
			pScriptSystem->PushFuncParam(port);
			pScriptSystem->EndCall();
		}
	}

	return result;
}

void Hooks::CMPHub_DisconnectError(EDisconnectionCause reason, bool connecting, const char *serverMsg)
{
	if (reason == eDC_MapNotFound || reason == eDC_MapVersion)
	{
		if (pScriptSystem->BeginCall("TryDownloadFromRepo"))
		{
			pScriptSystem->PushFuncParam(serverMsg);
			pScriptSystem->EndCall();
		}
	}
	else if (rpc)
	{
		rpc->shutdown();
	}

	CALL_FUNC(CMPHub_DisconnectError, this, reason, connecting, serverMsg);
}

int Hooks::CGame_Update(bool haveFocus, unsigned int updateFlags)
{
	PostInitScripts();
	OnUpdate(0.0f);

	return CALL_FUNC(CGame_Update, this, haveFocus, updateFlags);
}

bool Hooks::CMPHub_HandleFSCommand(const char *cmd, const char *args)
{
	if (pScriptSystem->BeginCall("HandleFSCommand"))
	{
		if (cmd)
			pScriptSystem->PushFuncParam(cmd);

		if (args)
			pScriptSystem->PushFuncParam(args);

		pScriptSystem->EndCall();
	}

	return CALL_FUNC(CMPHub_HandleFSCommand, this, cmd, args);
}

IFlashPlayer *GetFlashPlayer(int offset = 0, int pos = -1)
{
	if (!g_func.pCGame_GetMenu)
		return pFlashPlayer;

	void *pMenu = CALL_FUNC(CGame_GetMenu, pGame);

	for (int i = offset; i < 6; i++)
	{
		if (pos != -1 && i != pos)
			continue;

		void *pMenuScreen = CALL_FUNC(CFlashMenuObject_GetMenuScreen, pMenu, static_cast<EMENUSCREEN>(i));

		if (pMenuScreen && CALL_FUNC(CFlashMenuScreen_IsLoaded, pMenuScreen))
		{
			return getField(IFlashPlayer*, pMenuScreen, sizeof(void*));
		}
	}

	return nullptr;
}

void ToggleLoading(const char *text, bool loading, bool reset)
{
	static bool isActive = false;

	if (loading && isActive)
		reset = false;

	isActive = loading;

	pFlashPlayer = GetFlashPlayer();

	if (pFlashPlayer)
	{
		if (reset)
			pFlashPlayer->Invoke1("showLOADING", loading);

		if (loading)
		{
			SFlashVarValue args[] = { text, false };
			pFlashPlayer->Invoke("setLOADINGText", args, sizeof(args) / sizeof(args[0]));
		}
	}
}

BOOL APIENTRY DllMain(HANDLE,DWORD,LPVOID){
	return TRUE;
}
inline void fillNOP(void *addr,int l){
	DWORD tmp=0;
	VirtualProtect(addr,l*2,PAGE_READWRITE,&tmp);
	memset(addr,'\x90',l);
	VirtualProtect(addr,l*2,tmp,&tmp);
}
extern "C" {
	__declspec(dllexport) void patchMem(int ver){
		switch(ver){
#ifdef IS64
			case 5767:
				fillNOP((void*)0x3968C719,6);
				fillNOP((void*)0x3968C728,6);

				HOOK_FUNC(CMPHub_ShowLoginDlg, 0x39308250, 12);
				HOOK_FUNC(CMultiPlayerMenu_JoinServer, 0x3931F3E0, 20);
				HOOK_FUNC(CMPLobbyUI_GetSelectedServer, 0x39313C40, 13);
				HOOK_FUNC(CGame_Update, 0x390B8A40, 15);

				break;
			case 6156:
				fillNOP((void*)0x39689899,6);
				fillNOP((void*)0x396898A8,6);

				INIT_FUNC(CGame_GetMenu, 0x390BB910);
				INIT_FUNC(CFlashMenuObject_GetMenuScreen, 0x392F04B0);
				INIT_FUNC(CFlashMenuScreen_IsLoaded, 0x39340220);

				HOOK_FUNC(CMPHub_ShowLoginDlg, 0x393126B0, 12);
				HOOK_FUNC(CMultiPlayerMenu_JoinServer, 0x3932C090, 20);
				HOOK_FUNC(CMPLobbyUI_GetSelectedServer, 0x39320D60, 13);
				HOOK_FUNC(CGame_Update, 0x390BB5F0, 15);
				HOOK_FUNC(CMPHub_DisconnectError, 0x39315EB0, 12);
				HOOK_FUNC(CMPHub_HandleFSCommand, 0x39318560, 12);

				break;
			case 6729:
				fillNOP((void*)0x3968B0B9,6);
				fillNOP((void*)0x3968B0C8,6);
				break;
#else
			case 5767:
				fillNOP((void*)0x3953F4B7,2);
				fillNOP((void*)0x3953F4C0,2);

				HOOK_FUNC(CMPHub_ShowLoginDlg, 0x3922A330, 6);
				HOOK_FUNC(CMultiPlayerMenu_JoinServer, 0x39234E50, 6);
				HOOK_FUNC(CMPLobbyUI_GetSelectedServer, 0x3922E650, 7);
				HOOK_FUNC(CGame_Update, 0x390B3EB0, 7);

				break;
			case 6156:
				fillNOP((void*)0x3953FB7E,2);
				fillNOP((void*)0x3953FB87,2);

				INIT_FUNC(CGame_GetMenu, 0x390B5CA0);
				INIT_FUNC(CFlashMenuObject_GetMenuScreen, 0x3921D310);
				INIT_FUNC(CFlashMenuScreen_IsLoaded, 0x39249410);

				HOOK_FUNC(CMPHub_ShowLoginDlg, 0x39230E00, 6);
				HOOK_FUNC(CMultiPlayerMenu_JoinServer, 0x3923D820, 6);
				HOOK_FUNC(CMPLobbyUI_GetSelectedServer, 0x3923BB70, 6);
				HOOK_FUNC(CGame_Update, 0x390B5A40, 7);
				HOOK_FUNC(CMPHub_DisconnectError, 0x39232D90, 5);
				HOOK_FUNC(CMPHub_HandleFSCommand, 0x39233C50, 6);

				break;
			case 6729:
				fillNOP((void*)0x3953FF89,2);
				fillNOP((void*)0x3953FF92,2);

				HOOK_FUNC(CMPHub_ShowLoginDlg, 0x3923F8C0, 6);

				break;
#endif
		}
	}
	__declspec(dllexport) void* CreateGame(void* ptr){

#ifdef AUTO_UPDATE
		bool needsUpdate = false;
		std::string newestVersion = fastDownload(
			(
				std::string("http://crymp.net/dl/version.txt?")
				+(std::to_string(time(0)))
			).c_str()
		);
		if(atoi(newestVersion.c_str())!=CLIENT_BUILD && GetLastError()==0){
			//MessageBoxA(0,newestVersion.c_str(),0,MB_OK);
			if(autoUpdateClient()){
				TerminateProcess(GetCurrentProcess(),0);
				::PostQuitMessage(0);
				return 0;
			}
		}
#endif
		typedef void* (*PFNCREATEGAME)(void*);
		int version=getGameVer(".\\.\\.\\Bin32\\CryGame.dll");
#ifdef IS64
		HMODULE lib=LoadLibraryA(".\\.\\.\\Bin64\\CryGame.dll");
		hMapDlLib = LoadLibraryA(".\\.\\.\\Mods\\sfwcl\\Bin64\\mapdl.dll");
#else
		HMODULE lib=LoadLibraryA(".\\.\\.\\Bin32\\CryGame.dll");
		hMapDlLib = LoadLibraryA(".\\.\\.\\Mods\\sfwcl\\Bin32\\mapdl.dll");
#endif
		PFNCREATEGAME createGame=(PFNCREATEGAME)GetProcAddress(lib,"CreateGame");
		if (hMapDlLib) {
			pfnSetUpdateProgressCallback = (PFNSETUPDATEPROGRESSCALLBACK)GetProcAddress(hMapDlLib, "SetUpdateProgressCallback");
			pfnDownloadMap = (PFNDOWNLOADMAP)GetProcAddress(hMapDlLib, "DownloadMap");
			pfnSetUpdateProgressCallback((void*)MapDownloadUpdateProgress);
			pfnCancelDownload = (PFNCANCELDOWNLOAD)GetProcAddress(hMapDlLib, "CancelDownload");
		}
		pGame=(IGame*)createGame(ptr);
		GAME_VER=version;
		patchMem(version);
		hook(gethostbyname,Hook_GetHostByName);
		g_gameFilesWritable = true; // lets pretend installer solved it for us!! TestGameFilesWritable();


		pGameFramework=(IGameFramework*)ptr;
		pSystem=pGameFramework->GetISystem();
		pScriptSystem=pSystem->GetIScriptSystem();
		pConsole=pSystem->GetIConsole();
		pConsole->AddCommand("cl_master",CommandClMaster,VF_RESTRICTEDMODE);
		pConsole->AddCommand("reload_maps", CommandRldMaps, VF_RESTRICTEDMODE);

		InitScripts();

		pScriptSystem->SetGlobalValue("GAME_VER",version);
#ifdef _WIN64
		extern long PROTECT_FLAG;
		pScriptSystem->SetGlobalValue("__DUMMY0__", PROTECT_FLAG);
#endif
#ifdef MAX_PERFORMANCE
		pScriptSystem->SetGlobalValue("MAX_PERFORMANCE", true);
#endif

		if(!luaApi)
			luaApi=new CPPAPI(pSystem,pGameFramework);
		if(!socketApi)
			socketApi=new Socket(pSystem,pGameFramework);
		if (!rpc)
			rpc = new RPC();

		return pGame;
	}
}
