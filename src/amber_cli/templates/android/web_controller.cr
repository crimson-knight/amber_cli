require "html"
require "../../app/counter"

module App
  class WebCounterController < Amber::Controller::Base
    # Demonstration state only: production applications inject their own
    # authenticated, durable store. Native and web share rules, not memory.
    @@state = Counter.new

    def index
      response.content_type = "text/html; charset=utf-8"
      <<-HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Shared counter</title></head>
<body><main><h1>Shared counter</h1><p>Count: #{@@state.count}</p><p>Name: #{HTML.escape(@@state.name)}</p>
<form method="post" action="/increment">#{csrf_tag}<button type="submit">Increment</button></form>
<form method="post" action="/name">#{csrf_tag}<label>Name <input name="name" required minlength="2" maxlength="64"></label><button type="submit">Save name</button></form>
</main></body></html>
HTML
    end

    def increment
      @@state.increment
      redirect_to "/"
    end

    def rename
      unless @@state.rename(params["name"]? || "")
        response.status_code = 422
        return "Use at least two characters."
      end
      redirect_to "/"
    end

    def snapshot
      response.content_type = "application/json"
      @@state.snapshot
    end
  end
end
