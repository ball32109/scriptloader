
local _MODULES = {}

function search_module(name)
	local path = {}
	local start = 1
	local over = nil 
	while true do
		local over = name:find('%.')
		if over == nil then
			table.insert(path,name)
			break
		end
		local sub = name:sub(start,over)
		table.insert(path,sub)
		name = name:sub(over+1,name:len())
	end

	local submod
	local instance
	for i = 1,#path do 
		if i == #path then
			if submod == nil then
				submod = _MODULES
			end
			instance = submod[path[i]]
			break
		end

		if _MODULES[path[i]] == nil then
			_MODULES[path[i]] = {}
		else
			submod = _MODULES[path[i]]
		end
	end
	return submod,path[#path],instance
end

function _LOAD(name,reload,...)
	local module,modulename,omod = search_module(name)
	local filename = modulename..".lua"

	if not omod then
		local nmod = {}
		setmetatable(nmod,{__index = _G})
		local func,err = loadfile(filename,"bt",nmod)
		assert(func ~= nil,string.format("error load module:%s",filename))
		func(...)

		module[modulename] = nmod
		return nmod
	else

		if reload == false then
			return omod
		else
			--把原来模块的非local非function类型的变量保存起来
			local otable = {}
			for k,v in pairs(omod) do
				if type(v) ~= "function" then
					otable[k] = v
				end
			end

			local ofunc = {}
			for k,v in pairs(omod) do
				if type(v) == "function" then
					local index = 1
					local upvalue = {}
					while true do
						local name,value = debug.getupvalue(v,index)
						if name == nil then
							break
						end
						if name ~= "_ENV" then
							upvalue[name] = index
						end
						index = index + 1
					end
					ofunc[k] = {func = v,upvalue = upvalue}
				end
			end

			local nmod  = {}
			setmetatable(nmod,{__index = _G})

			local func,err = loadfile(filename,"bt",nmod)
			assert(func ~= nil,string.format("error reload module:%s",filename))
			func(...)

			--先把原来模块的中非local table转移到新模块中
			for k, v in pairs(otable) do
            	local mt = getmetatable(nmod[k])
            	if mt then setmetatable(v, mt) end
           	 	nmod[k] = v
            end

            for k,v in pairs(ofunc) do
            	local nfunc = nmod[v]
            	if nfunc ~= nil and type(nfunc) == "function" then
            		local index = 1
					while true do
						local name,value = debug.getupvalue(nfunc,index)
						if name == nil then
							break
						end
						local upvalue = ofunc[k].upvalue
						if  name ~= "_ENV" and upvalue[name] ~= nil then
							debug.upvaluejoin(nfunc,index,ofunc[k].func,upvalue[name])
						end
						index = index + 1
					end
            	end
            end
		end
	end
end
