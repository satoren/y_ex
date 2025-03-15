defprotocol Yex.Xml do
  @moduledoc """
  Defines a protocol for XML node operations.
  This protocol provides basic navigation and string conversion functionality for XML nodes.
  """

  @doc """
  Returns the next sibling node of the current node.
  """
  def next_sibling(xml)

  @doc """
  Returns the previous sibling node of the current node.
  """
  def prev_sibling(xml)

  @doc """
  Returns the parent node of the current node.
  """
  def parent(xml)

  @doc """
  Converts the XML node to its string representation.
  """
  def to_string(xml)
end
