# erlang-ann
Simple artificial neural network written in erlang.

## Usage

#### Create
To create neural network you need to write:
```erlang
NN = ann:create_neural_network(LIST_OF_NUMBERS_OF_NEURONS_IN_EACH_LAYER).
```



#### Training
Training set used for training needs to have a form of:
```erlang
TS = [{ INPUT1, OUTPUT1 },
      { INPUT2, OUTPUT2 },
      ...
     ].
% both INPUTx and OUTPUTx should be lists
```
To train network we write following lines:
```erlang
NN ! {learn_nb_epochs, NUMBER_OF_EPOCHS, LEARNING_RATE, TRAINING_SET}.
% or
NN ! {learn_until, MAX_ERROR, LEARNING_RATE, TRAINING_SET}.
```

#### Prediction
For a single input prediction use:
```erlang
NN ! {predict, INPUT}.
```
For multiple predictions at once use:
```erlang
ann:predict(NN, [INPUT1, INPUT2, ...]).
```

### Example

```erlang
% create network
NN = ann:create_neural_network([2, 3, 1]).
```

The above line of code will create neural network that looks like this:
![Example](https://raw.github.com/Grzego/erlang-ann/master/example_ann.PNG)

```erlang
% create training set
TS = [{ [0, 0], [0] },
      { [0, 1], [1] },
      { [1, 0], [1] },
      { [1, 1], [0] }].
```

```erlang
% train network on that set
NN ! {learn_until, 0.00001, 0.1, TS}.
```

```erlang
% predict output using network
NN ! {predict, [0, 0]}.
% or
ann:predict(NN, [[0, 0], [0, 1], [1, 0], [1, 1]]).
```

Example output for multiple predictions in above sample:
```
[[0.0011777173182934142],
 [0.9985160111565027],
 [0.9981415398654492],
 [0.0016010497083807085]]
```
