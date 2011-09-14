local ffi = require('ffi')
local poll = require('poll')
local socket = require('socket')
local bit = require('bit')
local fcntl = require('fcntl')

local table = table
local ipairs = ipairs
local assert = assert
local print = print
local tostring = tostring
local setmetatable = setmetatable

socketserver = {}
local tcpserver = socketserver
setfenv(1, socketserver)



return socketserver
