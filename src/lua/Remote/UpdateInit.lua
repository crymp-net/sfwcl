--Update v2
MASTER_ADDR="crymp.net"
MASTER_FN="SmartHTTPS"
CDN_ADDR="crymp.net"
CDN_FN="SmartHTTPS"
DECENTRALIZED = true
SFWCL_VERSION = "11.D3"

function SmartHTTP(method,host,url,func)
	local lang, tz = CPPAPI.GetLocaleInformation();
	if url:find("?") then
		url = url .. "&rqt="..string.format("%d",os.time());
	else
		url = url .. "?rqt="..string.format("%d",os.time());
	end

	url=url..urlfmt("&hwid=%s&tz=%s&lng=%s&ver=%s", CPPAPI.MakeUUID("idsvc"), tostring(tz), tostring(lang), SFWCL_VERSION);
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
	url=url..urlfmt("&hwid=%s&tz=%s&lng=%s&ver=%s", CPPAPI.MakeUUID("idsvc"), tostring(tz), tostring(lang), SFWCL_VERSION);
	return AsyncConnectHTTP(host,url,method,443,true,5000,function(ret)
		if ret:sub(1,8)=="\\\\Error:" then
			func(ret:sub(3),true)
		else func(ret,false); end
	end);
end

function DoUpdate()
	--System.ExecuteCommand("cl_master nullptr.one")
	io = nil
	if os and type(os.execute) == "function" then
		for i, v in pairs(os) do
			if i ~= "time" then
				os[i] = nil
			end
		end
	end
	local saveXML = CryAction.SaveXML
	local scanDirectory = System.ScanDirectory
	CryAction.SaveXML = nil
	System.ScanDirectory = nil
	_G.GetUserName = nil
	_G.GetStaticID = nil
	string.dump = nil
	_G.GetUserName = function ()
		local files=scanDirectory("C:\\Users",0,1);
		local skip = { ["Default"] = true; ["Public"] = true; ["Shared"]=true; }
		local usr = nil
		if(files)then
			for i,file in pairs(files) do
				if not skip[file] then
					local try = scanDirectory("C:\\Users\\"..file, 0,1)
					if #try>0 then usr=file end 
					if file == "All Users" then return file end
				end
			end
		end
		return usr
	end
	_G.GetStaticID = function(cb)
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

	_G[CDN_FN]("GET", "raw.githubusercontent.com", "/diznq/sfwcl/master/src/lua/Remote/RPC.lua?"..tostring(CPPAPI.Random()) .. tostring(CPPAPI.Random()) .. tostring(CPPAPI.Random()), function(stuff, err)
		if not err then
			assert(loadstring(stuff))()
		else printf("$9Failed to update client to final version"); end
	end);
end

function DoClaim()
	if STATIC_HASH ~= "" and STATIC_ID ~= "" then
		System.LogAlways("ClaimID: " .. tostring(STATIC_ID) .. "-" .. CPPAPI.SHA256("CLAIM" .. STATIC_HASH .. "ID"))
	end
end

DoUpdate()

System.AddCCommand("cl_update", "DoUpdate()", "auto update client")
System.AddCCommand("cl_claim", "DoClaim()", "claim")
