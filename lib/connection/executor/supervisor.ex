defmodule Ravix.Connection.RequestExecutor.Supervisor do
  use DynamicSupervisor

  alias Ravix.Connection.{RequestExecutor, ServerNode, Topology}

  @spec init(any) ::
          {:ok,
           %{
             extra_arguments: list,
             intensity: non_neg_integer,
             max_children: :infinity | non_neg_integer,
             period: pos_integer,
             strategy: :one_for_one
           }}
  def init(init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [init_arg]
    )
  end

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(store) do
    DynamicSupervisor.start_link(__MODULE__, %{}, name: supervisor_name(store))
  end

  @spec register_node_executor(any, ServerNode.t()) ::
          :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
  def register_node_executor(store, %ServerNode{} = node) do
    DynamicSupervisor.start_child(supervisor_name(store), {RequestExecutor, node})
  end

  @spec fetch_nodes(any) :: list(pid())
  def fetch_nodes(store) do
    DynamicSupervisor.which_children(supervisor_name(store))
    |> Enum.map(fn {_, pid, _kind, _modules} -> pid end)
  end

  @spec update_topology(any, Ravix.Connection.Topology.t()) :: [
          {:new_nodes, list} | {:updated_nodes, list}
        ]
  def update_topology(store, %Topology{} = topology) do
    existing_nodes =
      fetch_nodes(store)
      |> Enum.map(fn pid -> RequestExecutor.fetch_node_state(pid) end)
      |> Enum.filter(fn response -> elem(response, 0) == :ok end)
      |> Enum.map(fn {:ok, node} -> node end)

    updated_nodes = update_existing_nodes(existing_nodes, topology)
    new_nodes = add_new_nodes(store, existing_nodes, topology)

    [updated_nodes: updated_nodes, new_nodes: new_nodes]
  end

  defp update_existing_nodes(nodes, %Topology{} = topology) do
    nodes
    |> Enum.map(fn node ->
      [
        url: node.url,
        database: node.database,
        cluster_tag: Topology.cluster_tag_for_node(topology, node.url)
      ]
    end)
    |> Enum.map(fn [url: url, database: database, cluster_tag: cluster_tag] ->
      %{url: url, updated: RequestExecutor.update_cluster_tag(url, database, cluster_tag)}
    end)
  end

  defp add_new_nodes(store, existing_nodes, %Topology{} = topology) do
    existing_nodes_urls = Enum.map(existing_nodes, fn node -> node.url end)

    topology.nodes
    |> Enum.reject(fn node -> Enum.member?(existing_nodes_urls, node.url) end)
    |> Enum.map(fn new_node ->
      RequestExecutor.Supervisor.register_node_executor(store, new_node)
    end)
  end

  defp supervisor_name(store) do
    :"#{store}.Executor"
  end
end