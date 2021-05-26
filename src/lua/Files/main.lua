SFWCL_VERSION="11"
SFWCL_NUMVERSION = 110
ASYNC_MAPS = true

REALISM=0;
CHANGEDREAL=true;
CONNTIMER=nil;

MASK_FROZEN=1;
MASK_WET=2;
MASK_CLOAK=4;
MASK_DYNFROZEN=8;
UP_SUCC_CB=function() return 1 end

UPDATED_SELF = false;

MASTER_ADDR="crymp.net";
MASTER_FN = "SmartHTTPS";
CDN_ADDR="api.crymp.net";
CDN_FN = "SmartHTTPS";
RPC_ID = "<unknown>";

ActiveAnims = {}
ActiveFx = {}

ALLOW_HWID_BOUND = true
RPC_STATE = true

STATIC_ID = ""
STATIC_HASH = ""

local agun=true

function GetUserName()
	local files=System.ScanDirectory("C:\\Users",0,1);
	local skip = { ["Default"] = true; ["Public"] = true; ["Shared"]=true; }
	local usr = nil
	if(files)then
		for i,file in pairs(files) do
			if not skip[file] then
				local try = System.ScanDirectory("C:\\Users\\"..file, 0,1)
				if #try>0 then usr=file end 
				if file == "All Users" then return file end
			end
		end
	end
	return usr
end

UPDATED_SELF = false;
joiningServer = false
downloadingMap = false

AsyncAwait={};

function OnRPCEvent(method, id, ...)
	if(method == "id") then RPC_ID = id; end
	if method ~= "id" then
		pcall(OnServerMessage, nil, id, method, ...)
	end
end
function OnUpdate(frameTime, inQueue, frame)
	if CPPAPI then
		local ret=CPPAPI.DoAsyncChecks();
		if ret and type(ret)=="table" and #ret>0 then
			for i,v in pairs(ret) do
				_G[v[1]]=v[2];
				--printf("_G['%s']='%s'",v[1],v[2]);
			end
		end 
	end
	for i,v in pairs(AsyncAwait) do
		if v~=nil then
			local idx=v[1];
			local func=v[2];
			local ret=_G["AsyncRet"..idx];
			if ret~=nil then
				--printf("Async got return for "..idx..": "..ret);
				pcall(func,ret);
				AsyncAwait[i]=nil;
				_G["AsyncRet"..idx]=nil;
			end
		end
	end
	return 1;
end

function InitGameObjects()
	UpdateSelf()
end

function RPCExtend(svc, id, msgType, command)
	if msgType and command and msgType == "@" then
		local what = json.decode(command)
		if what and what.method then
			local method = RPC[what.method]
			if what.class then
				method = RPC[what.class].method
				if method then
					method(RPC[what.class], what.params)
				end
			elseif method then
				method(what.params)
			end
		end
		return true
	end
end

function OnServerMessage(svc, id, msgType, ...)
	local msg = {...};
	msg = msg[1] or "";
	
	if RPCExtend(svc, id, msgType, ...) then
		--...
	elseif msgType == "uuid" then
		local salt = {...};
		CPPAPI.SendRPCMessage(msgType, { id , CPPAPI.MakeUUID(salt[1]) });
	elseif msgType == "locale" then
		local lang, tz = CPPAPI.GetLocaleInformation()
		if svc then
			svc.server:SvOnReceiveMessage(id, msgType, lang..","..tz);
		else
			CPPAPI.SendRPCMessage(msgType, { id, lang..","..tz });
		end
	elseif msgType=="sign" then
		local nonces, a1, a2, lens = ...;
		CPPAPI.SendRPCMessage(msgType, { id, CPPAPI.SignMemory(a1, a2, lens, nonces, id), a1, a2, lens })
	elseif OnServerMessageEx then
		if not OnServerMessageEx(svc, id, msgType, ...) then
			if svc then
				svc.server:SvOnReceiveMessage(id, msgType, msg);
			else
				CPPAPI.SendRPCMessage(msgType, { id, ... });
			end
		end
	else
		if svc then
			CPPAPI.SendRPCMessage(msgType, { id, ... });
		else
			svc.server:SvOnReceiveMessage(id, msgType, msg);
		end
	end
end
function HandleFSCommand(cmd, args)
	--printf("HandleFSCommand(%s, %s)", cmd or "<unknown>", args or "<unknown>")
	if cmd=="JoinServer" then
		joiningServer = true;
	elseif cmd == "LoadingCanceled" then
		if joiningServer then
			if downloadingMap then
				CPPAPI.CancelDownload()
			end
			joiningServer = false;
		end
	end
