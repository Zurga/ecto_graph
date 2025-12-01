defmodule EctoGraphTest do
  use ExUnit.Case
  doctest EctoGraph

  test "new/1" do
    graph = EctoGraph.new([Person, Tag])
    assert graph.paths != []
    assert graph.join_modules != []
    assert graph.edge_fields != []
    assert EctoGraph.paths(graph, Person, Tag) == [{:all_tags, []}, {:favourite_tags, []}]
  end

  test "prewalk/3" do
    graph = EctoGraph.new([Person, Post, Tag, Label, PostsTags])
    tags = [%Tag{}, %Tag{}]
    person = %Person{all_tags: tags, posts: [%Post{tags: tags}]}

    paths = EctoGraph.paths(graph, Person, Tag)

    assert %Person{all_tags: [%Tag{name: "tag1"}, %Tag{name: "tag2"}]} =
             EctoGraph.prewalk(paths, person, fn _, tags, _ ->
               Enum.with_index(tags, 1)
               |> Enum.map(fn {tag, index} ->
                 %{tag | name: "tag#{index}"}
               end)
             end)
  end
end
