%%% @doc Agent harness for HyperBEAM — `harness@1.0`.
%%%
%%% Orchestrates `llm@1.0` + `relay@1.0` + `store` (HB cache FS) + `query@1.0`
%%% + `lua@5.3a` bash-like env. Example flow: fetch `dan-feed` RSS,
%%% parse, store each post under `dan/posts/<guid>` in the node's store,
%%% then query/index. Lua sidecar `harness.lua` shows AO handlers.
-module(dev_harness).
-implements(<<"harness@1.0">>).
-export([info/1, fetch/3, parse/3, store/3, ingest/3, query/3, list/3]).
-export([fetch_feed/1, parse_feed/1]).

-include_lib("eunit/include/eunit.hrl").

info(_) ->
    #{
        <<"fetch">> => dev,
        <<"parse">> => dev,
        <<"store">> => dev,
        <<"ingest">> => dev,
        <<"query">> => dev,
        <<"list">> => dev
    }.

%% Fetch dan-feed RSS via hb_http (public, not blocked)
fetch(Base, _Req, Opts) ->
    URL = hb_ao:get(<<"url">>, Base, <<"https://hyperio-mc.github.io/dan-feed/feed.xml">>, Opts),
    fetch_feed(URL, Opts).
fetch_feed(URL) -> fetch_feed(URL, #{}).
fetch_feed(URL, Opts) ->
    Req = #{<<"path">> => URL, <<"method">> => <<"GET">>},
    case hb_http:request(Req, Opts#{ <<"http-only-result">> => false }) of
        {ok, #{<<"body">> := Body}} -> {ok, Body};
        {ok, #{body := Body}} -> {ok, Body};
        {ok, Res} -> {ok, maps:get(<<"body">>, Res, maps:get(body, Res, <<>>))};
        Err -> Err
    end.

%% Parse RSS XML → list of post maps
parse(Base, Req, Opts) ->
    Body = hb_ao:get(<<"body">>, Req, hb_ao:get(<<"body">>, Base, <<>>, Opts), Opts),
    case Body of
        <<>> -> fetch_and_parse(Opts);
        _ -> {ok, parse_feed(Body)}
    end.
fetch_and_parse(Opts) ->
    case fetch_feed(<<"https://hyperio-mc.github.io/dan-feed/feed.xml">>, Opts) of
        {ok, Body} -> {ok, parse_feed(Body)};
        Err -> Err
    end.

parse_feed(Body) when is_binary(Body) ->
    % Very simple RSS item extraction via regex — no xmerl dep
    Items = case re:run(Body, <<"<item>(.*?)</item>">>, [global, dotall, {capture, [1], binary}]) of
        {match, Matches} -> [ hd(M) || M <- Matches ];
        nomatch -> []
    end,
    [parse_item(Item) || Item <- Items].

parse_item(Item) ->
    G = extract_tag(Item, <<"guid">>),
    #{
        <<"guid">> => G,
        <<"id">> => G,
        <<"title">> => extract_tag(Item, <<"title">>),
        <<"link">> => extract_tag(Item, <<"link">>),
        <<"description">> => extract_tag(Item, <<"description">>),
        <<"pubDate">> => extract_tag(Item, <<"pubDate">>),
        <<"source">> => extract_source(Item)
    }.

extract_tag(Bin, Tag) ->
    Pat = <<"<", Tag/binary, "[^>]*>(.*?)</", Tag/binary, ">">>,
    case re:run(Bin, Pat, [dotall, {capture, [1], binary}]) of
        {match, [V]} -> unescape(V);
        nomatch -> <<>>
    end.

extract_source(Item) ->
    case re:run(Item, <<"<source[^>]*>(.*?)</source>">>, [dotall, {capture, [1], binary}]) of
        {match, [V]} -> unescape(V);
        nomatch -> <<>>
    end.

unescape(Bin) ->
    B1 = binary:replace(Bin, <<"&amp;">>, <<"&">>, [global]),
    B2 = binary:replace(B1, <<"&lt;">>, <<"<">>, [global]),
    B3 = binary:replace(B2, <<"&gt;">>, <<">">>, [global]),
    B4 = binary:replace(B3, <<"&apos;">>, <<"'">>, [global]),
    binary:replace(B4, <<"&quot;">>, <<"\"">>, [global]).

%% Store posts as dan-<guid> flat keys + dan-index
store(Base, Req, Opts) ->
    Posts = case hb_ao:get(<<"posts">>, Req, not_found, Opts) of
        not_found -> case hb_ao:get(<<"posts">>, Base, not_found, Opts) of
            not_found -> parse_feed(hb_ao:get(<<"body">>, Req, <<>>, Opts));
            P -> P
        end;
        P -> P
    end,
    PostsList = case is_list(Posts) of true -> Posts; false -> [Posts] end,
    Store = hb_opts:get(store, no_viable, Opts),
    % Write each post as dan-<guid> => JSON binary
    lists:foreach(fun(P) ->
        Guid = maps:get(<<"guid">>, P, hb_util:bin(rand:uniform(1000000))),
        Key = <<"dan-", Guid/binary>>,
        hb_store:write(Store, #{Key => hb_json:encode(P)}, Opts)
    end, PostsList),
    % Maintain index
    ExistingIdx = case hb_store:read(Store, <<"dan-index">>, Opts) of {ok, Bin} -> try hb_json:decode(Bin) catch _:_ -> [] end; _ -> [] end,
    NewGuids = [maps:get(<<"guid">>, P, <<>>) || P <- PostsList],
    MergedIdx = lists:usort(ExistingIdx ++ NewGuids),
    hb_store:write(Store, #{<<"dan-index">> => hb_json:encode(MergedIdx)}, Opts),
    {ok, #{<<"stored">> => length(PostsList), <<"keys">> => NewGuids, <<"total">> => length(MergedIdx)}}.

%% Ingest = fetch + parse + store
ingest(_Base, _Req, Opts) ->
    case fetch_feed(<<"https://hyperio-mc.github.io/dan-feed/feed.xml">>, Opts) of
        {ok, Body} ->
            Posts = parse_feed(Body),
            Store = hb_opts:get(store, no_viable, Opts),
            lists:foreach(fun(P) ->
                Guid = maps:get(<<"guid">>, P, hb_util:bin(rand:uniform(1000000))),
                Key = <<"dan-", Guid/binary>>,
                hb_store:write(Store, #{Key => hb_json:encode(P)}, Opts)
            end, Posts),
            ExistingIdx = case hb_store:read(Store, <<"dan-index">>, Opts) of {ok, Bin} -> try hb_json:decode(Bin) catch _:_ -> [] end; _ -> [] end,
            NewGuids = [maps:get(<<"guid">>, P, <<>>) || P <- Posts],
            MergedIdx = lists:usort(ExistingIdx ++ NewGuids),
            hb_store:write(Store, #{<<"dan-index">> => hb_json:encode(MergedIdx)}, Opts),
            {ok, #{<<"ingested">> => length(Posts), <<"total">> => length(MergedIdx), <<"posts">> => Posts}};
        Err -> Err
    end.

%% List stored posts via dan-index
list(_Base, _Req, Opts) ->
    Store = hb_opts:get(store, no_viable, Opts),
    case hb_store:read(Store, <<"dan-index">>, Opts) of
        {ok, Bin} ->
            Keys = try hb_json:decode(Bin) catch _:_ -> [] end,
            {ok, #{<<"keys">> => Keys, <<"count">> => length(Keys)}};
        Err -> Err
    end.

%% Query via dan-index + per-post reads
query(Base, Req, Opts) ->
    Q = hb_ao:get(<<"q">>, Req, hb_ao:get(<<"query">>, Base, <<>>, Opts), Opts),
    Store = hb_opts:get(store, no_viable, Opts),
    case hb_store:read(Store, <<"dan-index">>, Opts) of
        {ok, Bin} ->
            Keys = try hb_json:decode(Bin) catch _:_ -> [] end,
            Posts = [case hb_store:read(Store, <<"dan-", K/binary>>, Opts) of {ok, B} -> try hb_json:decode(B) catch _:_ -> #{} end; _ -> #{} end || K <- Keys],
            Filtered = case Q of
                <<>> -> Posts;
                _ -> [P || P <- Posts, matches_query(P, Q)]
            end,
            {ok, #{<<"results">> => Filtered, <<"count">> => length(Filtered), <<"q">> => Q}};
        Err -> Err
    end.

matches_query(Post, Q) ->
    QLow = string:lowercase(Q),
    Fields = [maps:get(<<"title">>, Post, <<>>), maps:get(<<"description">>, Post, <<>>), maps:get(<<"link">>, Post, <<>>)],
    lists:any(fun(F) -> binary:match(string:lowercase(F), QLow) =/= nomatch end, Fields).

-ifdef(TEST).
parse_feed_test() ->
    Body = <<"<rss><channel><item><guid>1</guid><title>T</title><link>http://x</link><description>D</description></item></channel></rss>">>,
    [Post] = parse_feed(Body),
    ?assertEqual(<<"1">>, maps:get(<<"guid">>, Post)),
    ?assertEqual(<<"T">>, maps:get(<<"title">>, Post)).
-endif.
