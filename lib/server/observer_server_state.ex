defmodule Yex.ObserverServer.State do
    @moduledoc """
    Provides the `State` struct and functions to manage the internal state of `Yex.ObserverServer`.
    """
    defstruct undo_manager: nil, assigns: %{}, module: nil

    @type t :: %__MODULE__{
            assigns: map,
            undo_manager: Yex.UndoManager.t(),
            module: module()
          }

    def assign(state, key, value) do
      assign(state, [{key, value}])
    end

    def assign(state, attrs) when is_map(attrs) or is_list(attrs) do
      %{state | assigns: Map.merge(state.assigns, Map.new(attrs))}
    end
  end
