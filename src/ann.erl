%  ann.erl
-module(ann).
-compile([export_all]).

%% -----
% Activation functions
%% -----

% --
sigmoid(X) -> 1.0 / (1.0 + math:exp(-X)).

activation(X) -> sigmoid(X).
activation_gradient(X) -> X * (1.0 - X).

output_activation(X) -> X.
output_activation_gradient(_) -> 1.0.



% --
run_neuron() ->
  spawn_link(ann, run_neuron, [none, [], [], 0]).

run_neuron(Main, Inputs, Outputs, Token) ->
  receive
    {main_pid, Pid} ->
      run_neuron(Pid, Inputs, Outputs, Token);

    {connect_to_output, Pid} ->
      run_neuron(Main, Inputs, [Pid | Outputs], Token);

    {connect_to_input, PidWeight} ->
      run_neuron(Main, [PidWeight | Inputs], Outputs, Token);

    {status, Token} ->
      status_neuron(Inputs, Outputs, Token),
      run_neuron(Main, Inputs, Outputs, Token + 1);

    {feed_forward, Token} ->
      fire_neuron(Inputs, Outputs, {feed_forward, Token}, Main, Token),
      run_neuron(Main, Inputs, Outputs, Token + 1);

    {back_prop, LearningRate, Token} ->
      NewInputs = learn_neuron(Inputs, Outputs, LearningRate, Main, Token),
      run_neuron(Main, NewInputs, Outputs, Token + 1)
  end.



%% -----
% operations on neuron
%% -----

% --
status_neuron(Inputs, Outputs, Token) ->
  io:format("~p -> ~p --> ~p ~n", [self(), Inputs, Outputs]),
  resend_status_neuron(Inputs, Outputs, Token).



resend_status_neuron([], Outputs, Token) ->
  lists:foreach(fun(Pid) ->
                  Pid ! {status, Token}
                end, Outputs);

resend_status_neuron(_, _, _) -> ok.



% -- learning
  % -- bias neuron
learn_neuron([], Outputs, LearningRate, Main, Token) ->
  fire_neuron([], Outputs, {back_prop, LearningRate, Token}, Main, Token),
  [receive {delta, Pid, _, Token} -> ignore end || Pid <- Outputs],
  [];


  % -- output neuron
learn_neuron(Inputs, [], LearningRate, Main, Token) ->
  {Output, Outs} = fire_neuron(Inputs, [], output_layer_fire, Main, Token),
  receive {target, Target, Token} -> Target end,
  Delta = (Output - Target) * output_activation_gradient(Output),
  update_weights(Inputs, Outs, Delta, LearningRate, Token);


  % -- input layer neuron
learn_neuron([{Pid, Weight}], Outputs, _, Main, Token) when Pid == Main ->
  fire_neuron([{Pid, Weight}], Outputs, input_layer_fire, Main, Token),
  [receive {delta, N, InDelta, Token} -> InDelta end || N <- Outputs],
  [{Pid, Weight}];


  % -- hidden layer neuron
learn_neuron(Inputs, Outputs, LearningRate, Main, Token) ->
  {Output, Outs} = fire_neuron(Inputs, Outputs, hidden_layer_fire, Main, Token),
  Delta = lists:sum([receive {delta, Pid, InDelta, Token} -> InDelta end || Pid <- Outputs]) * activation_gradient(Output),
  update_weights(Inputs, Outs, Delta, LearningRate, Token).


% --
update_weights(Inputs, Outs, Delta, LearningRate, Token) ->
  Self = self(),
  lists:map(fun({{Pid, Weight}, Out}) ->
              Pid ! {delta, Self, Delta * Weight, Token},
              {Pid, Weight - LearningRate * Delta * Out}
            end, lists:zip(Inputs, Outs)).

% -- predicting
  % -- bias neuron
fire_neuron([], Outputs, Opt, _, Token) ->
  Self = self(),
  lists:foreach(fun(Pid) ->
                  Pid ! Opt, 
                  Pid ! {fire, Self, 1.0, Token} 
                end, Outputs),
  {1.0, []};


  % -- output neuron
