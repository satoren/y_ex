defprotocol Yex.Xml do
  def next_sibling(xml)
  def prev_sibling(xml)
  def parent(xml)
  def to_string(xml)
end

defimpl Yex.Xml, for: Yex.XmlText do
  defdelegate next_sibling(xml), to: Yex.XmlText
  defdelegate prev_sibling(xml), to: Yex.XmlText
  defdelegate parent(xml), to: Yex.XmlText
  defdelegate to_string(xml), to: Yex.XmlText
end

defimpl Yex.Xml, for: Yex.XmlElement do
  defdelegate next_sibling(xml), to: Yex.XmlElement
  defdelegate prev_sibling(xml), to: Yex.XmlElement
  defdelegate parent(xml), to: Yex.XmlElement
  defdelegate to_string(xml), to: Yex.XmlElement
end
