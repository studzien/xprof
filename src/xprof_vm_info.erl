-module(xprof_vm_info).

-export([get_available_funs/1]).

%% @doc Return list of existing module/funcion/arity that match query.
%%
%% If query does not contain colon only the global functions
%% (excluding module_info) of all the matching modules are listed.
%% If query contains colon both the global and local functions
%% (excluding generated local functions) are listed of that particular module
%% matching the query.

-spec get_available_funs(binary()) -> [MFA]
  when MFA :: list(). %% [module(), atom(), arity()]
get_available_funs(Query) ->
    case binary:split(Query, <<":">>) of
        [ModBin, Rest] ->
            case is_module(ModBin) of
                {true, Mod} ->
                    Funs = get_all_functions(Mod),
                    %% match instead on "mod:fun/" if value seems to be a
                    %% match-spec fun of the form "mod:fun(..."
                    FunPrefix = re:replace(Rest, "\\(.*", "/", [{return, list}]),
                    [[Mod, Fun, Arity]
                     || {Fun, Arity} <- filter_funs(FunPrefix, Funs)];
                false ->
                    []
            end;
        [ModPrefix] ->
            [[Mod, Fun, Arity]
             || Mod <- filter_mods(binary_to_list(ModPrefix), get_modules()),
                {Fun, Arity} <- get_global_functions(Mod)]
    end.

filter_funs(Prefix, Funs) ->
    lists:filter(fun({Fun, Arity}) ->
                         Str = lists:flatten(
                                 [atom_to_list(Fun), $/, integer_to_list(Arity)]),
                         lists:prefix(Prefix, Str)
                 end, Funs).

filter_mods(Prefix, Mods) ->
    lists:filter(fun(Mod) ->
                         Str = atom_to_list(Mod),
                         lists:prefix(Prefix, Str)
                 end, Mods).

-spec get_global_functions(module()) -> [{atom(), arity()}].
get_global_functions(Mod) ->
    [FA || FA = {F, _} <- Mod:module_info(exports), F =/= module_info].

-spec get_all_functions(module()) -> [{atom(), arity()}].
get_all_functions(Mod) ->
    %% filter out functions generated for fun objects
    %% and list comprehensions like '-filter_funs/2-fun-0-'
    [FA || FA = {F, _} <- Mod:module_info(functions), not lists:prefix("-", atom_to_list(F))].

is_module(ModBin) ->
    try list_to_existing_atom(binary_to_list(ModBin)) of
        Mod ->
            case code:is_loaded(Mod) of
                {file, _} -> {true, Mod};
                false -> false
            end
    catch error:badarg ->
            false
    end.

get_modules() ->
    ModsFiles = code:all_loaded(),
    [ Mod || {Mod, _File} <- ModsFiles].