fire_neuron(Inputs, [], _, Main, Token) ->
  Self = self(),
  Input = [receive {fire, Pid, In, Token} -> {Weight * In, In} end || {Pid, Weight} <- Inputs],
  Output = output_activation(sum_tuples(Input)),
  Main ! {output, Self, Output, Token},
  {Output, snd(Input)};


  % -- input layer
fire_neuron([{Pid, _}], Outputs, _, Main, Token) when Pid == Main ->
  Self = self(),
  Output = receive {fire, Pid, In, Token} -> In end,
  lists:foreach(fun(N) ->
                  N ! {fire, Self, Output, Token}
                end, Outputs),
  {Output, [Output]};


  % -- hidden layer neuron
fire_neuron(Inputs, Outputs, _, _, Token) ->
  Self = self(),
  Input = [receive {fire, Pid, In, Token} -> {Weight * In, In} end || {Pid, Weight} <- Inputs],
  Output = activation(sum_tuples(Input)),
  lists:foreach(fun(Pid) ->
                  Pid ! {fire, Self, Output, Token}
                end, Outputs),
  {Output, snd(Input)}.




% --
create_neural_network(Layers) ->
  Weights = random_weigths(compute_neurons(Layers)),
  create_neural_network(Layers, Weights).

% --
create_neural_network(Layers, Weights) when length(Layers) > 1 ->
  Neurons = [[run_neuron() || _ <- lists:seq(1, InLayer)] || InLayer <- modify_layers(Layers)],
  full_mesh_connect(Neurons, Weights),
  NN = spawn_link(ann, neural_network, [tail(head(Neurons)), 
                                        lists:last(Neurons), 
                                        lists:map(fun(X) -> head(X) end, 
                                        lists:droplast(Neurons)), 
                                        0]),

  lists:foreach(fun(Pid) -> 
                  Pid ! {connect_to_input, {NN, 1.0}} 
                end, tail(head(Neurons))),
  lists:foreach(fun(Pid) ->
                  Pid ! {main_pid, NN}
                end, lists:concat(Neurons)),
  NN;

create_neural_network(_, _) ->
  io:format("Not enought layers.~n"), fail.

% --
neural_network(InputLayer, OutputLayer, BiasNeurons, Token) ->
  erlang:garbage_collect(),
  receive
    {predict, Input} ->
      Output = forward_pass(InputLayer, OutputLayer, BiasNeurons, Token, Input),
      io:format("Output: ~p~n", [Output]),
      neural_network(InputLayer, OutputLayer, BiasNeurons, Token + 1);

    {predict, Input, OutputPid} ->
      Output = forward_pass(InputLayer, OutputLayer, BiasNeurons, Token, Input),
      OutputPid ! {predicted, Output},
      neural_network(InputLayer, OutputLayer, BiasNeurons, Token + 1);

    {compute_error, TrainingSet} ->
      Examples = length(TrainingSet),
      Rss =  forward_pass_examples(InputLayer, OutputLayer, BiasNeurons, Token, TrainingSet, Examples),
      io:format("RSS: ~p~n", [Rss]),
      neural_network(InputLayer, OutputLayer, BiasNeurons, Token + Examples);

    {learn_nb_epochs, Epochs, LearningRate, TrainingSet} ->
      TokenShift = learn_epochs(InputLayer, OutputLayer, BiasNeurons, Token, Epochs, LearningRate, TrainingSet),
      io:format("Done.~n"),
      neural_network(InputLayer, OutputLayer, BiasNeurons, Token + TokenShift);

    {learn_until, RssEps, LearningRate, TrainingSet} ->
      TokenShift = learn_until(InputLayer, OutputLayer, BiasNeurons, Token, RssEps, LearningRate, TrainingSet),
      io:format("Done.~n"),
      neural_network(InputLayer, OutputLayer, BiasNeurons, Token + TokenShift);

    {status} ->
      lists:foreach(fun(N) -> 
                      N ! {status, Token}
                    end, BiasNeurons),
      lists:foreach(fun(N) -> 
                      N ! {status, Token}
                    end, InputLayer),
      neural_network(InputLayer, OutputLayer, BiasNeurons, Token + 1);

    {finish} ->
      exit(neural_network_shutdown);

    _ ->
      neural_network(InputLayer, OutputLayer, BiasNeurons, Token)
  end.



