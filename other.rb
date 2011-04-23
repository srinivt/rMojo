# Rack - openid - rpx

get '/login' do
  erb :login
end

post '/login' do
  if resp = request.env["rack.openid.response"]
    if resp.status == :success
      "Welcome: #{resp.display_identifier}"
    else
      "Error: #{resp.status}"
    end
  else
    headers 'WWW-Authenticate' => Rack::OpenID.build_header(
      :identifier => params["openid_identifier"]
    )
    throw :halt, [401, 'got openid?']
  end
end

enable :inline_templates


__END__

@@ login

<iframe src="http://mojo-jr.rpxnow.com/openid/embed?token_url=http%3A%2F%2Fts-mini.com%2Frpx" scrolling="no" frameBorder="no" allowtransparency="true" style="width:400px;height:240px">

<form action="/login" method="post">
<p>
<label for="openid_identifier">OpenID:</label>
<input id="openid_identifier" name="openid_identifier" type="text" />
</p>

<p>
<input name="commit" type="submit" value="Sign in" />
</p>
</form>


