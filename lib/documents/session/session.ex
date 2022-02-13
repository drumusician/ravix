defmodule Ravix.Documents.Session do
  use GenServer

  require OK

  alias Ravix.Documents.Session
  alias Ravix.Documents.Session.SessionManager

  def init(session_state) do
    {:ok, session_state}
  end

  @spec start_link(any, Session.State.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_attr, initial_state = %Session.State{}) do
    GenServer.start_link(
      __MODULE__,
      initial_state,
      name: session_id(initial_state.session_id)
    )
  end

  @spec load(binary, binary() | list(binary()), list() | nil) :: any
  def load(session_id, ids, includes \\ nil)
  def load(_session_id, nil, _includes), do: {:error, :document_ids_not_informed}

  def load(session_id, ids, includes) when is_list(ids) do
    session_id
    |> session_id()
    |> GenServer.call({:load, [document_ids: ids, includes: includes]})
  end

  def load(session_id, id, includes) do
    session_id
    |> session_id()
    |> GenServer.call({:load, [document_ids: [id], includes: includes]})
  end

  def delete(session_id, entity) when is_map_key(entity, :id) do
    delete(session_id, entity.id)
  end

  def delete(session_id, id) when is_binary(id) do
    session_id
    |> session_id()
    |> GenServer.call({:delete, id})
  end

  @spec store(binary(), map(), binary() | nil, binary() | nil) :: any
  def store(session_id, entity, key \\ nil, change_vector \\ nil)

  def store(_session_id, entity, _key, _change_vector) when entity == nil,
    do: {:error, :null_entity}

  def store(session_id, entity, key, change_vector) do
    session_id
    |> session_id()
    |> GenServer.call({:store, [entity: entity, key: key, change_vector: change_vector]})
  end

  @spec save_changes(binary) :: any
  def save_changes(session_id) do
    session_id
    |> session_id()
    |> GenServer.call({:save_changes})
  end

  @spec fetch_state(binary()) :: Session.State.t()
  def fetch_state(session_id) do
    session_id
    |> session_id()
    |> GenServer.call({:fetch_state})
  end

  @spec session_id(String.t()) :: {:via, Registry, {:sessions, String.t()}}
  defp session_id(id) when id != nil, do: {:via, Registry, {:sessions, id}}

  ####################
  #     Handlers     #
  ####################

  def handle_call(
        {:load, [document_ids: ids, includes: includes]},
        _from,
        state = %Session.State{}
      ) do
    with {:ok, result} <- SessionManager.load_documents(state, ids, includes) do
      {:reply, {:ok, result[:response]}, result[:updated_state]}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call(
        {:store, [entity: entity, key: key, change_vector: change_vector]},
        _from,
        state = %Session.State{}
      )
      when key != nil,
      do: SessionManager.store_entity(state, entity, key, change_vector)

  def handle_call(
        {:store, [entity: entity, key: _, change_vector: change_vector]},
        _from,
        state = %Session.State{}
      )
      when entity.id != nil,
      do: SessionManager.store_entity(state, entity, entity.id, change_vector)

  def handle_call(
        {:store, [entity: _, key: _, change_vector: _]},
        _from,
        state = %Session.State{}
      ),
      do: {:reply, {:error, :no_valid_id_informed}, state}

  def handle_call({:fetch_state}, _from, state = %Session.State{}),
    do: {:reply, {:ok, state}, state}

  def handle_call({:save_changes}, _from, state = %Session.State{}) do
    with {:ok, response} <- SessionManager.save_changes(state) do
      {:reply, {:ok, response[:result]}, response[:updated_state]}
    else
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  def handle_call({:delete, id}, _from, state = %Session.State{}) do
    with {:ok, updated_state} <- SessionManager.delete_document(state, id) do
      {:reply, {:ok, id}, updated_state}
    else
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end
end