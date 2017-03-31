%%%----------------------------------------------------------------------

%%% File    : mod_offline_prowl.erl
%%% Author  : Robert George <rgeorge@midnightweb.net>
%%% Purpose : Forward offline messages to prowl
%%% Created : 31 Jul 2010 by Robert George <rgeorge@midnightweb.net>
%%%
%%%
%%% Copyright (C) 2010   Robert George
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(mod_offline_prowl).
-author('rgeorge@midnightweb.net').

-behaviour(gen_mod).

-export([start/2,
	 init/2,
	 stop/1,
	 mod_opt_type/1,
	 find_apikey/2,
	 send_notice/1]).

-define(PROCNAME, ?MODULE).
-define(DEFAULT_APIKEYS, "/etc/ejabberd/prowlapikeys").

-include("ejabberd.hrl").
-include("xmpp.hrl").
-include("logger.hrl").

-record(config, {path=?DEFAULT_APIKEYS}).

start(Host, Opts) ->
    ?INFO_MSG("Starting mod_offline_prowl", [] ),
    register(?PROCNAME,spawn(?MODULE, init, [Host, Opts])),  
    ok.

init(Host, _Opts) ->
    inets:start(),
    ssl:start(),
    ejabberd_hooks:add(offline_message_hook, Host, ?MODULE, send_notice, 10),
    ok.

stop(Host) ->
    ?INFO_MSG("Stopping mod_offline_prowl", [] ),
    ejabberd_hooks:delete(offline_message_hook, Host,
			  ?MODULE, send_notice, 10),
    ok.

mod_opt_type(apikeys) -> fun iolist_to_binary/1;
mod_opt_type(_) -> [apikeys].

find_apikey(APIKeyFile,User) ->
	case io:fread(APIKeyFile,"","~s\t~s") of
		{ok,[JID,APIKey]} ->
			if (JID /= User) ->
				find_apikey(APIKeyFile,User);
			   true ->
				file:close(APIKeyFile),
				APIKey
			end;
		eof ->
			file:close(APIKeyFile),false
	end.

-spec send_notice({any(), message()}) -> {any(), message()}.
send_notice({_Action, #message{from = Peer, to = To, type = Type, body = Body} = Pkt} = Acc) -> 
    APIKeys = gen_mod:get_module_opt(global, ?MODULE, apikeys,fun iolist_to_binary/1,?DEFAULT_APIKEYS ),
    {ok,APIKeyFile} = file:open(APIKeys,[read]),
    APIKey = find_apikey(APIKeyFile,binary_to_list(jid:encode(jid:remove_resource(To)))),
    BodyText = xmpp:get_text(Body),
    if
	(Type /= chat ) ->
		    Acc;
	(BodyText == <<>>) ->
		    Acc;
	(APIKey == false) ->
		    Acc;
	true ->
    	  ?INFO_MSG("Found API Key for ~s. Will post message to Prowl.", [jid:encode(To)] ),
          F = binary:bin_to_list(jid:encode(Peer)),
	  Sep = "&",
	  Post = [
	    "apikey=", APIKey, Sep,
	    "application=Midnight%20Web", Sep,
	    "event=New%20Chat", Sep,
	    "description=", string:sub_word(F,1,$/), "%0A", BodyText, Sep,
	    "priority=-1", Sep,
	    "url=xmpp:", string:sub_word(F,1,$/) ],
	  httpc:request(post, {"https://api.prowlapp.com/publicapi/add", [], "application/x-www-form-urlencoded", list_to_binary(Post)},[],[]),
	  Acc
    end.

