# Byraft

Byraft is an implementation of Raft consensus algorithm in Ruby using gRPC.

<img width="80%" src="https://user-images.githubusercontent.com/38203748/182122278-e61c3aad-8144-441f-9e59-3ed43b5a5fdb.gif"/>

## Install

```shell
gem install grpc
```

## Usage

```shell
script/byraft # run server
script/client # request as client
```

## Spec

[raft.proto](proto/raft.proto)

## Example

Configuration

- `election timeout` : between 1 and 2 sec
- `heartbeat period` : 0.1 sec
- Write committed commands in log/log-node-\<id\>.txt
- Nodes
    - #1 on localhost:50051
    - #2 on localhost:50052
    - ...

Options

- `-n <number of nodes>` : default is 3
- `-c <command>` : request command as client
- `-v` : set logger level to DEBUG, otherwise INFO

Run servers in different terminals.

```shell
script/example 1 -n 5 # terminal 1
script/example 2 -n 5 # terminal 2
script/example 3 -n 5 # terminal 3
script/example 4 -n 5 # terminal 4
script/example 5 -n 5 # terminal 5
```

Run client to append log.

```shell
script/example 1 -c 'RUN COMMAND' # another terminal
```

## Test

```shell
bundle install
bundle exec rspec
```

## TODO

- [Liveness in the face of Network Faults](https://decentralizedthoughts.github.io/2020-12-12-raft-liveness-full-omission/)
- Make gem

## Reference

[paper](https://raft.github.io/raft.pdf)
