# Byraft

Byraft is an implementation of Raft consensus algorithm in Ruby using gRPC.

## Install

```shell
bundle install
```

## Example

Three nodes communicates each other with the following configuration.
- `election timeout` between 1 and 2 sec
- `heartbeat period` as 0.1 sec
- `verbose` print DEBUG msg
- Write commited entries in log/log-node-<id>.txt
- Nodes
  - #1 on localhost:50051
  - #2 on localhost:50052
  - #3 on localhost:50053

Run examples in different terminal tabs.

```shell
bin/example 1 # terminal 1
bin/example 2 # terminal 2
bin/example 3 # terminal 3
```

Run client to append log.

```shell
bundle exec bin/client localhost:50051 command
```

## Test

```shell
# rspec
bin/test
```

## Reference

[paper](https://raft.github.io/raft.pdf)
