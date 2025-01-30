defprotocol Yex.Xml do
  def next_sibling(xml)
  def prev_sibling(xml)
  def parent(xml)
  def to_string(xml)
end
