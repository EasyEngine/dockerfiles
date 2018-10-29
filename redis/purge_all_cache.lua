local k =  0
for i, name in ipairs(redis.call('KEYS', ARGV[1]))
do
  redis.call('DEL', name)
  k = k+1
end
return k