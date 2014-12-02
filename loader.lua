local _MODULES = {}

local function metaindex(self,key)
	local module = _MODULES[self.__module]
	assert(module ~= nil)
	return module.instance[key]
end

local function search_path(name)
	local path = package.path
	local subpaths = {}
	local start = 1
	while true do
		local over = path:find(";")
		if over == nil then
			break
		end
		local n = name:gsub("%.","/")
		local subpath = path:sub(start,over-1):gsub("?",n)
		table.insert(subpaths,subpath)
		path = path:sub(over+1,path:len())
	end
	return subpaths
end

local function tryload(file,paths,index)
	local module = {}
	setmetatable(module,{__index = _G})

	local pathnname
	if index == nil then
		for i = 1,#paths do
			local path = paths[i]
			local func,err = loadfile(path,"bt",module)
			if func ~= nil then
				local instance = func()
				_MODULES[path] = {env = module,instance = instance,path = path}
				pathnname = path
				break
			end
		end
	else
		local path = paths[index]
		local func,err = loadfile(path,"bt",module)
		if func ~= nil then
			local instance = func()
			_MODULES[path] = {env = module,instance = instance,path = path}
			pathnname = path
		end
	end

	if not pathnname then
		error(string.format("error load:%s",file))
	end

	return setmetatable({__module = pathnname},{__index = metaindex})
end

function loadscript(file,...)
	local paths = search_path(file)

	local omod
	local index
	for i = 1,#paths do 
		if _MODULES[paths[i]] ~= nil then
			omod = _MODULES[paths[i]]
			index = i
			break
		end
	end

	if not omod then
		return tryload(file,paths)
	else
		return setmetatable({__module = omod.path},{__index = metaindex})
	end
end

--[[

{
	func:函数addr
	upvalue:函数的upvalue = {
		index:upvalue的索引
		func:如果upvalue为函数类型时此字段为函数addr
		upvalue:上面func的upvalue = {
			index:
			func:
			upvalue:
		}
	}

}

]]
local function collect_uv(func)
	local index = 1
	local upvalue = {}
	while true do
		local name,value = debug.getupvalue(func,index)
		if name == nil then
			break
		end

		if name ~= "_ENV" then
			if type(value) == "function" then
				local uv = collect_uv(value)
				upvalue[name] = {index = index,func = uv.func,upvalue = uv.upvalue}
			else
				upvalue[name] = {index = index}
			end
		end
		index = index + 1
	end
	return {func = func,upvalue = upvalue}
end

local function join_uv(nfunc,ofunc,upvalue)
	local index = 1
	while true do
		local name,value = debug.getupvalue(nfunc,index)
		if name == nil then
			break
		end
		if name ~= "_ENV" then
			if upvalue ~= nil then
				if type(value) == "function" then
					join_uv(value,upvalue[name].func,upvalue[name].upvalue)
				else
					if upvalue[name] ~= nil then
						debug.upvaluejoin(nfunc,index,ofunc,upvalue[name].index)
					end
				end
			end
		end
		index = index + 1
	end
end

function reloadscript(name,...)
	local paths = search_path(name)

	local omod
	local index
	for i = 1,#paths do 
		if _MODULES[paths[i]] ~= nil then
			omod = _MODULES[paths[i]]
			index = i
			break
		end
	end

	assert(omod ~= nil)

	local oetable = {}
	local oefunc = {}
	for k,v in pairs(omod.env) do
		if type(v) == "function" then
			oefunc[k] = collect_uv(v)
		else
			oetable[k] = v
		end
	end

	local oitable = {}
	local oifunc = {}
	for k,v in pairs(omod.instance) do
		if type(v) == "function" then
			oifunc[k] = collect_uv(v)
		else
			oitable[k] = v
		end
	end

	local nmod  = {}
	setmetatable(nmod,{__index = _G})

	local func,err = loadfile(omod.path,"bt",nmod)
	assert(func ~= nil,string.format("error reload module:%s",filename))
	local instance = func(...)

	_MODULES[omod.path] = {env = nmod,instance = instance,path = omod.path}


	for k, v in pairs(oetable) do
		if nmod[k] ~= nil then
	    	local mt = getmetatable(nmod[k])
	    	if mt then setmetatable(v, mt) end
	   	 	nmod[k] = v
	   	 end
    end

    for k, v in pairs(oitable) do
		if instance[k] ~= nil then
	    	local mt = getmetatable(instance[k])
	    	if mt then setmetatable(v, mt) end
	   	 	instance[k] = v
	   	 end
    end


    for k,v in pairs(oefunc) do
    	local nfunc = nmod[k]
    	if nfunc ~= nil and type(nfunc) == "function" then
    		local index = 1
			while true do
				local name,value = debug.getupvalue(nfunc,index)
				if name == nil then
					break
				end

				if name ~= "_ENV" then
					local upvalue = oefunc[k].upvalue
					if upvalue ~= nil then
						if type(value) == "function" then
							join_uv(value,upvalue[name].func,upvalue[name].upvalue)
						else
							if upvalue[name] ~= nil then
								debug.upvaluejoin(nfunc,index,oefunc[k].func,upvalue[name].index)
							end
						end
					end
				end
	
				index = index + 1
			end
    	end
    end

    for k,v in pairs(oifunc) do
    	local nfunc = instance[k]
    	if nfunc ~= nil and type(nfunc) == "function" then
    		local index = 1
			while true do
				local name,value = debug.getupvalue(nfunc,index)
				if name == nil then
					break
				end
				if name ~= "_ENV" then

					local upvalue = oifunc[k].upvalue
					if upvalue ~= nil then
						if type(value) == "function" then
							join_uv(value,upvalue[name].func,upvalue[name].upvalue)
						else
							if value ~= instance then
								if upvalue[name] ~= nil then
									debug.upvaluejoin(nfunc,index,oifunc[k].func,upvalue[name].index)
								end
							end
						end
					end
				end
				index = index + 1
			end
    	end
    end

    return setmetatable({__module = omod.path},{__index = metaindex}) 
end
