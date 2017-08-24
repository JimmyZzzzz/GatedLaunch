local redis = require "resty.redis"
local ck = require "resty.cookie"
local cjson = require "cjson"  
local busid = nil

local cookie, err = ck:new()
if not cookie then
        ngx.log(ngx.ERR,err)
        return ngx.exec("@white")
end


--通过模块里区分bus_id 参数
local uri = ngx.var.uri
local seachkey = nil
local modelname, err = ngx.re.match(uri, "(?<model>\\w+)/+(.*)?")

if not modelname then
  ngx.log(ngx.ERR,'not match model')
  return ngx.exec("@white") 
end

--ngx.log(ngx.ERR, 'MATCH MODEL ', modelname['model'])

if modelname['model'] then

        if modelname['model'] == 'Coach' then
           seachkey = 'c_bus_id'
        elseif modelname['model'] == 'MembershipV2' then
           seachkey = 'ms_bus_id'
        end
        --查询post提交过来数据
        if seachkey then
           ngx.req.read_body()
           local postargs, err = ngx.req.get_post_args()
                if postargs then
                        for key, val in pairs(postargs) do
                            if seachkey == key then

                                --获取本地缓存
                                local cache = ngx.shared.busstr
                                local value, flags = cache:get(val)

                                if value then
                                        ngx.log(ngx.ERR, 'Find cache ', value)
                                        busid = value

                                else


                                  local resp =  ngx.location.capture('/authdecode',{ method = ngx.HTTP_GET, args = {str = val}})

                                      if (resp.status == 200) then
                                           local unjson = cjson.decode(resp.body) 
                                           if unjson['bus_id'] then
                                              busid = unjson['bus_id']
                                              cache:set(val,busid)
                                              ngx.log(ngx.ERR, 'Find authdecode ', busid)
                                           end
                                      end
                                end
                            end
                        end
                end
        end   
end

--ngx.log(ngx.ERR, 'Trace Model Seach Bus_id ', busid)

local red = redis:new()

red:set_timeout(1000)

local ok, err = red:connect('*',6379)
      if not ok then
         ngx.log(ngx.ERR, 'failed to connection redis',err)
         return ngx.exec("@white")
      end


local ok, err = red:auth("*")
      if not ok then
         ngx.log(ngx.ERR, 'Auth not pass')
         return ngx.exec("@white")
end

--模块是 Admin/Web
if modelname['model'] == 'Admin' or modelname['model'] == 'Web' then
--通过cookie获取busid
        --ngx.log(ngx.ERR, 'Enter Admin/Web')
        local PHPSESSID = cookie:get("PHPSESSID")
        --ngx.log(ngx.ERR, 'PHPSESSID = ',PHPSESSID)
        if PHPSESSID and not busid then

                local php_sess = "PHPREDIS_SESSION:"..PHPSESSID

                local res, err = red:get(php_sess)
                --ngx.log(ngx.ERR, 'M Json Source: ', res)
                if res and res ~= '' and res ~= ngx.null then

                        local m, err = ngx.re.match(res, "bus_id|s:\\d+:\"(?<busid>\\d+)\"")
                        --ngx.log(ngx.ERR, 'M Json: ',cjson.encode(m))
                        if m then
                                busid = m['busid']
                         end
                end

        end
end

--未获取到bus_id
if not busid then
        ngx.log(ngx.ERR, 'Proxy Gray white 1')
        return ngx.exec("@white")
end


--按场馆灰度配置进行分发请求 获取gray:config:bus_id  hget

local graystr = "gray:config:"..busid
local grayconf, err = red:hget(graystr,modelname['model'])
if grayconf == 'true' then
   ngx.log(ngx.ERR, 'Proxy Gray gray 0')
   return ngx.exec("@gray")
else
   ngx.log(ngx.ERR, 'Proxy Gray white 2')
   return ngx.exec("@white")
end