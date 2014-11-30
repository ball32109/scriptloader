
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

function index(self,key)
	local module,modulename,omod = search_module(self.__module)
	assert(omod ~= nil)
	return omod.instance[key]
end

function _LOAD(name,reload,...)
	local module,modulename,omod = search_module(name)
	local filename = modulename..".lua"

	if not omod then
		local nmod = {}
		setmetatable(nmod,{__index = _G})
		local func,err = loadfile(filename,"bt",nmod)
		assert(func ~= nil,string.format("error load module:%s",filename))
		module[modulename] = {env = nmod,instance = instance}
		return setmetatable({__module = name},{__index = index})
	else

		if reload == false then
			return setmetatable({__module = name},{__index = index})
		else
			--把原来模块的非function类型非local的变量保存起来
			local otable = {}
			for k,v in pairs(omod.instance) do
				if type(v) ~= "function" then
					otable[k] = v
				end
			end
			-- for k,v in pairs(omod) do print("@",k,v) end
			--把原来模块的function类型引用到的upvalue保存起来
			local ofunc = {}
			for k,v in pairs(omod.instance) do
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
			local instance = func(...)

			module[modulename] = {env = nmod,instance = instance}

			--把原来模块的中非local变量转移到新模块中
			for k, v in pairs(otable) do
            	local mt = getmetatable(nmod[k])
            	if mt then setmetatable(v, mt) end
           	 	nmod[k] = v
            end
            --把来的函数引用到的upvalue转移到新模块的同名函数的upvalue中
            for k,v in pairs(ofunc) do
            	local nfunc = instance[k]
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
	return setmetatable({__module = name},{__index = index})
end
