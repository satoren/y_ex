defmodule Yex.YjsCompatTest do
  # Exchanges documents, updates and protocol messages with the real Yjs (run on Node.js
  # by Yex.Yjs) and checks that both sides read the same data.
  use ExUnit.Case

  alias Yex.{
    Array,
    ArrayPrelim,
    Awareness,
    Buffer,
    Doc,
    Map,
    MapPrelim,
    StickyIndex,
    Sync,
    Text,
    TextPrelim,
    XmlElementPrelim,
    XmlFragment,
    XmlTextPrelim,
    Yjs
  }

  @moduletag :yjs

  setup_all do
    {:ok, bridge: start_supervised!(Yjs)}
  end

  setup %{bridge: bridge} do
    Yjs.reset!(bridge)
  end

  defp new_doc(client_id, opts \\ []) do
    Doc.with_options(struct!(Doc.Options, [client_id: client_id] ++ opts))
  end

  defp bytes(binary), do: {:bytes, binary}

  # Loads `update` into a fresh Yjs doc and returns what `code` returns, with the doc as `d`.
  defp in_yjs(bridge, update, code, args \\ %{}) do
    Yjs.eval!(
      bridge,
      "const d = new Y.Doc(); Y.applyUpdate(d, args.update);\n" <> code,
      Elixir.Map.put(args, :update, bytes(update))
    )
  end

  defp from_yjs(bridge, code, args \\ %{}) do
    update = Yjs.eval!(bridge, code, args)
    doc = Doc.new()
    :ok = Yex.apply_update(doc, update)
    doc
  end

  describe "values" do
    @values %{
      "int" => 42,
      "negative" => -7,
      "int32_max" => 2_147_483_647,
      "safe_integer" => 9_007_199_254_740_991,
      "float" => 1.5,
      "negative_float" => -0.25,
      "true" => true,
      "false" => false,
      "nil" => nil,
      "string" => "héllo, 世界 😀",
      "empty_string" => "",
      "list" => [1, "a", true, nil, [2.5], %{"k" => "v"}],
      "object" => %{"nested" => %{"deep" => [1, 2, 3]}, "empty" => %{}}
    }

    test "y_ex values read the same in Yjs", %{bridge: bridge} do
      doc = new_doc(1)
      map = Doc.get_map(doc, "map")
      Enum.each(@values, fn {key, value} -> Map.set(map, key, value) end)
      Map.set(map, "bytes", Buffer.from(<<0, 1, 2, 255>>))

      result =
        in_yjs(bridge, Yex.encode_state_as_update!(doc), ~S"""
        const map = d.getMap('map')
        return { json: map.toJSON(), bytesIsUint8Array: map.get('bytes') instanceof Uint8Array }
        """)

      assert result["json"] == Elixir.Map.put(@values, "bytes", <<0, 1, 2, 255>>)
      assert result["bytesIsUint8Array"]
    end

    test "Yjs values read the same in y_ex", %{bridge: bridge} do
      doc =
        from_yjs(
          bridge,
          ~S"""
          const d = new Y.Doc()
          const map = d.getMap('map')
          for (const [key, value] of Object.entries(args.values)) map.set(key, value)
          map.set('bytes', new Uint8Array([0, 1, 2, 255]))
          map.set('bigint', 2n ** 62n)
          return Y.encodeStateAsUpdate(d)
          """,
          %{values: @values}
        )

      map = Doc.get_map(doc, "map")

      # JavaScript has one number type, so Yjs numbers read back as floats. `==` treats
      # 42 and 42.0 as equal, also inside lists and maps.
      assert Map.to_json(map) |> Elixir.Map.drop(["bytes", "bigint"]) == @values
      assert Map.fetch!(map, "int") === 42.0
      assert Map.fetch!(map, "bytes") == Buffer.from(<<0, 1, 2, 255>>)
      assert Map.fetch!(map, "bigint") === 2 ** 62
    end
  end

  describe "shared types" do
    test "nested types written by y_ex", %{bridge: bridge} do
      doc = new_doc(1)
      map = Doc.get_map(doc, "map")
      Map.set(map, "array", ArrayPrelim.from([1, MapPrelim.from(%{"a" => "b"})]))
      Map.set(map, "text", TextPrelim.from("text"))
      array = Doc.get_array(doc, "array")
      Array.insert_list(array, 0, ["x", "y", "z"])
      Array.delete(array, 1)
      Array.push(array, ArrayPrelim.from([TextPrelim.from("inner")]))

      result =
        in_yjs(bridge, Yex.encode_state_as_update!(doc), ~S"""
        const map = d.getMap('map')
        return {
          map: map.toJSON(),
          array: d.getArray('array').toJSON(),
          types: [map.get('array') instanceof Y.Array, map.get('array').get(1) instanceof Y.Map,
                  map.get('text') instanceof Y.Text, d.getArray('array').get(2).get(0) instanceof Y.Text]
        }
        """)

      assert result["map"] == %{"array" => [1, %{"a" => "b"}], "text" => "text"}
      assert result["array"] == ["x", "z", ["inner"]]
      assert result["types"] == [true, true, true, true]
    end

    test "nested types written by Yjs", %{bridge: bridge} do
      doc =
        from_yjs(bridge, ~S"""
        const d = new Y.Doc()
        const map = d.getMap('map')
        const array = map.set('array', new Y.Array())
        array.insert(0, ['a', 'b', 'c'])
        array.delete(0, 1)
        const inner = new Y.Map()
        array.push([inner])
        inner.set('text', new Y.Text('hello'))
        map.set('deleted', 'value')
        map.delete('deleted')
        return Y.encodeStateAsUpdate(d)
        """)

      map = Doc.get_map(doc, "map")
      assert %{"array" => ["b", "c", %{"text" => "hello"}]} == Map.to_json(map)
      assert %Array{} = array = Map.fetch!(map, "array")
      assert %Map{} = inner = Array.fetch!(array, 2)
      assert %Text{} = Map.fetch!(inner, "text")
    end

    test "formatted text and embeds round trip", %{bridge: bridge} do
      doc = new_doc(1)
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "Hello World")
      Text.format(text, 0, 5, %{"bold" => true})
      Text.format(text, 6, 5, %{"link" => %{"href" => "https://example.com"}})
      Text.insert_embed(text, 11, %{"image" => "cat.png"}, %{"width" => 100})
      Text.delete(text, 5, 1)

      expected = [
        %{"insert" => "Hello", "attributes" => %{"bold" => true}},
        %{"insert" => "World", "attributes" => %{"link" => %{"href" => "https://example.com"}}},
        %{"insert" => %{"image" => "cat.png"}, "attributes" => %{"width" => 100}}
      ]

      assert in_yjs(
               bridge,
               Yex.encode_state_as_update!(doc),
               "return d.getText('text').toDelta()"
             ) ==
               expected

      doc =
        from_yjs(
          bridge,
          ~S"""
          const d = new Y.Doc()
          d.getText('text').applyDelta(args.delta)
          return Y.encodeStateAsUpdate(d)
          """,
          %{delta: expected}
        )

      assert Text.to_delta(Doc.get_text(doc, "text")) ==
               Enum.map(expected, fn op ->
                 %{insert: op["insert"], attributes: op["attributes"]}
               end)
    end

    test "text indexes count UTF-16 code units with offset_kind: :utf16", %{bridge: bridge} do
      doc = new_doc(1, offset_kind: :utf16)
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "a😀b")
      # 3 is after the emoji (a surrogate pair) in UTF-16, as in Yjs.
      Text.insert(text, 3, "X")
      update = Yex.encode_state_as_update!(doc)

      assert in_yjs(bridge, update, ~S"""
             const text = d.getText('text')
             text.insert(5, '!')
             return [text.toString(), text.length]
             """) == ["a😀Xb!", 6]

      js =
        Yjs.eval!(
          bridge,
          ~S"""
          const d = new Y.Doc(); d.clientID = 2
          Y.applyUpdate(d, args.update)
          d.getText('text').insert(1, 'Y')
          return Y.encodeStateAsUpdate(d, args.sv)
          """,
          %{update: bytes(update), sv: bytes(Yex.encode_state_vector!(doc))}
        )

      :ok = Yex.apply_update(doc, js)
      assert Text.to_string(text) == "aY😀Xb"
      assert Text.length(text) == 6
    end

    test "xml written by y_ex", %{bridge: bridge} do
      doc = new_doc(1)
      fragment = Doc.get_xml_fragment(doc, "xml")

      XmlFragment.push(
        fragment,
        XmlElementPrelim.new("p", [XmlTextPrelim.from("hello "), XmlElementPrelim.empty("br")], %{
          "class" => "intro"
        })
      )

      XmlFragment.push(fragment, XmlTextPrelim.from("tail"))
      update = Yex.encode_state_as_update!(doc)

      result =
        in_yjs(bridge, update, ~S"""
        const xml = d.getXmlFragment('xml')
        const p = xml.get(0)
        return { string: xml.toString(), tag: p.nodeName, class: p.getAttribute('class'),
                 text: p.get(0) instanceof Y.XmlText }
        """)

      assert result == %{
               "string" => ~s(<p class="intro">hello <br></br></p>tail),
               "tag" => "p",
               "class" => "intro",
               "text" => true
             }

      assert result["string"] == XmlFragment.to_string(fragment)
    end

    test "xml written by Yjs", %{bridge: bridge} do
      doc =
        from_yjs(bridge, ~S"""
        const d = new Y.Doc()
        const xml = d.getXmlFragment('xml')
        const p = new Y.XmlElement('p')
        p.setAttribute('class', 'intro')
        const text = new Y.XmlText()
        p.insert(0, [text, new Y.XmlElement('br')])
        text.insert(0, 'hello', { bold: true })
        xml.insert(0, [p, new Y.XmlText('tail')])
        return Y.encodeStateAsUpdate(d)
        """)

      fragment = Doc.get_xml_fragment(doc, "xml")

      assert XmlFragment.to_string(fragment) ==
               ~s(<p class="intro"><bold>hello</bold><br></br></p>tail)

      assert {:ok, p} = XmlFragment.fetch(fragment, 0)
      assert Yex.XmlElement.get_tag(p) == "p"
      assert Yex.XmlElement.get_attribute(p, "class") == "intro"
    end

    test "a document from a Yjs editor (BlockNote) reads the same", %{bridge: bridge} do
      update = File.read!(Path.expand("test_data/blocknote_data.bin", __DIR__))
      doc = Doc.new()
      :ok = Yex.apply_update(doc, update)

      fragment = Doc.get_xml_fragment(doc, "document-store")

      # toString differs on purpose (Yjs lowercases tags and sorts attributes), so compare
      # the trees: tags, attributes and the formatted text inside.
      js =
        in_yjs(bridge, update, ~S"""
        const tree = (node) => node instanceof Y.XmlText
          ? { delta: node.toDelta() }
          : { tag: node.nodeName ?? null, attributes: node instanceof Y.XmlElement ? node.getAttributes() : {},
              children: node.toArray().map(tree) }
        return tree(d.getXmlFragment('document-store'))
        """)

      assert js == xml_tree(fragment)
      assert js["children"] != []
    end

    test "subdocuments", %{bridge: bridge} do
      doc = new_doc(1)
      subdoc = Doc.with_options(%Doc.Options{guid: "sub-guid", auto_load: true})
      Map.set(Doc.get_map(doc, "docs"), "child", subdoc)

      assert in_yjs(bridge, Yex.encode_state_as_update!(doc), ~S"""
             const child = d.getMap('docs').get('child')
             return [child instanceof Y.Doc, child.guid, child.autoLoad, [...d.getSubdocGuids()]]
             """) == [true, "sub-guid", true, ["sub-guid"]]

      doc =
        from_yjs(bridge, ~S"""
        const d = new Y.Doc()
        d.getMap('docs').set('child', new Y.Doc({ guid: 'js-guid', meta: { kind: 'note' } }))
        return Y.encodeStateAsUpdate(d)
        """)

      assert %Doc{} = child = Map.fetch!(Doc.get_map(doc, "docs"), "child")
      assert Doc.guid(child) == "js-guid"
    end
  end

  describe "updates" do
    test "a full update survives a round trip byte for byte", %{bridge: bridge} do
      doc = new_doc(1)
      Text.insert(Doc.get_text(doc, "text"), 0, "hello")
      Array.push(Doc.get_array(doc, "array"), "a")
      Map.set(Doc.get_map(doc, "map"), "k", "v")
      Text.delete(Doc.get_text(doc, "text"), 1, 2)
      update = Yex.encode_state_as_update!(doc)

      assert in_yjs(bridge, update, "return Y.encodeStateAsUpdate(d)") == update

      assert in_yjs(bridge, update, "return Y.encodeStateVector(d)") ==
               Yex.encode_state_vector!(doc)
    end

    test "v2 updates", %{bridge: bridge} do
      doc = new_doc(1)
      Text.insert(Doc.get_text(doc, "text"), 0, "hello")
      Map.set(Doc.get_map(doc, "map"), "k", [1, 2])
      {:ok, update_v2} = Yex.encode_state_as_update_v2(doc)

      assert Yjs.eval!(
               bridge,
               ~S"""
               const d = new Y.Doc()
               Y.applyUpdateV2(d, args.update)
               return [d.getText('text').toString(), d.getMap('map').toJSON()]
               """,
               %{update: bytes(update_v2)}
             ) == ["hello", %{"k" => [1, 2]}]

      js_v2 =
        Yjs.eval!(bridge, ~S"""
        const d = new Y.Doc()
        d.getText('text').insert(0, 'from yjs')
        d.getArray('array').insert(0, [1, 'two'])
        return Y.encodeStateAsUpdateV2(d)
        """)

      doc = Doc.new()
      :ok = Yex.apply_update_v2(doc, js_v2)
      assert Text.to_string(Doc.get_text(doc, "text")) == "from yjs"
      assert Array.to_json(Doc.get_array(doc, "array")) == [1, "two"]

      {:ok, v1} = Yex.convert_update_format_v2_to_v1(js_v2)

      assert Yjs.eval!(bridge, "return Y.convertUpdateFormatV2ToV1(args.update)", %{
               update: bytes(js_v2)
             }) == v1
    end

    test "update utilities agree with Yjs", %{bridge: bridge} do
      updates =
        Yjs.eval!(bridge, ~S"""
        const d = new Y.Doc(); d.clientID = 7
        const updates = []
        d.on('update', (update) => updates.push(update))
        const text = d.getText('text')
        text.insert(0, 'abc')
        text.insert(3, 'def')
        text.delete(1, 2)
        d.getMap('map').set('k', 'v')
        return updates
        """)

      {:ok, merged} = Yex.merge_updates(updates)

      result =
        Yjs.eval!(
          bridge,
          ~S"""
          const merged = Y.mergeUpdates(args.updates)
          const sv = Y.encodeStateVectorFromUpdate(merged)
          const d = new Y.Doc(); Y.applyUpdate(d, args.merged)
          const partial = new Y.Doc(); Y.applyUpdate(partial, args.updates[0])
          return {
            merged, sv, text: d.getText('text').toString(),
            diff: Y.diffUpdate(merged, Y.encodeStateVector(partial)),
            meta: Y.parseUpdateMeta(merged)
          }
          """,
          %{updates: Enum.map(updates, &bytes/1), merged: bytes(merged)}
        )

      assert result["merged"] == merged
      assert result["text"] == "adef"
      assert {:ok, result["sv"]} == Yex.encode_state_vector_from_update(merged)

      partial = Doc.new()
      :ok = Yex.apply_update(partial, hd(updates))
      assert {:ok, result["diff"]} == Yex.diff_update(merged, Yex.encode_state_vector!(partial))

      assert {:ok, %{from: from, to: to}} = Yex.parse_update_meta(merged)
      assert %{"from" => %{"7" => 0}, "to" => %{"7" => 7}} == result["meta"]
      assert {from, to} == {%{7 => 0}, %{7 => 7}}
    end

    test "snapshots encode the state Yjs sees at that time", %{bridge: bridge} do
      doc = new_doc(1, skip_gc: true)
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "before")
      {:ok, snapshot} = Yex.snapshot(doc)
      Text.insert(text, 6, " after")
      Text.delete(text, 0, 1)
      {:ok, state} = Yex.Snapshot.encode_state_v1(snapshot)

      assert in_yjs(bridge, state, "return d.getText('text').toString()") == "before"
    end
  end

  describe "concurrent editing" do
    test "concurrent edits converge to the same document", %{bridge: bridge} do
      doc = new_doc(1)
      Text.insert(Doc.get_text(doc, "text"), 0, "base")
      Array.insert_list(Doc.get_array(doc, "array"), 0, [1, 2, 3])
      base = Yex.encode_state_as_update!(doc)

      Yjs.eval!(
        bridge,
        ~S"""
        ctx.doc = new Y.Doc(); ctx.doc.clientID = 2
        Y.applyUpdate(ctx.doc, args.base)
        ctx.doc.getText('text').insert(0, 'js:')
        ctx.doc.getText('text').delete(5, 2)
        ctx.doc.getArray('array').insert(1, ['js'])
        ctx.doc.getMap('map').set('k', 'js')
        """,
        %{base: bytes(base)}
      )

      Text.insert(Doc.get_text(doc, "text"), 4, ":ex")
      Array.delete(Doc.get_array(doc, "array"), 1)
      Array.push(Doc.get_array(doc, "array"), "ex")
      Map.set(Doc.get_map(doc, "map"), "k", "ex")

      # Exchange only what each side is missing, as a provider would.
      js_diff =
        Yjs.eval!(bridge, "return Y.encodeStateAsUpdate(ctx.doc, args.sv)", %{
          sv: bytes(Yex.encode_state_vector!(doc))
        })

      js_sv = Yjs.eval!(bridge, "return Y.encodeStateVector(ctx.doc)")
      ex_diff = Yex.encode_state_as_update!(doc, js_sv)
      :ok = Yex.apply_update(doc, js_diff)

      js =
        Yjs.eval!(
          bridge,
          ~S"""
          Y.applyUpdate(ctx.doc, args.diff)
          return {
            text: ctx.doc.getText('text').toString(),
            array: ctx.doc.getArray('array').toJSON(),
            map: ctx.doc.getMap('map').toJSON(),
            state: Y.encodeStateAsUpdate(ctx.doc),
            sv: Y.encodeStateVector(ctx.doc)
          }
          """,
          %{diff: bytes(ex_diff)}
        )

      assert js["text"] == Text.to_string(Doc.get_text(doc, "text"))
      assert js["array"] == Array.to_json(Doc.get_array(doc, "array"))
      assert js["map"] == Map.to_json(Doc.get_map(doc, "map"))
      # The higher client id wins a concurrent map write in both implementations.
      assert js["map"] == %{"k" => "js"}
      # Yjs writes clients in descending order and yrs in no fixed order, so compare the
      # decoded state vectors and the documents rebuilt from each side's full state.
      assert Yex.decode_state_vector(js["sv"]) ==
               Yex.decode_state_vector(Yex.encode_state_vector!(doc))

      rebuilt = Doc.new()
      :ok = Yex.apply_update(rebuilt, js["state"])
      assert Text.to_string(Doc.get_text(rebuilt, "text")) == js["text"]
    end

    test "random concurrent edits converge", %{bridge: bridge} do
      seed = :erlang.phash2(make_ref())
      :rand.seed(:exsss, seed)
      doc = new_doc(1, offset_kind: :utf16)

      Yjs.eval!(bridge, "ctx.doc = new Y.Doc(); ctx.doc.clientID = 2")

      for round <- 1..20 do
        Enum.each(1..5, fn _ -> random_edit(doc) end)

        Yjs.eval!(
          bridge,
          ~S"""
          let seed = args.seed
          const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
          const pick = (n) => Math.floor(random() * n)
          const text = ctx.doc.getText('text'), array = ctx.doc.getArray('array'), map = ctx.doc.getMap('map')
          for (let i = 0; i < 5; i++) {
            switch (pick(5)) {
              case 0: text.insert(pick(text.length + 1), ['x', 'yz', '世', 'é'][pick(4)]); break
              case 1: if (text.length > 0) { const at = pick(text.length); text.delete(at, Math.min(2, text.length - at)) } break
              case 2: array.insert(pick(array.length + 1), [pick(100)]); break
              case 3: if (array.length > 0) array.delete(pick(array.length)); break
              case 4: map.set('k' + pick(4), pick(100)); break
            }
          }
          """,
          %{seed: seed + round}
        )

        js_diff =
          Yjs.eval!(bridge, "return Y.encodeStateAsUpdate(ctx.doc, args.sv)", %{
            sv: bytes(Yex.encode_state_vector!(doc))
          })

        ex_diff =
          Yex.encode_state_as_update!(
            doc,
            Yjs.eval!(bridge, "return Y.encodeStateVector(ctx.doc)")
          )

        :ok = Yex.apply_update(doc, js_diff)

        js =
          Yjs.eval!(
            bridge,
            ~S"""
            Y.applyUpdate(ctx.doc, args.diff)
            return [ctx.doc.getText('text').toString(), ctx.doc.getArray('array').toJSON(), ctx.doc.getMap('map').toJSON()]
            """,
            %{diff: bytes(ex_diff)}
          )

        assert js == [
                 Text.to_string(Doc.get_text(doc, "text")),
                 Array.to_json(Doc.get_array(doc, "array")),
                 Map.to_json(Doc.get_map(doc, "map"))
               ],
               "diverged in round #{round} (seed #{seed})"
      end
    end
  end

  defp xml_tree(%Yex.XmlText{} = text) do
    %{"delta" => Enum.map(Yex.XmlText.to_delta(text), &delta_op/1)}
  end

  defp xml_tree(%Yex.XmlElement{} = element) do
    %{
      "tag" => Yex.XmlElement.get_tag(element),
      "attributes" => Yex.XmlElement.get_attributes(element),
      "children" => Enum.map(Yex.XmlElement.children(element), &xml_tree/1)
    }
  end

  defp xml_tree(%XmlFragment{} = fragment) do
    %{
      "tag" => nil,
      "attributes" => %{},
      "children" => Enum.map(XmlFragment.children(fragment), &xml_tree/1)
    }
  end

  defp delta_op(op) do
    Elixir.Map.new(op, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  # Only characters inside the BMP: deleting half of a surrogate pair is covered by
  # neither implementation the same way, and the UTF-16 test above covers indexes.
  defp random_edit(doc) do
    text = Doc.get_text(doc, "text")
    array = Doc.get_array(doc, "array")
    len = Text.length(text)
    alen = Array.length(array)

    case :rand.uniform(5) do
      1 ->
        Text.insert(text, :rand.uniform(len + 1) - 1, Enum.random(["a", "bc", "界", "ü"]))

      2 when len > 0 ->
        at = :rand.uniform(len) - 1
        Text.delete(text, at, min(2, len - at))

      3 ->
        Array.insert(array, :rand.uniform(alen + 1) - 1, :rand.uniform(100))

      4 when alen > 0 ->
        Array.delete(array, :rand.uniform(alen) - 1)

      5 ->
        Map.set(Doc.get_map(doc, "map"), "k#{:rand.uniform(4) - 1}", :rand.uniform(100))

      _ ->
        :ok
    end
  end

  describe "y-protocols" do
    test "sync handshake with a y-protocols peer", %{bridge: bridge} do
      doc = new_doc(1)
      Text.insert(Doc.get_text(doc, "text"), 0, "from y_ex")

      # Yjs opens with sync step 1.
      step1 =
        Yjs.eval!(bridge, ~S"""
        ctx.doc = new Y.Doc(); ctx.doc.clientID = 2
        ctx.doc.getArray('array').insert(0, ['from yjs'])
        const encoder = encoding.createEncoder()
        encoding.writeVarUint(encoder, 0) // messageSync
        syncProtocol.writeSyncStep1(encoder, ctx.doc)
        return encoding.toUint8Array(encoder)
        """)

      assert {:ok, {:sync, {:sync_step1, _} = message}} = Sync.message_decode(step1)
      {:ok, step2} = Sync.read_sync_message(message, doc, :remote)
      {:ok, ex_step1} = Sync.get_sync_step1(doc)

      replies =
        Enum.map([step2, ex_step1], &Sync.message_encode!({:sync, &1}))
        |> Enum.map(&bytes/1)

      # Yjs answers our step 1 with its step 2.
      [js_step2] =
        Yjs.eval!(
          bridge,
          ~S"""
          const out = []
          for (const message of args.messages) {
            const decoder = decoding.createDecoder(message)
            if (decoding.readVarUint(decoder) !== 0) throw new Error('not a sync message')
            const encoder = encoding.createEncoder()
            encoding.writeVarUint(encoder, 0)
            syncProtocol.readSyncMessage(decoder, encoder, ctx.doc, 'y_ex')
            if (encoding.length(encoder) > 1) out.push(encoding.toUint8Array(encoder))
          }
          return out
          """,
          %{messages: replies}
        )

      assert {:ok, {:sync, {:sync_step2, _} = message}} = Sync.message_decode(js_step2)
      :ok = Sync.read_sync_message(message, doc, :remote)

      # Later edits travel as sync updates in both directions.
      js_update =
        Yjs.eval!(bridge, ~S"""
        let message
        ctx.doc.once('update', (update) => {
          const encoder = encoding.createEncoder()
          encoding.writeVarUint(encoder, 0)
          syncProtocol.writeUpdate(encoder, update)
          message = encoding.toUint8Array(encoder)
        })
        ctx.doc.getMap('map').set('k', 'v')
        return message
        """)

      assert {:ok, {:sync, {:sync_update, _} = message}} = Sync.message_decode(js_update)
      :ok = Sync.read_sync_message(message, doc, :remote)

      {:ok, _} = Doc.monitor_update(doc)
      Array.push(Doc.get_array(doc, "array"), "later")
      assert_receive {:update_v1, ex_update, _origin, _doc}

      result =
        Yjs.eval!(
          bridge,
          ~S"""
          const decoder = decoding.createDecoder(args.message)
          decoding.readVarUint(decoder)
          syncProtocol.readSyncMessage(decoder, encoding.createEncoder(), ctx.doc, 'y_ex')
          return { text: ctx.doc.getText('text').toString(), array: ctx.doc.getArray('array').toJSON(),
                   map: ctx.doc.getMap('map').toJSON(), sv: Y.encodeStateVector(ctx.doc) }
          """,
          %{message: bytes(Sync.message_encode!({:sync, {:sync_update, ex_update}}))}
        )

      assert result == %{
               "text" => "from y_ex",
               "array" => ["from yjs", "later"],
               "map" => %{"k" => "v"},
               "sv" => result["sv"]
             }

      assert Yex.decode_state_vector(result["sv"]) ==
               Yex.decode_state_vector(Yex.encode_state_vector!(doc))

      assert Array.to_json(Doc.get_array(doc, "array")) == ["from yjs", "later"]
      assert Map.to_json(Doc.get_map(doc, "map")) == %{"k" => "v"}
    end

    test "awareness updates", %{bridge: bridge} do
      {:ok, awareness} = Awareness.new(new_doc(1))
      Awareness.set_local_state(awareness, %{"user" => %{"name" => "elixir", "color" => "#f00"}})
      {:ok, update} = Awareness.encode_update(awareness)

      js =
        Yjs.eval!(
          bridge,
          ~S"""
          const d = new Y.Doc(); d.clientID = 2
          ctx.awareness = new awarenessProtocol.Awareness(d)
          ctx.awareness.setLocalState({ user: { name: 'js', color: '#0f0' }, cursor: null })
          awarenessProtocol.applyAwarenessUpdate(ctx.awareness, args.update, 'y_ex')
          return {
            states: ctx.awareness.getStates(),
            update: awarenessProtocol.encodeAwarenessUpdate(ctx.awareness, [2])
          }
          """,
          %{update: bytes(update)}
        )

      assert js["states"] == %{
               "1" => %{"user" => %{"name" => "elixir", "color" => "#f00"}},
               "2" => %{"user" => %{"name" => "js", "color" => "#0f0"}, "cursor" => nil}
             }

      :ok = Awareness.apply_update(awareness, js["update"])

      assert Awareness.get_states(awareness) == %{
               1 => %{"user" => %{"name" => "elixir", "color" => "#f00"}},
               2 => %{"user" => %{"name" => "js", "color" => "#0f0"}, "cursor" => nil}
             }

      # The awareness message of the y-websocket protocol wraps the same update.
      message =
        Yjs.eval!(bridge, ~S"""
        ctx.awareness.setLocalStateField('cursor', { anchor: 3 })
        const encoder = encoding.createEncoder()
        encoding.writeVarUint(encoder, 1) // messageAwareness
        encoding.writeVarUint8Array(encoder, awarenessProtocol.encodeAwarenessUpdate(ctx.awareness, [2]))
        return encoding.toUint8Array(encoder)
        """)

      assert {:ok, {:awareness, update}} = Sync.message_decode(message)
      :ok = Awareness.apply_update(awareness, update)
      assert Awareness.get_states(awareness)[2]["cursor"] == %{"anchor" => 3}

      # Removing a state reaches the other side as well.
      Awareness.monitor_update(awareness)
      Awareness.clean_local_state(awareness)
      assert_receive {:awareness_update, %{removed: [1]}, _origin, _awareness}
      {:ok, update} = Awareness.encode_update(awareness, [1])

      assert Yjs.eval!(
               bridge,
               ~S"""
               awarenessProtocol.applyAwarenessUpdate(ctx.awareness, args.update, 'y_ex')
               return [...ctx.awareness.getStates().keys()]
               """,
               %{update: bytes(update)}
             ) == [2]
    end
  end

  describe "sticky indexes" do
    test "relative positions created by y_ex resolve the same in Yjs", %{bridge: bridge} do
      doc = new_doc(1)
      text = Doc.get_text(doc, "text")
      Text.insert(text, 0, "hello world")
      after_index = StickyIndex.new(text, 6, :after)
      before_index = StickyIndex.new(text, 5, :before)
      {:ok, encoded_after} = StickyIndex.encode(after_index)

      result =
        in_yjs(
          bridge,
          Yex.encode_state_as_update!(doc),
          ~S"""
          const text = d.getText('text')
          text.insert(0, '>> ')
          const resolve = (rpos) => {
            const abs = Y.createAbsolutePositionFromRelativePosition(rpos, d)
            return [abs.index, abs.assoc]
          }
          return {
            binary: resolve(Y.decodeRelativePosition(args.encoded)),
            json: resolve(Y.createRelativePositionFromJSON(JSON.parse(args.json))),
            own: Y.encodeRelativePosition(Y.createRelativePositionFromTypeIndex(text, 9)),
            ownJson: JSON.stringify(Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(text, 8, -1))),
            update: Y.encodeStateAsUpdate(d)
          }
          """,
          %{encoded: bytes(encoded_after), json: StickyIndex.to_json(before_index)}
        )

      assert result["binary"] == [9, 0]
      assert result["json"] == [8, -1]

      :ok = Yex.apply_update(doc, result["update"])
      assert Text.to_string(text) == ">> hello world"

      assert {:ok, %{index: 9, assoc: :after}} =
               StickyIndex.get_offset(StickyIndex.decode(doc, result["own"]))

      assert {:ok, js_before} = StickyIndex.from_json(result["ownJson"], doc)
      assert {:ok, %{index: 8, assoc: :before}} = StickyIndex.get_offset(js_before)
    end
  end
end
