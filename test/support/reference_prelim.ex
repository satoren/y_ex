defmodule Yex.ReferencePrelim do
  @moduledoc false
  # The `as_prelim/1` functions as they were written in Elixir, one NIF call per node,
  # before the conversion moved into a single NIF. Tests check the native result against
  # this. Children are read with `children/1`, which streams the same nodes the native
  # conversion walks.

  alias Yex.{Array, Map, Text, WeakLink, XmlElement, XmlFragment, XmlText}

  def as_prelim(%Text{} = text), do: text |> Text.to_delta() |> Yex.TextPrelim.from()

  def as_prelim(%Array{} = array) do
    array |> Array.to_list() |> Enum.map(&as_prelim/1) |> Yex.ArrayPrelim.from()
  end

  def as_prelim(%Map{} = map) do
    map
    |> Map.to_list()
    |> Enum.map(fn {key, value} -> {key, as_prelim(value)} end)
    |> Elixir.Map.new()
    |> Yex.MapPrelim.from()
  end

  def as_prelim(%XmlElement{} = xml) do
    children = xml |> XmlElement.children() |> Enum.map(&as_prelim/1)
    attributes = attributes(XmlElement.get_attributes(xml))
    Yex.XmlElementPrelim.new(XmlElement.get_tag(xml), children, attributes)
  end

  def as_prelim(%XmlFragment{} = xml) do
    xml |> XmlFragment.children() |> Enum.map(&as_prelim/1) |> Yex.XmlFragmentPrelim.new()
  end

  def as_prelim(%XmlText{} = xml) do
    %{
      Yex.XmlTextPrelim.from(XmlText.to_delta(xml))
      | attributes: attributes(XmlText.get_attributes(xml))
    }
  end

  def as_prelim(%WeakLink{} = weak), do: WeakLink.as_prelim(weak)
  def as_prelim(value), do: value

  defp attributes(attributes) do
    Elixir.Map.new(attributes, fn {key, value} -> {key, as_prelim(value)} end)
  end
end
