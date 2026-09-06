require "http/client"
require "json"

# Runtime proof against an independently launched, generated web application.
# Never log session cookies or CSRF tokens.
class GeneratedWebProof
  @cookies = HTTP::Cookies.new

  def initialize(@origin : String)
    uri = URI.parse(@origin)
    raise "Proof server must be local HTTP" unless uri.scheme == "http" && uri.host == "127.0.0.1"
  end

  def request(method : String, path : String, data = {} of String => String)
    headers = HTTP::Headers.new
    @cookies.add_request_headers(headers)
    body = nil
    unless data.empty?
      headers["Content-Type"] = "application/x-www-form-urlencoded"
      body = HTTP::Params.encode(data)
    end
    response = HTTP::Client.exec(method, @origin + path, headers: headers, body: body)
    @cookies.fill_from_server_headers(response.headers)
    response
  end

  def state(count : Int32, name : String)
    response = request("GET", "/state")
    raise "State endpoint failed: #{response.status_code}" unless response.status_code == 200
    value = JSON.parse(response.body)
    raise "Shared state mismatch" unless value["count"].as_i == count && value["name"].as_s == name
  end

  def form(path : String, values = {} of String => String, expected_status = 302)
    page = request("GET", "/")
    raise "Generated page failed" unless page.status_code == 200
    token = page.body.match(/name="_csrf" value="([^"]+)"/).try(&.[1]) || raise "Missing CSRF form field"
    response = request("POST", path, values.merge({"_csrf" => token}))
    raise "Form #{path}: expected #{expected_status}, got #{response.status_code}" unless response.status_code == expected_status
  end

  def run
    state(0, "Guest")
    forbidden = request("POST", "/increment", {"untrusted" => "1"})
    raise "Unprotected state mutation" unless forbidden.status_code == 403
    state(0, "Guest")
    form("/increment")
    state(1, "Guest")
    form("/name", {"name" => "Android"})
    state(1, "Android")
    form("/name", {"name" => "x"}, 422)
    state(1, "Android")
    form("/name", {"name" => "<b>Amber & Android</b>"})
    page = request("GET", "/").body
    raise "Name is not HTML escaped" unless page.includes?("&lt;b&gt;Amber &amp; Android&lt;/b&gt;") && !page.includes?("Name: <b>")
    puts "PASS: generated web state, shared validation, rejected CSRF and HTML escaping"
  end
end

GeneratedWebProof.new(ARGV[0]? || raise "Usage: test_generated_web <http://127.0.0.1:port>").run
