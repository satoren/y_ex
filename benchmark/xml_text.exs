alias Yex.{Doc, XmlFragment, XmlText, XmlTextPrelim}

Benchee.run(
  %{
    "XmlText.insert/3" => fn %{xml_text: xml_text, data: data} ->
      XmlText.insert(xml_text, 0, data)
    end
  },
  inputs: %{
    "large text" => String.duplicate("1", 10_000),
    "small text" => String.duplicate("1", 10)
  },
  before_scenario: fn data ->
    doc = Doc.new()
    frag = Doc.get_xml_fragment(doc, "xml")
    XmlFragment.push(frag, XmlTextPrelim.from(""))
    {:ok, xml_text} = XmlFragment.fetch(frag, 0)
    %{xml_text: xml_text, data: data}
  end,
  memory_time: 2,
  time: 5
)

Benchee.run(
  %{
    "XmlText.format/4" => fn %{xml_text: xml_text} ->
      XmlText.format(xml_text, 0, 10, %{"href" => "https://github.com"})
    end
  },
  before_scenario: fn _ ->
    doc = Doc.new()
    frag = Doc.get_xml_fragment(doc, "xml")
    XmlFragment.push(frag, XmlTextPrelim.from(""))
    {:ok, xml_text} = XmlFragment.fetch(frag, 0)
    XmlText.insert(xml_text, 0, String.duplicate("x", 20))
    %{xml_text: xml_text}
  end,
  memory_time: 2,
  time: 5
)

Benchee.run(
  %{
    "XmlText.to_delta/1" => fn %{xml_text: xml_text} ->
      XmlText.to_delta(xml_text)
    end,
    "XmlText.to_string/1" => fn %{xml_text: xml_text} ->
      XmlText.to_string(xml_text)
    end
  },
  before_scenario: fn _ ->
    doc = Doc.new()
    frag = Doc.get_xml_fragment(doc, "xml")
    XmlFragment.push(frag, XmlTextPrelim.from(""))
    {:ok, xml_text} = XmlFragment.fetch(frag, 0)
    XmlText.insert(xml_text, 0, String.duplicate("a", 500))
    XmlText.format(xml_text, 0, 100, %{"bold" => true})
    %{xml_text: xml_text}
  end,
  memory_time: 2,
  time: 5
)
