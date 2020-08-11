--Update v2
MASTER_ADDR="crymp.net"
MASTER_FN="SmartHTTPS"
CDN_ADDR="api.crymp.net"
CDN_FN="SmartHTTPS"
DECENTRALIZED = true

function DoUpdate()
	_G[CDN_FN]("GET", "raw.githubusercontent.com", "/diznq/sfwcl/master/src/lua/Remote/RPC.lua?"..tostring(CPPAPI.Random()) .. tostring(CPPAPI.Random()) .. tostring(CPPAPI.Random()), function(stuff, err)
		if not err then
			assert(loadstring(stuff))()
		else printf("$9Failed to update client to final version"); end
	end);
end

DoUpdate()

System.AddCCommand("cl_update", "DoUpdate()", "auto update client")