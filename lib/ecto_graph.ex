defmodule EctoGraph do
  @moduledoc false
  require Logger
  alias Ecto.Association.{HasThrough, ManyToMany, NotLoaded}

  defstruct ~w/paths join_modules has_through edge_fields/a

  def new(modules) do
    modules = Enum.filter(modules, &ecto_schema_mod?/1)
    join_modules = find_join_modules(modules)
    {edges, edge_fields} = find_edges(modules)
    graph = Graph.new() |> Graph.add_edges(edges)
    vertices = Graph.vertices(graph)

    paths =
      for v <- vertices, v2 <- vertices, reduce: %{} do
        acc ->
          if v != v2 and not is_nil(Graph.get_shortest_path(graph, v, v2)) do
            paths =
              Graph.get_paths(graph, v, v2)
              |> Enum.flat_map(&normalize_path(&1, join_modules, edge_fields, []))

            Map.put(acc, {v, v2}, paths)
          else
            acc
          end
      end

    %__MODULE__{paths: paths, join_modules: join_modules, edge_fields: edge_fields}
  end

  def paths(graph, from, to) do
    Map.get(graph.paths, {from, to}, [])
  end

  def get(value, path) do
    do_get(value, path)
    |> List.flatten()
  end

  defp do_get(nil, _), do: nil
  defp do_get(%NotLoaded{} = not_loaded, _), do: not_loaded
  defp do_get(values, {key, []}) when is_list(values), do: Enum.map(values, &Map.get(&1, key))
  defp do_get(value, {key, []}), do: Map.get(value, key)

  defp do_get(values, {key, nested}) when is_list(values),
    do: Enum.map(values, &do_get(Map.get(&1, key), nested))

  defp do_get(value, {key, nested}), do: do_get(Map.get(value, key), nested)
  defp do_get(value, keys) when is_list(keys), do: Enum.map(keys, &do_get(value, &1))

  def prewalk(paths, value, fun) when is_list(paths) do
    Enum.reduce(paths, value, &do_prewalk(&2, &1, fun))
  end

  defp do_prewalk(nil, _, _), do: nil

  defp do_prewalk(%NotLoaded{} = not_loaded, _, _), do: not_loaded

  defp do_prewalk(value, path, fun) when is_list(value) do
    Enum.map(value, &do_prewalk(&1, path, fun))
  end

  defp do_prewalk(%{__struct__: schema_mod} = value, {key, []}, fun) do
    Map.update!(value, key, fn
      %NotLoaded{} = not_loaded ->
        not_loaded

      associated ->
        assoc_info = schema_mod.__schema__(:association, key)
        fun.(value, associated, assoc_info)
    end)
  end

  defp do_prewalk(value, {key, nested}, fun) do
    Map.update!(value, key, &do_prewalk(&1, nested, fun))
  end

  defp do_prewalk(value, keys, fun) when is_list(keys) do
    Enum.reduce(keys, value, &do_prewalk(&2, &1, fun))
  end

  defp find_join_modules(modules) do
    modules
    |> Enum.reduce([], fn module, acc ->
      reduce_assocs(module, acc, fn
        {_, assoc}, acc ->
          case assoc do
            %ManyToMany{
              join_through: join_through,
              owner: from,
              related: to,
              join_keys: [{from_fk, _}, {to_fk, _}]
            } ->
              [
                {join_through,
                 %{
                   from => {to_fk, to},
                   to => {from_fk, from}
                 }}
                | acc
              ]

            _ ->
              acc
          end
      end)
    end)
    |> Enum.into(%{})
  end

  defp find_edges(modules) do
    modules
    |> Enum.reduce(
      {[], %{}},
      fn module, acc ->
        reduce_assocs(module, acc, fn {field, %{owner: from} = assoc}, {edge_acc, field_acc} ->
          {edges, related} =
            case assoc do
              %ManyToMany{
                join_through: join_through,
                related: related
              } ->
                edges =
                  if is_binary(join_through) do
                    [{from, join_through}, {join_through, from}]
                  else
                    [{from, join_through}]
                  end

                {edges, related}

              %HasThrough{through: through} ->
                to = resolve_through(module, through)

                {[{from, to}], to}

              %{related: to} ->
                {[{from, to}], to}
            end

          field_acc =
            Map.update(field_acc, {from, related}, [field], fn fields -> [field | fields] end)

          {edges ++ edge_acc, field_acc}
        end)
      end
    )
  end

  defp normalize_path([_], _, _, acc) do
    acc |> Enum.reverse() |> List.flatten()
  end

  defp normalize_path([parent, child], join_modules, edge_fields, acc) do
    child =
      (get_in(join_modules, [child, parent]) || child)
      |> case do
        {_, child} -> child
        child -> child
      end

    case Map.get(edge_fields, {parent, child}) do
      nil ->
        acc

      fields ->
        Enum.reduce(fields, acc, &Keyword.put(&2, &1, []))
    end
  end

  defp normalize_path([parent, join, child | rest], join_modules, edge_fields, acc) do
    {edge, next} =
      if Enum.member?(Map.keys(join_modules), join) do
        {{parent, child}, [child | rest]}
      else
        {{parent, join}, [join, child | rest]}
      end

    case Map.get(edge_fields, edge) do
      nil ->
        acc

      fields ->
        for field <- fields do
          # fav, posts
          Keyword.put(acc, field, normalize_path(next, join_modules, edge_fields, []))
        end
    end
  end

  defp ecto_schema_mod?(schema_mod) do
    schema_mod.__schema__(:fields)

    true
  rescue
    ArgumentError -> false
    UndefinedFunctionError -> false
  end

  defp reduce_assocs(schema_mod, acc, function)

  defp reduce_assocs(%NotLoaded{} = value, _acc, _function), do: value

  defp reduce_assocs(%{__struct__: schema_mod} = value, _acc, function)
       when is_function(function) do
    reduce_assocs(schema_mod, value, function)
  end

  defp reduce_assocs(schema_mod, acc, function) when is_function(function) do
    schema_mod.__schema__(:associations)
    |> Enum.reduce(acc, fn key, acc ->
      assoc_info = schema_mod.__schema__(:association, key)
      function.({key, assoc_info}, acc)
    end)
  end

  defp resolve_through(schema, []), do: schema

  defp resolve_through(schema, [key | rest]) do
    case schema.__schema__(:association, key) do
      %{related: related} ->
        resolve_through(related, rest)

      %Ecto.Association.HasThrough{through: through} ->
        resolve_through(schema, through)
    end
  end
end