% --
predict(NN, Set) ->
  Self = self(),
  lists:map(fun(Ex) ->
              NN ! {predict, Ex, Self},
              receive {predicted, Val} -> Val end,
              Val
            end, Set).



% --
learn_epochs(InputLayer, OutputLayer, BiasNeurons, Token, Epochs, LearningRate, TrainingSet) ->
  Examples = length(TrainingSet),
  lists:foreach(fun(Epoch) ->
      learn_pass(InputLayer, OutputLayer, BiasNeurons, Token + Examples * Epoch * 2, LearningRate, TrainingSet, Examples),
      Rss = forward_pass_examples(InputLayer, OutputLayer, BiasNeurons, Token + Examples * (Epoch * 2 + 1), TrainingSet, Examples),
      io:format("Epoch ~p, loss: ~p, average: ~p~n", [Epoch, Rss, Rss / Examples])
    end, lists:seq(0, Epochs - 1)),
  Examples * Epochs * 2.



% --
learn_until(InputLayer, OutputLayer, BiasNeurons, Token, RssEps, LearningRate, TrainingSet) ->
  Examples = length(TrainingSet),
  {_, Epochs} = until(
    fun({X, _}) -> X < RssEps end,
    fun({_, Epoch}) ->
      learn_pass(InputLayer, OutputLayer, BiasNeurons, Token + Examples * Epoch, LearningRate, TrainingSet, Examples),
      Rss = forward_pass_examples(InputLayer, OutputLayer, BiasNeurons, Token + Examples * (Epoch + 1), TrainingSet, Examples),
      io:format("Epoch ~p, loss: ~p, average: ~p~n", [Epoch div 2, Rss, Rss / Examples]),
      {Rss, Epoch + 2}
    end, {RssEps * 2, 0}),
  Examples * Epochs.



% --
learn_pass(InputLayer, OutputLayer, BiasNeurons, Token, LearningRate, TrainingSet, Examples) ->
  Self = self(),
  lists:foreach(fun({Shift, {Input, Output}}) ->
                  TokenShift = Token + Shift,
                  lists:foreach(fun(N) -> 
                                  N ! {back_prop, LearningRate, TokenShift} 
                                end, BiasNeurons),
                  lists:foreach(fun({N, In}) ->
                                  N ! {back_prop, LearningRate, TokenShift},
                                  N ! {fire, Self, In, TokenShift}
                                end, lists:zip(InputLayer, Input)),
                  lists:foreach(fun({N, Out}) ->
                                  N ! {target, Out, TokenShift}
                                end, lists:zip(OutputLayer, Output)),
                  [receive {output, Pid, Out, TokenShift} -> Out end || Pid <- OutputLayer]
                end, lists:zip(lists:seq(0, Examples - 1), TrainingSet)).



% --
forward_pass_examples(InputLayer, OutputLayer, BiasNeurons, Token, TrainingSet, Examples) ->
  Rss = lists:map(fun({Shift, {ExIn, ExOut}}) ->
                    TokenShift = Token + Shift,
                    Output = forward_pass(InputLayer, OutputLayer, BiasNeurons, TokenShift, ExIn),
                    compute_rss(Output, ExOut)
                  end, lists:zip(lists:seq(0, Examples - 1), TrainingSet)),
  lists:sum(Rss).



% --
forward_pass(InputLayer, OutputLayer, BiasNeurons, Token, Example) ->
  Self = self(),
  lists:foreach(fun(Pid) -> 
                  Pid ! {feed_forward, Token} 
                end, BiasNeurons),
  lists:foreach(fun({Pid, In}) -> 
                  Pid ! {feed_forward, Token}, 
                  Pid ! {fire, Self, In, Token} 
                end, lists:zip(InputLayer, Example)),
  [receive {output, Pid, Out, Token} -> Out end || Pid <- OutputLayer].



