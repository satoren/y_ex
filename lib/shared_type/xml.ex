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

  @doc """
  Returns the value of the node attribute `key`, or nil when it is not set.

  Implemented by `Yex.XmlElement` and `Yex.XmlText`, the nodes in `Yex.XmlFragment.tree_walker/2`
  output that carry attributes. A nested `Yex.XmlFragment` has no attributes and
  does not implement this protocol, as in yjs and yrs.
  """
  def get_attribute(xml, key)

  @doc """
  Returns all node attributes as a map.

  Implemented by `Yex.XmlElement` and `Yex.XmlText`; see `get_attribute/2`.
  """
  def get_attributes(xml)
end
