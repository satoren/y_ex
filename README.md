# Yex

[![CI](https://github.com/satoren/y_ex/actions/workflows/elixir.yml/badge.svg)](https://github.com/satoren/y_ex/actions/workflows/elixir.yml)
[![Coverage Status](https://coveralls.io/repos/satoren/y_ex/badge.svg?branch=main)](https://coveralls.io/r/satoren/y_ex?branch=master)
[![hex.pm version](https://img.shields.io/hexpm/v/y_ex.svg)](https://hex.pm/packages/y_ex)
[![hex.pm downloads](https://img.shields.io/hexpm/dt/y_ex.svg)](https://hex.pm/packages/y_ex)
[![hex.pm license](https://img.shields.io/hexpm/l/y_ex.svg)](https://github.com/satoren/y_ex/blob/master/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/satoren/y_ex.svg)](https://github.com/satoren/y_ex/commits/master)

[Yjs](https://yjs.dev/) port for Elixir using [y-crdt](https://github.com/y-crdt/y-crdt)


A demo using the phoenix framework can be found [here](https://github.com/satoren/y-phoenix-channel).

## Installation

```elixir
def deps do
  [
    {:y_ex, "~> 0.6.0"}
  ]
end
```


## Feature parity


|                                         |                  yjs <br/>(13.6)                  |               yrs<br/>(0.18)               |                y_ex<br/>(0.62)               | 
|-----------------------------------------|:-------------------------------------------------:|:------------------------------------------:|:------------------------------------------:|
| YText: insert/delete                    |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| YText: formatting attributes and deltas |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| YText: embeded elements                 |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| YMap: update/delete                     |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| YMap: weak links                        | &#x2705; <br/> <small>(weak-links branch)</small> |                  &#x2705;                  |                  &#x274C;                  |
| YArray: insert/delete                   |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| YArray & YText quotations               | &#x2705; <br/> <small>(weak links branch)</small> |                  &#x2705;                  |                  &#x2705;                  |
| YArray: move                            |    &#x2705; <br/> <small>(move branch)</small>    |                  &#x2705;                  |                  &#x274C;                  |
| XML Element, Fragment and Text          |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| Sub-documents                           |                     &#x2705;                      |                  &#x2705;                  |                  &#x274C;                  |
| Shared collections: observers           |                     &#x2705;                      |                  &#x2705;                  |                  &#x274C;                  |
| Shared collections: recursive nesting   |                     &#x2705;                      |                  &#x2705;                  |                  &#x274C;                  |
| Document observers                      |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| Transaction: origins                    |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| Snapshots                               |                     &#x2705;                      |                  &#x2705;                  |                  &#x274C;                  |
| Sticky indexes                          |                     &#x2705;                      |                  &#x2705;                  |                  &#x274C;                  |
| Undo Manager                            |                     &#x2705;                      |                  &#x2705;                  |                  &#x274C;                  |
| Awareness                               |                     &#x2705;                      |                  &#x2705;                  |                  &#x2705;                  |
| Network provider: WebSockets            |    &#x2705; <br/> <small>(y-websocket)</small>    |  &#x2705; <br/> <small>(yrs-warp)</small>  |                  &#x274C;                  |
| Network provider: WebRTC                |     &#x2705; <br/> <small>(y-webrtc)</small>      | &#x2705; <br/> <small>(yrs-webrtc)</small> |                  &#x274C;                  |


