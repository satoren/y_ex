# DocServer (`Yex.Sync.SharedDoc`) 上の XmlText 操作を `SharedDoc.update_doc/2` 経由で計測する。
#
#   MIX_ENV=dev mix run benchmark/doc_server.exs

alias Yex.{Doc, XmlFragment, XmlText, XmlTextPrelim}
alias Yex.Sync.SharedDoc

random_doc_name = fn -> :crypto.strong_rand_bytes(10) end

IO.puts("\n=== SharedDoc (DocServer) — XmlText.insert ===\n")

Benchee.run(
  %{
    "SharedDoc.update_doc/2 — XmlText.insert/3" => fn %{server: server, data: data} ->
      SharedDoc.update_doc(server, fn doc ->
        frag = Doc.get_xml_fragment(doc, "xml")
        {:ok, xml_text} = XmlFragment.fetch(frag, 0)
        XmlText.insert(xml_text, 0, data)
      end)
    end
  },
  inputs: %{
    "large text" => String.duplicate("1", 10_000),
    "small text" => String.duplicate("1", 10)
  },
  before_scenario: fn data ->
    {:ok, server} =
      SharedDoc.start_link(doc_name: random_doc_name.(), auto_exit: false)

    SharedDoc.update_doc(server, fn doc ->
      frag = Doc.get_xml_fragment(doc, "xml")
      XmlFragment.push(frag, XmlTextPrelim.from(""))
    end)

    %{server: server, data: data}
  end,
  after_scenario: fn %{server: server} ->
    GenServer.stop(server, :normal, :infinity)
  end,
  memory_time: 2,
  time: 5
)

IO.puts("\n=== SharedDoc (DocServer) — XmlText.format ===\n")

Benchee.run(
  %{
    "SharedDoc.update_doc/2 — XmlText.format/4" => fn %{server: server} ->
      SharedDoc.update_doc(server, fn doc ->
        frag = Doc.get_xml_fragment(doc, "xml")
        {:ok, xml_text} = XmlFragment.fetch(frag, 0)
        XmlText.format(xml_text, 0, 10, %{"href" => "https://github.com"})
      end)
    end
  },
  before_scenario: fn _ ->
    {:ok, server} =
      SharedDoc.start_link(doc_name: random_doc_name.(), auto_exit: false)

    SharedDoc.update_doc(server, fn doc ->
      frag = Doc.get_xml_fragment(doc, "xml")
      XmlFragment.push(frag, XmlTextPrelim.from(""))
      {:ok, xml_text} = XmlFragment.fetch(frag, 0)
      XmlText.insert(xml_text, 0, String.duplicate("x", 20))
    end)

    %{server: server}
  end,
  after_scenario: fn %{server: server} ->
    GenServer.stop(server, :normal, :infinity)
  end,
  memory_time: 2,
  time: 5
)

IO.puts("\n=== SharedDoc (DocServer) — XmlText read ===\n")

Benchee.run(
  %{
    "SharedDoc.update_doc/2 — XmlText.to_delta/1" => fn %{server: server} ->
      SharedDoc.update_doc(server, fn doc ->
        frag = Doc.get_xml_fragment(doc, "xml")
        {:ok, xml_text} = XmlFragment.fetch(frag, 0)
        XmlText.to_delta(xml_text)
      end)
    end,
    "SharedDoc.update_doc/2 — XmlText.to_string/1" => fn %{server: server} ->
      SharedDoc.update_doc(server, fn doc ->
        frag = Doc.get_xml_fragment(doc, "xml")
        {:ok, xml_text} = XmlFragment.fetch(frag, 0)
        XmlText.to_string(xml_text)
      end)
    end
  },
  before_scenario: fn _ ->
    {:ok, server} =
      SharedDoc.start_link(doc_name: random_doc_name.(), auto_exit: false)

    SharedDoc.update_doc(server, fn doc ->
      frag = Doc.get_xml_fragment(doc, "xml")
      XmlFragment.push(frag, XmlTextPrelim.from(""))
      {:ok, xml_text} = XmlFragment.fetch(frag, 0)
      XmlText.insert(xml_text, 0, String.duplicate("a", 500))
      XmlText.format(xml_text, 0, 100, %{"bold" => true})
    end)

    %{server: server}
  end,
  after_scenario: fn %{server: server} ->
    GenServer.stop(server, :normal, :infinity)
  end,
  memory_time: 2,
  time: 5
)
