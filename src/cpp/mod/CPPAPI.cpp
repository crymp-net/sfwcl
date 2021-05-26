#include "CPPAPI.h"
#include "AtomicCounter.h"
#include "Atomic.h"
#include "Crypto.h"
#include "RPC.h"

#include <sstream>
#include <string>
#include <vector>

#include <IEntity.h>
#include <IEntitySystem.h>
#include <IVehicleSystem.h>
#include <IGameObjectSystem.h>
#include <IConsole.h>
#include <ISystem.h>
#include <I3DEngine.h>
#include <WinSock2.h>
#include <Windows.h>
#include <shellapi.h>

#pragma region CPPAPI

extern std::list<AsyncData*> asyncQueue;
extern int asyncQueueIdx;
extern std::map<std::string, std::string> asyncRetVal;
extern IScriptSystem *pScriptSystem;

bool DownloadMapFromObject(DownloadMapStruct *now);

HANDLE gEvent;

CPPAPI::CPPAPI(ISystem *pSystem, IGameFramework *pGameFramework)
	:	m_pSystem(pSystem),
		m_pSS(pSystem->GetIScriptSystem()),
		m_pGameFW(pGameFramework)
{
	Init(m_pSS, m_pSystem);
	gEvent=CreateEvent(0,0,0,0);
	threads.push_back(CreateThread(0, 0, (LPTHREAD_START_ROUTINE)AsyncThread, 0, 0, 0));
	threads.push_back(CreateThread(0, 0, (LPTHREAD_START_ROUTINE)AsyncThread, 0, 0, 0));
	SetGlobalName("CPPAPI");
	RegisterMethods();
}
CPPAPI::~CPPAPI(){
	for (auto& thread : threads) {
		TerminateThread(thread, 0);
	}
}
void CPPAPI::RegisterMethods(){
#undef SCRIPT_REG_CLASSNAME
#define SCRIPT_REG_CLASSNAME &CPPAPI::
	SetGlobalName("CPPAPI");
	SCRIPT_REG_TEMPLFUNC(FSetCVar,"cvar, value");
	SCRIPT_REG_TEMPLFUNC(Random,"");
	SCRIPT_REG_TEMPLFUNC(MapAvailable,"host");
	SCRIPT_REG_TEMPLFUNC(DownloadMap,"mapnm,mapurl");
	SCRIPT_REG_TEMPLFUNC(ConnectWebsite,"host, page, port, http11, timeout, methodGet");
	SCRIPT_REG_TEMPLFUNC(GetIP,"host");
	SCRIPT_REG_TEMPLFUNC(GetLocalIP,"");
	SCRIPT_REG_TEMPLFUNC(GetMapName,"");
	SCRIPT_REG_TEMPLFUNC(ApplyMaskAll,"mask,apply");
	SCRIPT_REG_TEMPLFUNC(ApplyMaskOne,"ent,mask,apply");
	SCRIPT_REG_TEMPLFUNC(AsyncConnectWebsite,"host, page, port, http11, timeout, methodGet");
	SCRIPT_REG_TEMPLFUNC(MsgBox,"text,title,mask");
	SCRIPT_REG_TEMPLFUNC(DoAsyncChecks, "");
	SCRIPT_REG_TEMPLFUNC(AsyncDownloadMap, "mapn, mapdl");
	SCRIPT_REG_TEMPLFUNC(ToggleLoading, "text, loading, reset");
	SCRIPT_REG_TEMPLFUNC(CancelDownload, "");
	SCRIPT_REG_TEMPLFUNC(MakeUUID, "salt");
	SCRIPT_REG_TEMPLFUNC(SHA256, "text");
	SCRIPT_REG_TEMPLFUNC(GetLocaleInformation, "");
	SCRIPT_REG_TEMPLFUNC(SignMemory, "addr1, addr2, nonce, len, id");
	SCRIPT_REG_TEMPLFUNC(InitRPC, "ip, port");
	SCRIPT_REG_TEMPLFUNC(SendRPCMessage, "method, params...");
}
int CPPAPI::SendRPCMessage(IFunctionHandler *pH, const char *method, SmartScriptTable params) {
	IScriptTable::Iterator it = params->BeginIteration();
	std::vector<const char*> args;
	while (params->MoveNext(it)) {
		args.push_back(it.value.str);
	}
	extern RPC* rpc;
	if (rpc && rpc->active) {
		rpc->sendMessage(method, args);
		return pH->EndFunction(true);
	}
	return pH->EndFunction(false);
}
int CPPAPI::InitRPC(IFunctionHandler *pH, const char *ip, int port) {
	unsigned int a, b, c, d;
	sscanf(ip, "%d.%d.%d.%d", &a, &b, &c, &d);
	unsigned long i = (a << 24) | (b << 16) | (c << 8) | d;
	extern RPC *rpc;
	if (rpc) {
		rpc->establish(i, port & 0xFFFF);
		return pH->EndFunction(rpc->active);
	} else {
		return pH->EndFunction(false);
	}
}
int CPPAPI::SHA256(IFunctionHandler *pH, const char *text) {
	unsigned char digest[32];
	char hash[80];
	sha256((const unsigned char*)text, strlen(text), digest);
	for (int i = 0; i < 32; i++) {
		sprintf(hash + i * 2, "%02X", digest[i] & 255);
	}
	return pH->EndFunction(hash);
}
int CPPAPI::MakeUUID(IFunctionHandler *pH, const char *salt) {
	char hwid[256];
	char pool[256];
	unsigned char digest[32];

	HKEY hkey = 0;
	LSTATUS res = RegOpenKeyExA(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Cryptography", 0, KEY_READ | KEY_WOW64_64KEY, &hkey);
	if (SUCCEEDED(res)) {
		DWORD dwBufferSize = sizeof(hwid);
		ULONG nError;
		nError = RegQueryValueExA(hkey, "MachineGuid", 0, NULL, (LPBYTE)hwid, &dwBufferSize);
		if (ERROR_SUCCESS != nError) strcpy(hwid, "unknown_uuid");
	} else strcpy(hwid, "unknown_uuid");

	sha256((const unsigned char*)hwid, strlen(hwid), digest);

	memset(hwid, 0, sizeof(hwid));
	for (int i = 0; i < 32; i++) {
		sprintf(hwid + i * 2, "%02X", digest[i] & 255);
	}

	strcpy(pool, hwid);
	strcat(pool, salt);
	sha256((const unsigned char*)pool, strlen(pool), digest);
	strcpy(pool, hwid);
	strcat(pool, ":");
	int len = strlen(pool);
	for (int i = 0; i < 32; i++) {
		sprintf(pool + len + i * 2, "%02X", digest[i] & 255);
	}
	return pH->EndFunction(pool);
}
int CPPAPI::GetLocaleInformation(IFunctionHandler *pH) {
	char buffer[32];
#ifndef LOCALE_SNAME
#define LOCALE_SNAME 0x5C
#endif
	GetLocaleInfoA(LOCALE_USER_DEFAULT, LOCALE_SNAME, buffer, sizeof(buffer));
	TIME_ZONE_INFORMATION tzinfo;
	GetTimeZoneInformation(&tzinfo);
	return pH->EndFunction(buffer, tzinfo.Bias);
}
int CPPAPI::SignMemory(IFunctionHandler *pH, const char *a1, const char *a2, const char *len, const char *nonce, const char *id) {
	std::stringstream a1s, a2s, ls, ns;
	a1s << a1;
	a2s << a2;
	ls << len;
	ns << nonce;
	std::string pa1, pa2, pl, pn;
	std::string h = "";
	while ((a1s >> pa1) && (a2s >> pa2) && (ls >> pl) && (ns >> pn)) {
		if (isdigit(pa1[0])) {
			unsigned long addr1 = 0, addr2 = 0;
			sscanf(pa1.c_str(), "%lx", &addr1);
			sscanf(pa2.c_str(), "%lx", &addr2);
#ifdef _WIN64
			unsigned long long addr = 0;
			addr |= addr1;
			addr <<= 32;
#else
			unsigned long addr = 0;
#endif
			addr |= addr2;
			void *ptr = (void*)addr;
			h += ::SignMemory(ptr, atoi(pl.c_str()), pn.c_str(), true);
		} else if (pa1 == "file" || pa1=="FILE") {
			if (pa2.find("..") == std::string::npos && pa2.find(".\\") == std::string::npos) {
				h += SignFile(pa2.c_str(), pn.c_str(), true);
			}
		}
	}
	std::string hash = "";
	unsigned char digest[32];
	sha256((const unsigned char*)h.c_str(), h.size(), digest);
	for (int i = 0; i < 32; i++) {
		static char bf[4];
		sprintf(bf, "%02X", digest[i] & 255);
		hash += bf;
	}
	return pH->EndFunction(hash.c_str());
}
int CPPAPI::ToggleLoading(IFunctionHandler *pH, const char *text, bool loading, bool reset) {
	::ToggleLoading(text, loading, reset);
	return pH->EndFunction(true);
}
int CPPAPI::FSetCVar(IFunctionHandler* pH,const char * cvar,const char *val){
	if(ICVar *cVar=pConsole->GetCVar(cvar))
		cVar->ForceSet(val);
	return pH->EndFunction(true);
}
int CPPAPI::Random(IFunctionHandler* pH){
	static bool set=false;
	if(!set){
		srand(time(0)^clock());
		set=true;
	}
	return pH->EndFunction(rand());
}
int CPPAPI::ConnectWebsite(IFunctionHandler* pH,char * host,char * page,int port,bool http11,int timeout,bool methodGet,bool alive){
	using namespace Network; 
	std::string content="Error";
	content=Connect(host,page,methodGet?INetGet:INetPost,http11?INetHTTP11:INetHTTP10,port,timeout,alive);
	return pH->EndFunction(content.c_str());
}
int CPPAPI::GetIP(IFunctionHandler* pH,char* host){
	if(strlen(host)>0){
		char ip[255];
		Network::GetIP(host,ip);
		return pH->EndFunction(ip);
	}
	return pH->EndFunction();
}
int CPPAPI::GetLocalIP(IFunctionHandler* pH){
    char hostn[255];
    if (gethostname(hostn, sizeof(hostn))!= SOCKET_ERROR) {
        hostent *host = gethostbyname(hostn);
        if(host){
            for (int i = 0; host->h_addr_list[i] != 0; ++i) {
                struct in_addr addr;
                memcpy(&addr, host->h_addr_list[i], sizeof(struct in_addr));
				return pH->EndFunction(inet_ntoa(addr));
            }
        }
    }
	return pH->EndFunction();
}
int CPPAPI::GetMapName(IFunctionHandler *pH){
	return pH->EndFunction(pGameFramework->GetLevelName());
}
int CPPAPI::DoAsyncChecks(IFunctionHandler *pH) {
#ifdef DO_ASYNC_CHECKS
	extern Mutex g_mutex;
	IScriptTable *tbl = pScriptSystem->CreateTable();
	tbl->AddRef();
	std::vector<IScriptTable*> refs;
	//commonMutex.lock();
	g_mutex.Lock();
	for (std::map<std::string, std::string>::iterator it = asyncRetVal.begin(); it != asyncRetVal.end(); it++) {
		IScriptTable *item = pScriptSystem->CreateTable();
		item->AddRef();
		item->PushBack(it->first.c_str());
		item->PushBack(it->second.c_str());
		tbl->PushBack(item);
		refs.push_back(item);
	}
	g_mutex.Unlock();
	int code = pH->EndFunction(tbl);
#ifdef OLD_MSVC_DETECTED
	for (size_t i = 0; i < refs.size(); i++ ) {
		SAFE_RELEASE(refs[i]);
	}
#else
	for (auto& it : refs) {
		SAFE_RELEASE(it);
	}
#endif
	SAFE_RELEASE(tbl);
	return code;
#else
	return pH->EndFunction(0);
#endif
}
int CPPAPI::MapAvailable(IFunctionHandler *pH,const char *_path){
	char *ver=0;
	char path[255];
	strncpy(path,_path,255);
	for(int i=0,j=strlen(path);i<j;i++){
		if(path[i]=='|'){
			path[i]=0;
			ver=path+i+1;
		}
	}
	char mpath[255];
	strncpy(mpath,path,255);
	for(int i=0,j=strlen(mpath);i<j;i++)
		mpath[i]=mpath[i]=='/'?'\\':mpath[i];
	ILevelSystem *pLevelSystem = pGameFramework->GetILevelSystem();
	if(pLevelSystem){
		pLevelSystem->Rescan();
		for(int l = 0; l < pLevelSystem->GetLevelCount(); ++l){
			ILevelInfo *pLevelInfo = pLevelSystem->GetLevelInfo(l);
			if(pLevelInfo){
				if(_stricmp(pLevelInfo->GetName(),path)==0){
					bool exists=true;
					if(ver){
						char cwd[MAX_PATH], lpath[2 * MAX_PATH];
						getGameFolder(cwd);
						sprintf(lpath,"%s\\Game\\_levels.dat",cwd);
						FILE *f=fopen(lpath,"r");
						if(f){
							char name[255];
							char veri[255];
							while(!feof(f)){
								fscanf(f,"%s %s",name,veri);
								if(!strcmp(name,mpath)){
									exists=!strcmp(veri,ver);
									break;
								}
							}
							fclose(f);
						}
					}
					return pH->EndFunction(exists);
				}
			}
		}
	}
	return pH->EndFunction(false);
}
int CPPAPI::DownloadMap(IFunctionHandler *pH,const char *mapn,const char *mapdl){
	DownloadMapStruct *now=new DownloadMapStruct;
	if(now){
		//ToggleLoading("Downloading map",true);
		now->mapdl=mapdl;
		now->mapn=mapn;
		now->success = false;
		//CreateAsyncCallLua(AsyncDownloadMap,now);
		now->success = DownloadMapFromObject(now);
		return pH->EndFunction(now->success);
	}
	return pH->EndFunction();
}
int CPPAPI::CancelDownload(IFunctionHandler *pH) {
	extern PFNCANCELDOWNLOAD pfnCancelDownload;
	if (pfnCancelDownload) pfnCancelDownload();
	return pH->EndFunction();
}
int CPPAPI::AsyncConnectWebsite(IFunctionHandler* pH, char * host, char * page, int port, bool http11, int timeout, bool methodGet, bool alive) {
	using namespace Network;
	ConnectStruct *now = new ConnectStruct;
	if (now) {
		now->host = host;
		now->page = page;
		now->method = methodGet ? INetGet : INetPost;
		now->http = http11 ? INetHTTP11 : INetHTTP10;
		now->port = port;
		now->timeout = timeout;
		now->alive = alive;
		return now->callAsync(pH);
	}
	return pH->EndFunction();
}
int CPPAPI::AsyncDownloadMap(IFunctionHandler* pH, const char *path, const char *link) {
	DownloadMapStruct *now = new DownloadMapStruct();
	if (now) {
		now->mapdl = link;
		now->mapn = path;
		now->isAsync = true;
		return now->callAsync(pH);
	}
	return pH->EndFunction();
}
#pragma region Fun
int CPPAPI::ApplyMaskAll(IFunctionHandler* pH,int amask,bool apply){
	IEntitySystem *pES=pSystem->GetIEntitySystem();
	if(pES){
		IEntityIt* it=pES->GetEntityIterator();
		int c=0;
		while(!it->IsEnd()){
			IEntity *pEntity=it->This();
			int fmask=amask;
			if(fmask==MTL_LAYER_FROZEN && apply){
				IVehicleSystem *pVS=pGameFramework->GetIVehicleSystem();
				if(pVS->GetVehicle(pEntity->GetId()))
					fmask=MTL_LAYER_DYNAMICFROZEN;
			}
			IEntityRenderProxy *pRP=(IEntityRenderProxy*)pEntity->GetProxy(ENTITY_PROXY_RENDER);
			if(pRP){
				int mask=pRP->GetMaterialLayersMask();
				if(apply)
					mask|=fmask;
				else mask&=~fmask;
				pRP->SetMaterialLayersMask(mask);
			}
			c++;
			it->Next();
		}
		return pH->EndFunction(c);
	}
	return pH->EndFunction();
}
int CPPAPI::ApplyMaskOne(IFunctionHandler* pH,ScriptHandle entity,int amask,bool apply){
	IEntitySystem *pES=pSystem->GetIEntitySystem();
	if(pES){
		IEntity *pEntity=pES->GetEntity(entity.n);
		if(pEntity){
			IEntityRenderProxy *pRP=(IEntityRenderProxy*)pEntity->GetProxy(ENTITY_PROXY_RENDER);
			if(pRP){
				int mask=pRP->GetMaterialLayersMask();
				if(apply)
					mask|=amask;
				else mask&=~amask;
				pRP->SetMaterialLayersMask(mask);
				return pH->EndFunction(true);
			}
		}
	}
	return pH->EndFunction(false);
}
int CPPAPI::MsgBox(IFunctionHandler* pH,const char *text,const char *title,int buttons){
	MessageBoxA(0,text,title,buttons);
	return pH->EndFunction();
}
#pragma endregion

#pragma endregion

#pragma region AsyncStuff
#ifdef OLD_MSVC_DETECTED
BOOL WINAPI DownloadMapStructEnumProc(HWND hwnd, LPARAM lParam) {
	DownloadMapStruct::Info *pParams = (DownloadMapStruct::Info*)(lParam);
	DWORD processId;
	if (GetWindowThreadProcessId(hwnd, &processId) && processId == pParams->pid) {
		SetLastError(-1);
		pParams->hWnd = hwnd;
		return FALSE;
	}
	return TRUE;
}
#endif
bool DownloadMapFromObject(DownloadMapStruct *now) {
	IRenderer *pRend = pSystem->GetIRenderer();
	const char *mapn = now->mapn;
	const char *mapdl = now->mapdl;
	HWND hwnd = (HWND)pRend->GetHWND();
	//ShowWindow(hwnd,SW_MINIMIZE);
	char cwd[MAX_PATH], params[2 * MAX_PATH];
	getGameFolder(cwd);
	sprintf(cwd, "%s\\SfwClFiles\\", cwd);
	extern PFNDOWNLOADMAP pfnDownloadMap;
	bool ret = true;
	if (pfnDownloadMap) {
		extern Atomic<const char*> mapDlMessage;
		mapDlMessage.set(0);
		int code = pfnDownloadMap(mapn, mapdl, cwd);
		//sprintf(cwd, "Error: %d (%x)", code, code);
		//MessageBoxA(0, cwd, 0, 0);
		//CryLogAlways("Download error: %x", code);
		if (code) ret = false;
	}
	if (!now->isAsync) {
		ILevelSystem *pLevelSystem = pGameFramework->GetILevelSystem();
		if (pLevelSystem) {
			pLevelSystem->Rescan();
		}
		ShowWindow(hwnd, SW_MAXIMIZE);
	}
	return ret;
}
void AsyncConnect(int id, AsyncData *obj) {
	//GetAsyncObj(ConnectStruct,now);
	ConnectStruct *now = (ConnectStruct *)obj;
	std::string content = "\\\\Error: Unknown error";
	if (now) {
		now->lock();
		std::string host = now->host;
		std::string page = now->page;
		Network::INetMethods method = now->method, http = now->http;
		unsigned short port = now->port;
		int timeout = now->timeout;
		bool alive = now->alive;
		now->unlock();
		content = Network::Connect(host, page, method, http, port, timeout, alive);
	}
	if (content.length() > 2) {
		if (content[0] == 0xFE && content[1] == 0xFF) content = content.substr(2);
	}
	obj->ret(content.c_str());
}
bool AsyncDownloadMap(int id, AsyncData *obj) {
	DownloadMapStruct *now = (DownloadMapStruct*)obj;
	if (now) {
		now->success = DownloadMapFromObject(now);
		now->ret(now->success);
		return now->success;
	}
	return false;
}
static void AsyncThread(){
	extern Mutex g_mutex; 
	extern moodycamel::BlockingConcurrentQueue<AsyncData*> asyncRequestQueue;
	extern moodycamel::BlockingConcurrentQueue<AsyncData*> asyncResponseQueue;
	WSADATA data;
	WSAStartup(0x202, &data);
	while(true){
		AsyncData* obj = 0;
		asyncRequestQueue.wait_dequeue(obj);
		g_mutex.Lock();
		if(obj && !obj->finished){
			obj->executing = true;
			obj->finished = false;
			asyncResponseQueue.enqueue(obj);
			g_mutex.Unlock();
			obj->exec();
			g_mutex.Lock();
			obj->finished=true;
		}
		g_mutex.Unlock();
	}
	WSACleanup();
}
void GetClosestFreeItem(int *out){
	static AtomicCounter idx(0);
	*out = idx.increment();
}
#pragma endregion