% --
compute_rss(Xs, Ys) -> compute_rss(Xs, Ys, 0.0).
compute_rss([], [], R) -> R;
compute_rss([X | Xs], [Y | Ys], R) -> 
  D = X - Y,
  compute_rss(Xs, Ys, R + D * D).



% --
connect(InPidWeight, OutPid) ->
  OutPid ! {connect_to_input, InPidWeight},
  {InPid, _} = InPidWeight,
  InPid ! {connect_to_output, OutPid},
  io:format("connected ~p to ~p ~n", [InPid, OutPid]).



% --
full_mesh_connect(_, []) -> ok;

full_mesh_connect([N1, N2], W) ->
  full_mesh_connect_layers(N1, N2, W);

full_mesh_connect([N1, N2 | Ns], W) ->
  Ws = full_mesh_connect_layers(N1, tail(N2), W),
  full_mesh_connect([N2 | Ns], Ws).



full_mesh_connect_layers(_, [], W) -> W;
full_mesh_connect_layers(N1, [N | Ns], W) ->
  Ws = full_mesh_connect_layer(N1, N, W),
  full_mesh_connect_layers(N1, Ns, Ws).



full_mesh_connect_layer([], _, W) -> W;
full_mesh_connect_layer([N1 | Ns], N, [W | Ws]) ->
  connect({N1, W}, N),
  full_mesh_connect_layer(Ns, N, Ws).


%% -----
% utility functions
%% -----

% --
sum_tuples(L) -> sum_tuples(L, 0).
sum_tuples([], Acc) -> Acc;
sum_tuples([{X, _} | Xs], Acc) -> sum_tuples(Xs, Acc + X).



% --
snd([]) -> [];
snd([{_, X} | Xs]) -> [X | snd(Xs)].



% --
head([H | _]) -> H.
tail([_ | T]) -> T.



% --
modify_layers([]) -> [];
modify_layers([L]) -> [L];
modify_layers([L | Ls]) -> [L + 1 | modify_layers(Ls)].



% --
compute_neurons([]) -> 0;
compute_neurons([L]) -> L;
compute_neurons([L1, L2 | Ls]) -> (L1 + 1) * L2 + compute_neurons([L2 | Ls]).



% --
random_weigths(N) -> [random:uniform() * 2.0 - 1.0 || _ <- lists:seq(1, N)].



% --
random_shuffle(L) ->
  [X || {_, X} <- lists:sort([{random:uniform(), N} || N <- L])].



% --
until(P, F, X) ->
  case P(X) of
    false -> until(P, F, F(X));
    true -> X
  end.



%% -----
% read/write functions
%% -----

% --
read_train_set(FileName, NumOfFeatures) ->
  Lines = read_lines(FileName),
  Numbers = lists:map(fun(L) -> lists:map(fun(X) -> parse_float(X) end, string:tokens(L, " ")) end, Lines),
  lists:map(fun(L) -> lists:split(NumOfFeatures, L) end, Numbers).



% --
write_data(FileName, Data) ->
  Out = string:join([string:join([io_lib:format("~p", [X]) || X <- Y], " ") || Y <- Data], "\n"),
  file:write_file(FileName, io_lib:fwrite(Out, [])).



% --
read_lines(FileName) ->
    {ok, Device} = file:open(FileName, [read]),
    try get_lines(Device)
      after file:close(Device)
    end.



get_lines(Device) ->
    case io:get_line(Device, "") of
        eof  -> [];
        Line -> [Line | get_lines(Device)]
    end.



parse_float(String) ->
  T = string:strip(String, both, $\n),
  S = string:strip(T, both),
  case string:to_float(S) of
    {error, no_float} -> float(list_to_integer(S));
    {F, _} -> F
  end.