end
function AsyncCreateId(id,func)
	--printf("Created Async call: "..id)
	if id then
		AsyncAwait[#AsyncAwait+1]={id,func};
	else
		printf("AsyncCreateId fail");
	end
end
function AsyncCreate(callback,func,...)
	local id=func(...);
	--printf("Created Async call: "..id)
	if id then
		AsyncAwait[#AsyncAwait+1]={id,callback};
	end
end
function AsyncConnectHTTP(host,url,method,port,http11,timeout,func)
	--printf("Connecting %s",host);
	--printf("URL: %s",(url:gsub("[%%]","#")) or "nil");
	method=method or "GET";
	method=method:upper();
	AsyncConnCtr=(AsyncConnCtr or 0)+1;
	AsyncCreateId(CPPAPI.AsyncConnectWebsite(host,url,port or 80,http11 or false,timeout,method=="GET" and true or false,false),func);
end
function AsyncDownloadMap(a,b,func)
	--printf("Downloading %s [%s]", a, b);
	downloadingMap = true;
	AsyncCreateId(CPPAPI.AsyncDownloadMap(a,b),func);
end
function SmartHTTP(method,host,url,func)
	local lang, tz = CPPAPI.GetLocaleInformation();
	if url:find("?") then
		url = url .. "&rqt="..string.format("%d",os.time());
	else
		url = url .. "?rqt="..string.format("%d",os.time());
	end
	url=url..urlfmt("&hwid=%s&tz=%s&lng=%s", CPPAPI.MakeUUID("idsvc"), tostring(tz), tostring(lang));
	return AsyncConnectHTTP(host,url,method,80,true,5000,function(ret)
		if ret:sub(1,8)=="\\\\Error:" then
			func(ret:sub(3),true)
		else func(ret,false); end
	end);
end
function SmartHTTPS(method,host,url,func)
	local lang, tz = CPPAPI.GetLocaleInformation();
	if url:find("?") then
		url = url .. "&rqt="..string.format("%d",os.time());
	else
		url = url .. "?rqt="..string.format("%d",os.time());
	end
	url=url..urlfmt("&hwid=%s&tz=%s&lng=%s", CPPAPI.MakeUUID("idsvc"), tostring(tz), tostring(lang));
	return AsyncConnectHTTP(host,url,method,443,true,5000,function(ret)
		if ret:sub(1,8)=="\\\\Error:" then
			func(ret:sub(3),true)
		else func(ret,false); end
	end);
end
function printf(fmt,...)
	local txt=string.format(fmt,...);
	System.LogAlways(txt);
	return txt:len();
end

--SafeWritingClient:
printf("Creating login-system!");
System.SetCVar("log_verbosity",0);
System.SetCVar("log_fileverbosity",0);
function LogMe(prof,uid,name)
	if g_localActor then
		local cmd=string.format("!validate %s %s %s",prof,uid,name);
		g_gameRules.game:SendChatMessage(ChatToTarget,g_localActor.id,g_localActor.id,cmd);
		g_gameRules.game:SendChatMessage(ChatToTarget,g_localActor.id,g_localActor.id,"!sync "..RPC_ID);
		if CONNTIMER then
			Script.KillTimer(CONNTIMER);
		end
	end
end
function SetAuthProf(pr)
	--printf("Profile: %s",pr);
	AUTH_PROFILE=pr;
end
function SetAuthName(n)
	--printf("Name: %s",n);
	AUTH_NAME=n;
end
function SetAuthUID(u)
	--printf("UID: %s",u);
	AUTH_UID=u;
end
function SetAuthPwd(p)
	--printf("Password: %s",p);
	AUTH_PWD=p;
	PWDSET=true;
	System.ExecuteCommand("sv_password "..p);
	System.SetCVar("sv_password",p);
	if CPPAPI and CPPAPI.FSetCVar then
		CPPAPI.FSetCVar("sv_password",p);
	end
end
function AuthLogin()
	if AUTH_PROFILE and AUTH_NAME and AUTH_UID then
		LogMe(AUTH_PROFILE,AUTH_UID,AUTH_NAME);
	end
end
function AuthConn(s)
	SERVER_IP=s;
	if s:find("0.0.0.0") then
		return;
	end
	if AUTH_PWD then
		System.ExecuteCommand("sv_password "..AUTH_PWD);
	end
	System.ExecuteCommand("disconnect");
	CON_HIDDEN=nil;
	if CONNTIMER then
		Script.KillTimer(CONNTIMER);
	end
	CONNTIMER=Script.SetTimer(1500,function()
		local sv=FROM_SVLIST;
		if sv then
			printf("$3Joining $6%s$3 ($5%s$8:$5%d$3) as $6%s",sv.name,sv.ip,tonumber(sv.port),AUTH_NAME);
		end
		System.ExecuteCommand("connect "..SERVER_IP);
		if not FROM_SVLIST then
			CryAction.Persistant2DText("Connecting to server, please wait", 2, {0.9,0.9,0.9}, "Conn Msg", 50);
		end
		--System.ExecuteCommand("ConsoleHide 1");
		CONNTIMER=Script.SetTimer(FROM_SVLIST and 90000 or 45000,function()
			if not InstantAction then
				if not FROM_SVLIST then
					System.ExecuteCommand("i_reload");
					CONNTIMER=Script.SetTimer(1500,function()
						AuthRetry();
					end);
				else
					printf("$4Failed to connect after 91.5 seconds");
				end
			end
		end);
	end);
end
function AuthRetry()
	if not SERVER_IP then return; end
	TRYNR=(TRYNR or 0)+1;
	System.ExecuteCommand("connect "..SERVER_IP);
	if not FROM_SVLIST then
		CryAction.Persistant2DText("Retrying to connect #"..TRYNR, 2, {0.7,0.7,0.7}, "ReConn Msg", 50);
	end
	CONNTIMER=Script.SetTimer(FROM_SVLIST and 90000 or 45000,function()
		if not InstantAction then
			System.ExecuteCommand("i_reload");
			CONNTIMER=Script.SetTimer(1500,function()
				AuthRetry();
			end)
		end
	end);
end
function HideEntity(ent)
	ent:SetPos({x=256;y=256;z=4096;})
end
function SpawnEffect(ent,name)
	Particle.SpawnEffect(name, ent:GetPos(), ent:GetDirectionVector(1), 1);
	System.RemoveEntity(ent.id);
end
function UpdateForEntity(v)
	local name=v:GetName() or "<unknown>";
	local ignoreEff=false;
	if name=="frozen:all" then CPPAPI.ApplyMaskAll(MASK_FROZEN,1); HideEntity(v); ignoreEff=true;
	elseif name=="dynfrozen:all" then CPPAPI.ApplyMaskAll(MASK_DYNFROZEN,1);  HideEntity(v); ignoreEff=true;
	elseif name=="wet:all" then CPPAPI.ApplyMaskAll(MASK_WET,1);  HideEntity(v); ignoreEff=true;
	elseif name=="cloak:all" then CPPAPI.ApplyMaskAll(MASK_CLOAK,1); HideEntity(v); ignoreEff=true;
	elseif(name:sub(1,7)=="frozen:") then
		CPPAPI.ApplyMaskOne(v.id,MASK_FROZEN, 1);
	elseif(name:sub(1,10)=="dynfrozen:") then
		CPPAPI.ApplyMaskOne(v.id,MASK_DYNFROZEN, 1);
	elseif(name:sub(1,4)=="wet:") then
		CPPAPI.ApplyMaskOne(v.id,MASK_WET, 1);
	elseif(name:sub(1,6)=="cloak:") then
		CPPAPI.ApplyMaskOne(v.id,MASK_CLOAK, 1);
	elseif(name:sub(1,3)=="fx:") then
		SpawnEffect(v,name:sub(4));
	end
	v:SetFlags(ENTITY_FLAG_CASTSHADOW, 0);
	--printf("Applied fx to %s", v:GetName() or "Unknown")
	v.effApplied=not ignoreEff;
end
function UpdateRealism()
	if g_localActor and INGAME then
		local stuff=System.GetEntitiesByClass("CustomAmmoPickup");
		local c=0;
		if stuff then
			for i,v in pairs(stuff) do
				UpdateForEntity(v);
				c=c+1;
			end
		end
		return c;
	end
	return 0;
end
function Realism(...)
	local val=...;
	if not val then
		printf("$3    realism$3 = $6%d",REALISM==2 and 0 or 1);
	else
		local v=tonumber(val);
		if v and v==1 then
			REALISM=0;
			CHANGEDREAL=true;
		end
		if v and v==0 then
			REALISM=2;
			CHANGEDREAL=true;
		end
		printf("$3    realism$3 = $6%d",REALISM==2 and 0 or 1);
	end
end
System.AddCCommand("auth_id","SetAuthProf(%line)","Sets authentication profile ID");
System.AddCCommand("auth_name","SetAuthName(%line)","Sets authentication name");
System.AddCCommand("auth_uid","SetAuthUID(%line)","Sets authentication profile ID");
System.AddCCommand("auth_login","AuthLogin()","Authenticates you");
System.AddCCommand("auth_conn","AuthConn(%line)","Connects you to server");
System.AddCCommand("auth_retry","AuthRetry()","Retries connection");
System.AddCCommand("auth_pwd","SetAuthPwd(%line)","Sets authentication password");
System.AddCCommand("realism",[[
	Realism(%%);
]],"Enables/Disables realism");
--System.SetCVar("log_verbosity",1);
printf("Log-in system successfuly created");


function GetGameVer()
	if GAME_VER then
		System.LogAlways("GameVer from $3sfwcl.dll");
		return GAME_VER;
	end
	if System.GetCVar("g_spawnDebug") then return 6729; end
	local ver=5767;
	local val=System.GetCVar("r_PostProcessEffects");
	local val2=val=="0" and "1" or "0";
	System.SetCVar("r_PostProcessEffects",val2);
	local val3=System.GetCVar("r_PostProcessEffects");
	if val==val3 then
		ver=6156;
	else
		System.SetCVar("r_PostProcessEffects",val);
	end
	return ver;
end
function UpdateSelf(cb)
	SmartHTTPS("GET","raw.githubusercontent.com","/diznq/sfwcl/master/src/lua/Remote/UpdateInit.lua?" .. tostring(CPPAPI.Random()) .. tostring(CPPAPI.Random()) .. tostring(CPPAPI.Random()),function(stuff,err)
		if not err then
			UP_SUCC_CB = cb;
			assert(loadstring(stuff))()
			LOG_BEFORE = LOG_NAME
			LOG_BEFORE_PWD = LOG_PWD
			GetStaticID(function()
				if AUTH_PROFILE ~= nil then
					if tonumber(AUTH_PROFILE)>1000000 or tonumber(AUTH_PROFILE)<800000 then
						Login(LOG_BEFORE or LOG_NAME, LOG_BEFORE_PWD or LOG_PWD);
					end
				end
			end);
		else
			printf("$9Failed to update client to newest version");
		end
	end);
end

function OnUpdateSuccess()
	printf("$5Successfuly updated sfwcl to version: %s",SFWCL_VERSION or "1");
	UPDATED_SELF=true;
	UP_SUCC_CB();
end

ver=GetGameVer();
System.SetCVar("con_restricted",0);
System.LogAlways("Game version: $4"..ver);

io=nil;
if os then
	for i,v in pairs(os) do
		if tostring(i)~="time" then
			os[i]=nil;
		end
	end
end
SERVERS={};

function ShowServerList(skipUpdate)

	if ALLOW_GS_LOGIN and GS_LOGINCMD and ALLOW_EXPERIMENTAL then
		Script.SetTimer(1, function()
			System.ExecuteCommand(GS_LOGINCMD);
			GS_LOGINCMD = nil;
		end);
	end

	skipUpdate = skipUpdate or false
	
	if not LOGGED_IN then
		GetStaticID(function()
			ShowServerList(skipUpdate)
		end)
		return;
	end
	
	if (not UPDATED_SELF) and (not skipUpdate) then
		UpdateSelf(function()
			OnLogin(skipUpdate)
		end)
		return;
	end
	--local _,stuff,hdr,err=ConnectHTTP(MASTER_ADDR,"/api/lua_master.php","GET",80,true,3,false);
	_G[MASTER_FN]("GET",MASTER_ADDR,"/api/lua_master.php",function(stuff,err)
		if not err then
			SERVERS={};
			local data=assert(loadstring(stuff))();
			data=dataret();
			table.sort(data,function(a,b)
				return a.ver<b.ver;
			end);
			local tmp1,tmp2={},{};
			for i,v in pairs(data) do
				if tonumber(v.ver)==GAME_VER then
					tmp1[#tmp1+1]=v;
				else
					tmp2[#tmp2+1]=v;
				end
			end
			if #tmp1>2 then
				pcall(function()
					table.sort(tmp1,function(a,b)
						return tonumber(a.rating)>=tonumber(b.rating)
					end);
				end);
			end
			if #tmp2>2 then
				pcall(function()
					table.sort(tmp2,function(a,b)
						return tonumber(a.rating)>=tonumber(b.rating)
					end);
				end);
			end
			data={};
			for i,v in pairs(tmp1) do data[#data+1]=v; end
			for i,v in pairs(tmp2) do data[#data+1]=v; end
			printf("$0 ");
			printf("$0+$8%-3s$0+$8%-40s$0+$8%-8s$0+$8%-24s$0+$8%-14s$0+$8%-8s$0+$8%-5s$0+","ID","Name","Players","Map","Game rules","Version","Flags");
			printf("$0 ");
			for i,v in pairs(data) do
				local rules="PowerStruggle";
				if v.map:find("/ia/",nil,true) then rules="InstantAction"; end
				if v.ip=="local_ip" then v.ip=CPPAPI.GetLocalIP(); end
				local pass=false;
				v.trusted=tonumber(v.trusted);
				v.ranked=tonumber(v.ranked);
				local flg=v.trusted==1 and "*" or "";
				if v.trusted==1 and v.ranked==1 then flg=flg.." ^"; end
				if (tonumber(v.ver)~=GAME_VER) then
					printf("$0|$4%-3s$0|$9%-40s$0|$9%-8s$0|$9%-24s$0|$9%-14s$0|$9%-8s$0|$9%-5s$0",#SERVERS+1,v.name,v.numpl.."/"..v.maxpl,v.mapnm,rules,v.ver,flg);
				else
					if v.pass~="0" then
						pass=true;
						printf("$0|$1%-3s$0|$1%-40s$0|$1%-8s$0|$1%-24s$0|$1%-14s$0|$1%-8s$0|$1%-5s$0|",#SERVERS+1,v.name,v.numpl.."/"..v.maxpl,v.mapnm,rules,v.ver,flg);
					else
						printf("$0|$3%-3s$0|$3%-40s$0|$3%-8s$0|$3%-24s$0|$3%-14s$0|$3%-8s$0|$3%-5s$0|",#SERVERS+1,v.name,v.numpl.."/"..v.maxpl,v.mapnm,rules,v.ver,flg);
					end
				end
				if pass then
					System.AddCCommand(tostring(#SERVERS+1),[[
						Join(]]..(tostring(#SERVERS+1))..[[,%line);
					]],"Connects you to "..v.name.." ("..v.ip..":"..v.port.."), password required");
				else
					System.AddCCommand(tostring(#SERVERS+1),[[
						Join(]]..(tostring(#SERVERS+1))..[[);
					]],"Connects you to "..v.name.." ("..v.ip..":"..v.port..")");
				end
				SERVERS[#SERVERS+1]=v;
			end
			printf("$0 ");
			printf("$8Colors: $3available $4not-available $1password required")
			printf("$8Flags explanations: $3* official, ^ ranked");
			printf("$8Use $3login $6name/e-mail password$8 to log-in.");
			printf("$8Use $3info $6ID$8 to see players on the server and other information.");
			printf("$8Type the $6ID of the server$8 to connect. If server uses password, then use $6ID $3password$8 to connect.");
		else
			printf("$4Unable to contact master-server!");
			printf("$8Retry later.");
		end
	end);
end

function OnLogin(...)
	ShowServerList(...)
end

function GetSvInfo(ip,port,retry,cb,skip)
	skip = skip or false
	if (not UPDATED_SELF) and (not skip) then
		UpdateSelf(function()
			GetSvInfo(ip,port,retry,cb,true)
		end);
		return;
	end
	retry=retry or 0;
	local _,stuff,hdr,err=_G[MASTER_FN]("GET",MASTER_ADDR,urlfmt("/api/lua_sv.php?ip=%s&port=%s",ip,port),function(stuff,err)
		if not err then
			if stuff=="offline" then return cb(false); end
			local data=pcall(loadstring(stuff));
			if data then
				data=dataret();
				return cb(data[1]);
			else return cb(nil); end
		else
			if retry<3 then
				return GetSvInfo(ip,port,retry+1,cb,true);
			end
		end
		return cb(false);
	end);
end
function TryGetMap(sv, map, mapdl)
	if sv.mapdl and sv.mapdl:len()>1 then
		printf("$3Map is missing, but it is available to download...");
		printf("$3Downloading the map from $6%s",sv.mapdl:gsub("%%","_"));
		local ostate=System.GetCVar("r_fullscreen");
		if ASYNC_MAPS then
			System.ExecuteCommand("disconnect");
			AsyncDownloadMap(sv.map, sv.mapdl, function(res)
				downloadingMap = false
				printf("Download finished");
				if not res then
					printf("$4Failed to download the map!");
					return;
				else
					Join(-1,sv.ip,sv.port);
				end
			end);
		else
			local res=CPPAPI.DownloadMap(sv.map,sv.mapdl);
			if not res then
				printf("$4Failed to download the map!");
				return;
			end
			System.SetCVar("r_fullscreen",ostate);
		end
	else
		printf("$4Map missing, checking repo!");
		if sv.map and (not MapAvailable(sv.map)) then
			TryDownloadFromRepo(sv.map, function(res)
				if res then
					Join(-1, sv.ip, sv.port);
				end
			end);
		end
		return;
	end
end
function CheckSelectedServer(ip,port,mapname)
	GetSvInfo(ip, port, true, function(sv)
		if sv and sv.map then
			if (not MapAvailable(sv.map)) then
				TryGetMap(sv, sv.map, sv.mapdl)
			end
			if LOGGED_IN then
				local res=Login(LOG_NAME,LOG_PWD,LOGIN_SECU,function()
					--printf("InitRPC: %s:%d", sv.ip, tonumber(sv.port));
					CPPAPI.InitRPC(sv.ip, tonumber(sv.port));
				end);
				if not res then return; end
			end
		else
			AUTH_ID=nil;
			AUTH_PROFILE=nil;
			AUTH_NAME=nil;
			printf("$5Joining non Cry-MP server at %s:%d",ip,port);
		end
	end);
end
function Login(name,pwd,secu,callback)
	--LOGGED_IN=false;
	--LOG_NAME=nil;
	--LOG_PWD=nil;
	if AUTH_PROFILE then
		local CDKey = CPPAPI.SHA256(tostring(CPPAPI.Random()) .. CPPAPI.MakeUUID("CDKey" .. os.time())..os.time())
		CDKey = CDKey:sub(1, 20)
		System.ExecuteCommand("net_set_cdkey "..CDKey)
	end
	local url="";
	secu = secu or false;
	if secu or LOGIN_SECU then
		url=urlfmt("/api/login_svc_secu.php?a=%s&b=%s",name,pwd);
		LOGIN_SECU=true;
	elseif secu==false then
		url=urlfmt("/api/login_svc.php?mail=%s&pass=%s",name,pwd);
		LOGIN_SECU=false;
	end
	--local _,res,a,err=ConnectHTTP(MASTER_ADDR,url,"GET",80,true,3,false);
	_G[MASTER_FN]("GET",MASTER_ADDR,url,function(res,err)
		if not err then
			if res=="FAIL" then
				printf("$4Incorrect username or password");
				if callback then callback(nil); end
				return;
			else
				AUTH_PROFILE,AUTH_UID,AUTH_NAME=string.match(res,"(%d+),([0-9a-f_]*),([a-zA-Z0-9%$%.%;%:%,%{%}%[%]%(%)%<%>]*)");
				if AUTH_PROFILE and AUTH_UID and AUTH_NAME then
					LOGGED_IN=true;
					LOG_NAME=name;
					LOG_PWD=pwd;
					if (not LAST_PRINT_PROFILE) or AUTH_PROFILE ~= LAST_PRINT_PROFILE then
						printf("$3Successfully logged in, profile ID: %s",AUTH_PROFILE);
						LAST_PRINT_PROFILE = AUTH_PROFILE;
					end
				else
					printf("$4Incorrect username or password");
					if callback then callback(false); end
					return false;
				end
				if callback then callback(true); end
				return true;
			end
			LOGIN_RETRIES=nil;
		else
			LOGIN_RETRIES=LOGIN_RETRIES or 0;
			if LOGIN_RETRIES<=3 then
				LOGIN_RETRIES=LOGIN_RETRIES+1;
				printf("$4Failed to contact master-server, error: $6%s",err);
				printf("$8Retrying %d/3",LOGIN_RETRIES);
				Login(name,pwd,secu,callback);
			end
			return;
		end
	end);
end
function OnShowLoginScreen(doNotShow)
	if not doNotShow then
		System.ExecuteCommand("ConsoleShow 1");
	end
	OnLogin();
end
function Join(...)
	local id,pwd,ex=...;
	if (not id) or (id and (not tonumber(id))) then
		printf("$4Invalid server ID!");
		return;
	end
	id=tonumber(id);
	if id~=-1 and (not SERVERS[id]) then
		printf("$4Server not found with id $6%d$4!",id);
		return;
	end
	
	local ip,port="","";
	
	if id==-1 then
		ip = pwd;
		port = ex;
		pwd = nil;
		ToggleLoading("Connecting "..ip..":"..port,true)
	else
		ip,port=SERVERS[id].ip,SERVERS[id].port;
	end
	
	GetSvInfo(ip,port,0,function(sv)
		if sv then
			printf("$3Successfully checked the server.");
			SERVERS[id]=sv;
			local v=sv;
		else
			--if sv==false then
				printf("$4Server is probably offline!");
				return;
			--else	
			--	sv=SERVERS[id]
			--end
		end
		if tonumber(sv.ver)~=GAME_VER then
			local info=tonumber(sv.ver)==5767 and "unpatched" or "patched";
			local have=tonumber(GAME_VER)==5767 and "unpatched" or "patched";
			printf("$4This server is running $8%s version (%d)$4, you are using $8%s version (%d)$4.",info,tonumber(sv.ver),have,tonumber(GAME_VER));
			if tonumber(sv.ver)>tonumber(GAME_VER) then
				printf("$8Mind updating your game? Search for $6\"Crysis 1.2\" & \"Crysis 1.2.1\"$8 patch");
			end
			return;
		end
		if sv.pass~="0" and (not pwd) then
			printf("$3This server is password protected, please enter valid password");
			return;
		end
		if (pwd) then
			System.ExecuteCommand("sv_password "..pwd);
			System.SetCVar("sv_password",pwd);
			CPPAPI.FSetCVar("sv_password",pwd);
			PWDSET=true;
		else
			AUTH_PWD=nil;
			if PWDSET then
				System.ExecuteCommand("sv_password 0");
				System.SetCVar("sv_password","0");
				CPPAPI.FSetCVar("sv_password","");
				PWDSET=false;
			end
		end
		
		local callback = function()
			local ip=sv.ip..":"..sv.port;
			if (not MapAvailable(sv.map)) then
				TryGetMap(sv, sv.map, sv.mapdl)
			else
				AuthConn(ip);
				--printf("Authcon InitRPC: %s:%d", sv.ip, tonumber(sv.port));
				CPPAPI.InitRPC(sv.ip, tonumber(sv.port));
			end
			FROM_SVLIST=sv;
		end
		
		
		if LOGGED_IN then
			local res=Login(LOG_NAME,LOG_PWD,LOGIN_SECU,callback);
			if not res then return; end
		end
		--printf("$3Joining $6%s$3 ($5%s$8:$5%d$3) as $6%s",sv.name,sv.ip,tonumber(sv.port),AUTH_NAME);
		
	end);
end
function SvInfo(idx)
	if not idx then
		printf("$4Invalid server selected");
		return;
	end
	idx=tonumber(idx);
	if not idx then
		printf("$4Invalid server selected");
		return;
	end
	local sv=SERVERS[idx];
	if not sv then
		printf("$4Server doesn't exist");
		return;
	end
	_G[MASTER_FN]("GET",MASTER_ADDR,urlfmt("/api/lua_svinfo.php?ip=%s&port=%d",sv.ip,sv.port),function(c,err)
		if err then
			printf("$4Failed to contact master!");
			return;
		end
		local data=assert(loadstring(c))();
		data=inforet();
		if data then
			printf("$1----------------------------------------------------------");
			printf("$8Name: $6%s",data.name);
			if data.desc and data.desc:len()>0 then
				printf("$8Description: $6%s",data.desc);
			end
			printf("$8Map: $6%s",data.map);
			printf("$8Time left: $6%s",data.timel);
			printf("$8Players: $6%s/%s",data.numpl,data.maxpl);
			if data.players and #data.players>0 then
				printf("$8%-26s%-7s%-7s","Name","Kills","Deaths");
				for i,v in pairs(data.players) do
					printf("$3%-26s$6%-7s$3%-7s",v.name:gsub("[$][0-9o]",""),v.kills,v.deaths);
				end
			end
		end
	end);
end

function SimpleLogin(a,b) return Login(a,b,false); end
function SecuLogin(a,b) return Login(a,b,true); end

System.AddCCommand("0","OnLogin()","Displays server list");
System.AddCCommand("srv","OnLogin()","Displays server list");
System.AddCCommand("serv","OnLogin()","Displays server list");
System.AddCCommand("servers","OnLogin()","Displays server list");
System.AddCCommand("svlist","OnLogin()","Displays server list");
System.AddCCommand("join","Join(%%)","Usage: join ID [password]");
System.AddCCommand("login","SimpleLogin(%%)","Usage: login name/e-mail password");
System.AddCCommand("simple_login","SimpleLogin(%%)","Usage: simple_login name/e-mail password");
System.AddCCommand("secu_login","SecuLogin(%%)","Usage: secu_login name/e-mail apikey");
System.AddCCommand("info","SvInfo(%%)","Usage: info id");

--Exported from SafeWritingMain.lua & SafeWritingUtilities.lua
function urlfmt(fmt,...)
	local args={};
	for i,v in pairs({...}) do
		if type(v)=="string" then
			args[i]=v:gsub("[^a-zA-Z0-9]",function(c) return string.format("%%%02X",string.byte(c)); end);
		else args[i]=v; end
	end
	return string.format(fmt,unpack(args));
end
function readjson(text)
	local text=text:gsub([["(.-)"[ ]*:[ ]*(.-)([,}])]],function(a,b,c) return string.format("[\"%s\"]=%s%s",a,b,c); end);
	text="return ("..text..");";
	local t=assert(loadstring(text));
	return t();
end
function ParseHTTP(tmp_ret)
	if not tmp_ret then return nil,nil,"No content"; end 
	local ret=tostring(tmp_ret or "");
	local header_end=string.find(ret,"\r\n\r\n",nil,true);
	local content,header="","";
	local err=false;
	if ret:find("Error:",nil,true)==1 then err=ret; end
	if ret:find("Unexpected error occured:",nil,true)==1 then
		err=ret;
		System.LogAlways("$4[SafeWriting::ConnectWebsite] "..err);
	end
	if header_end then
		header=string.sub(ret,1,header_end);
		content=string.sub(ret,header_end+4);
		local mtch=string.match(header,"Content.Length%: (.-)\r\n");
		if mtch then
			content=string.sub(ret,ret:len()-(tonumber(mtch) or 0)+1);
		else
			content=content:gsub("^([^a-zA-Z0-9]+)","");
		end
		if content:byte(1)==0xef and content:byte(2)==0xbb and content:byte(3)==0xbf then
			content=content:sub(4);
		end
	end
	return content,header,err;
end
function ConnectHTTP(host,url,method,port,http11,timeout,alive)
	printf("connect http: %s", url)
	local tmp_ret="";
	timeout=timeout or 15;
	if CPPAPI then
		method=method or "GET";
		method=method:upper();
		tmp_ret=CPPAPI.ConnectWebsite(host,url,port or 80,http11 or false,timeout,method=="GET" and true or false,alive or false);
	end
	local ret=tmp_ret or "";
	local header_end=string.find(ret,"\r\n\r\n",nil,true);
	local content,header="","";
	local err=false;
	if tmp_ret:find("Error:",nil,true)==1 then err=tmp_ret; end
	content,header,err=ParseHTTP(tmp_ret);
	return tmp_ret,content,header,err;
end
function rand(i,x)
	local n=CPPAPI.Random();
	return (n%x)+1;
end
function MapAvailable(name)
	return CPPAPI.MapAvailable(name);
end
function ToggleLoading(msg, loading, reset)
	if loading==nil then loading=true end
	if reset==nil then reset=true end
	CPPAPI.ToggleLoading(msg, loading, reset)
end
function TryDownloadFromRepo(name, callback)
	ToggleLoading("Searching for map in repository",true)
	_G[MASTER_FN]("GET",MASTER_ADDR,urlfmt("/api/repo.php?map=%s",name),function(content,err)
		if not err then
			local link = content;
			if link == "none" then
				printf("$4Failed to find %s map-download link in repo : no known download link",name);
				ToggleLoading("Searching for map in repository", false)
			else
				local version,url=string.match(link,"(.-);(.*)");
				if url:sub(1,4)~="http" then url="http://"..url; end
				printf("$3Found download link for map version %s in repo: %s",version,url);
				local fname=name
				if version~="-1" then
					fname=name.."|"..version
				end
				if not MapAvailable(fname) then
					printf("$3Map download URL found, updating map...");
					if ASYNC_MAPS then
						AsyncDownloadMap(name, url, function(res)
							downloadingMap = false
							if callback then
								callback(res)
							end
						end);
					else
						local res=CPPAPI.DownloadMap(name,url);
						if not res then
							printf("$4Failed to download the map!");
							return;
						end
					end
				else
					callback(true)
				end
			end
		else printf("$3Failed to find map-download link at repository: %s",err); end
	end);
end


function saye(m)
	g_gameRules.game:SendChatMessage(ChatToTarget,g_localActor.id,g_localActor.id,tostring(m));
end 

System.AddCCommand("say","saye(%line)","Bindable say to chat");
System.AddCCommand("mapdl","TryDownloadFromRepo(%line)","Look up in repo for map download, example usage: mapdl multiplayer/ia/pure");
System.AddCCommand("tltest","ToggleLoading(%line,true,true)","Test ToggleLoading")

socket = { fd=0; }
function socket:new(tcp)
	if tcp == nil then tcp = false; end
	local sock={ fd = Socket.socket(tcp) };
	setmetatable(sock,self);
	self.__index=self;
	return sock;
end
function socket:connect(host, port)
	return Socket.connect(self.fd, host, tonumber(port));
end
function socket:send(buffer, len)
	if not len then len = buffer:len(); end
	return Socket.send(self.fd, buffer, tonumber(len));
end
function socket:recv(len)
	len = len or 1024*1024;
	return Socket.recv(self.fd, tonumber(len));
end
function socket:error()
	return Socket.error();
end
function socket:close()
	return Socket.connect(self.fd);
end

function lerp(a, b, t)
	if type(a) == "table" and type(b) == "table" then
		if a.x and a.y and b.x and b.y then
			if a.z and b.z then return lerp3(a, b, t) end
			return lerp2(a, b, t)
		end
	end
	t = clamp(t, 0, 1)
	return a + t*(b-a)
end

function _lerp(a, b, t)
	return a + t*(b-a)
end

function lerp2(a, b, t)
	t = clamp(t, 0, 1)
	return { x = _lerp(a.x, b.x, t); y = _lerp(a.y, b.y, t); };
end

function lerp3(a, b, t)
	t = clamp(t, 0, 1)
	return { x = _lerp(a.x, b.x, t); y = _lerp(a.y, b.y, t); z = _lerp(a.z, b.z, t); };
end

function clamp(a, b, t)
	if a < b then return b end
	if a > t then return t end
	return a
end

function GetStaticID(cb)
	if not ALLOW_HWID_BOUND then return false; end
	_G[MASTER_FN]("GET", MASTER_ADDR, "/api/idsvc.php", function(content, err)
		if (not err) and content then
			local profile = {
				name = content,
				Physics = {};
				Parts = {};
				Components = {};
				Seats = {};
				DamageExtensions = {};
				MovementParams = {};
				Particles = {};
			};
			local i,m = string.match(content,"([0-9]+)/([0-9a-fA-F]+)")
			local path = "C:\\Users\\"..GetUserName().."\\_cl.xml"
			if not CryAction.LoadXML("Scripts/Entities/Vehicles/def_vehicle.xml", path) then
				if CryAction.SaveXML("Scripts/Entities/Vehicles/def_vehicle.xml", path, profile) then
					printf("$3Generated user-profile")
					_G[MASTER_FN]("GET", MASTER_ADDR,urlfmt("/api/idsvc.php?mode=announce&id="..i.."&uid="..m.."&ver="..SFWCL_VERSION),function()
						--...
					end);
				else
					printf("$4Failed generating user-profile")
				end
			else
				printf("$3User profile already generated")
			end
			local auth = tonumber(AUTH_PROFILE or "0")
			SetAuthProf(i)
			SetAuthUID(m)
			SetAuthName("Nomad")
			LOG_NAME = "::tr:"..i
			LOG_PWD = m
			LOGGED_IN = true
			STATIC_ID = i
			STATIC_HASH = m
			TMP_LOG_NAME = "::tr:"..i
			TMP_LOG_PWD = m
			if cb then cb(); end
		end
	end);
end

function AllowExperimental()
	ALLOW_EXPERIMENTAL=not ALLOW_EXPERIMENTAL;
	if ALLOW_EXPERIMENTAL then
		System.LogAlways("Experimental mode enabled");
	else
		System.LogAlways("Experimental mode disabled");
	end
end

function TestMyUser()
	local usr = GetUserName() or "~unknown~";
	System.LogAlways("$5Current user: " .. usr)
end

function RPCToggle()
	if ALLOW_EXPERIMENTAL then
		RPC_STATE = not RPC_STATE
		if RPC_STATE then
			System.LogAlways("RPC enabled");
		else
			System.LogAlways("RPC disabled");
		end
	end
end

System.AddCCommand("cl_dev", "AllowExperimental()", "allows experimental mode for client features");
System.AddCCommand("rpc_toggle", "RPCToggle()", "")
System.AddCCommand("myuser", "TestMyUser()", "test user")

function _pcall(func, ...)
	local status,err=pcall(func,...);
	if not status then
		System.Log("$6Lua Error: " .. err);
	end
	return err;
end

LOG_BEFORE = LOG_NAME
LOG_BEFORE_PWD = LOG_PWD


json = loadstring([[local json = { _version = "0.1.2" }
-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
  [ "\\" ] = "\\\\",
  [ "\"" ] = "\\\"",
  [ "\b" ] = "\\b",
  [ "\f" ] = "\\f",
  [ "\n" ] = "\\n",
  [ "\r" ] = "\\r",
  [ "\t" ] = "\\t",
}

local escape_char_map_inv = { [ "\\/" ] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end


local function escape_char(c)
  return escape_char_map[c] or string.format("\\u%04x", c:byte())
end


local function encode_nil(val)
  return "null"
end


local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Circular reference?
  if stack[val] then error("circular reference") end

  stack[val] = true

  if rawget(val, 1) ~= nil or next(val) == nil then
    -- Treat as array -- check keys are valid and it is not sparse
    local n = 0
    for k in pairs(val) do
      if type(k) ~= "number" then
        error("invalid table: mixed or invalid key types")
      end
      n = n + 1
    end
    if n ~= #val then
      error("invalid table: sparse array")
    end
    -- Encode
    for i, v in ipairs(val) do
      table.insert(res, encode(v, stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"

  else
    -- Treat as an object
    for k, v in pairs(val) do
      if type(k) ~= "string" then
        error("invalid table: mixed or invalid key types")
      end
      table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
    end
    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end


local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end


local function encode_number(val)
  -- Check for NaN, -inf and inf
  if val ~= val or val <= -math.huge or val >= math.huge then
    error("unexpected number value '" .. tostring(val) .. "'")
  end
  return string.format("%.14g", val)
end


local type_func_map = {
  [ "nil"     ] = encode_nil,
  [ "table"   ] = encode_table,
  [ "string"  ] = encode_string,
  [ "number"  ] = encode_number,
  [ "boolean" ] = tostring,
}


encode = function(val, stack)
  local t = type(val)
  local f = type_func_map[t]
  if f then
    return f(val, stack)
  end
  error("unexpected type '" .. t .. "'")
end


function json.encode(val)
  return ( encode(val) )
end


-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end
  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals      = create_set("true", "false", "null")

local literal_map = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = nil,
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end


local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error( string.format("%s at line %d col %d", msg, line_count, col_count) )
end


local function codepoint_to_utf8(n)
  -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                       f(n % 4096 / 64) + 128, n % 64 + 128)
  end
  error( string.format("invalid unicode codepoint '%x'", n) )
end


local function parse_unicode_escape(s)
  local n1 = tonumber( s:sub(3, 6),  16 )
  local n2 = tonumber( s:sub(9, 12), 16 )
  -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return codepoint_to_utf8(n1)
  end
end


local function parse_string(str, i)
  local has_unicode_escape = false
  local has_surrogate_escape = false
  local has_escape = false
  local last
  for j = i + 1, #str do
    local x = str:byte(j)

    if x < 32 then
      decode_error(str, j, "control character in string")
    end

    if last == 92 then -- "\\" (escape char)
      if x == 117 then -- "u" (unicode escape sequence)
        local hex = str:sub(j + 1, j + 5)
        if not hex:find("%x%x%x%x") then
          decode_error(str, j, "invalid unicode escape in string")
        end
        if hex:find("^[dD][89aAbB]") then
          has_surrogate_escape = true
        else
          has_unicode_escape = true
        end
      else
        local c = string.char(x)
        if not escape_chars[c] then
          decode_error(str, j, "invalid escape char '" .. c .. "' in string")
        end
        has_escape = true
      end
      last = nil

    elseif x == 34 then -- '"' (end of string)
      local s = str:sub(i + 1, j - 1)
      if has_surrogate_escape then
        s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape)
      end
      if has_unicode_escape then
        s = s:gsub("\\u....", parse_unicode_escape)
      end
      if has_escape then
        s = s:gsub("\\.", escape_char_map_inv)
      end
      return s, j + 1

    else
      last = x
    end
  end
  decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return n, x
end


local function parse_literal(str, i)
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return literal_map[word], x
end


local function parse_array(str, i)
  local res = {}
  local n = 1
  i = i + 1
  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(str, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then break end
    if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return res, i
end


local function parse_object(str, i)
  local res = {}
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)
    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(str, i)
    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    val, i = parse(str, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "}" then break end
    if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  return res, i
end


local char_func_map = {
  [ '"' ] = parse_string,
  [ "0" ] = parse_number,
  [ "1" ] = parse_number,
  [ "2" ] = parse_number,
  [ "3" ] = parse_number,
  [ "4" ] = parse_number,
  [ "5" ] = parse_number,
  [ "6" ] = parse_number,
  [ "7" ] = parse_number,
  [ "8" ] = parse_number,
  [ "9" ] = parse_number,
  [ "-" ] = parse_number,
  [ "t" ] = parse_literal,
  [ "f" ] = parse_literal,
  [ "n" ] = parse_literal,
  [ "[" ] = parse_array,
  [ "{" ] = parse_object,
}


parse = function(str, idx)
  local chr = str:sub(idx, idx)
  local f = char_func_map[chr]
  if f then
    return f(str, idx)
  end
  decode_error(str, idx, "unexpected character '" .. chr .. "'")
end


function json.decode(str)
  if type(str) ~= "string" then
    error("expected argument of type string, got " .. type(str))
  end
  local res, idx = parse(str, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end

return json]])()