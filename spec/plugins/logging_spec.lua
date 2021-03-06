local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local yaml = require "yaml"
local IO = require "kong.tools.io"
local uuid = require "uuid"
local stringy = require "stringy"

-- This is important to seed the UUID generator
uuid.seed()

local STUB_GET_URL = spec_helper.STUB_GET_URL
local TEST_CONF = "kong_TEST.yml"

local TCP_PORT = 7777
local UDP_PORT = 8888

describe("Logging Plugins", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Invalid API", function()

    it("should log to TCP", function()
      local thread = spec_helper.start_tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local response, status, headers = http_client.get(STUB_GET_URL, nil, { host = "logging.com" })
      assert.are.equal(200, status)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.truthy(ok)
      assert.truthy(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.are.same("127.0.0.1", log_message.ip)
    end)

    it("should log to UDP", function()
      local thread = spec_helper.start_udp_server(UDP_PORT) -- Starting the mock TCP server

      -- Making the request
      local response, status = http_client.get(STUB_GET_URL, nil, { host = "logging.com" })
      assert.are.equal(200, status)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.truthy(ok)
      assert.truthy(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.are.same("127.0.0.1", log_message.ip)
    end)

    it("should log to file", function()
      local uuid = string.gsub(uuid(), "-", "")

      -- Making the request
      local response, status = http_client.get(STUB_GET_URL, nil,
        { host = "logging.com", file_log_uuid = uuid }
      )
      assert.are.equal(200, status)

      -- Reading the log file and finding the line with the entry
      local configuration = yaml.load(IO.read_file(TEST_CONF))
      assert.truthy(configuration)
      local error_log = IO.read_file(configuration.nginx_working_dir.."/logs/error.log")
      local line
      local lines = stringy.split(error_log, "\n")
      for _, v in ipairs(lines) do
        if string.find(v, uuid) then
          line = v
          break
        end
      end
      assert.truthy(line)

      -- Retrieve the JSON part of the line
      local json_str = line:match("(%{.*%})")
      assert.truthy(json_str)

      local log_message = cjson.decode(json_str)
      assert.are.same("127.0.0.1", log_message.ip)
      assert.are.same(uuid, log_message.request.headers.file_log_uuid)
    end)

  end)
end)
