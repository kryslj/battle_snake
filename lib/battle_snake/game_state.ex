defmodule BattleSnake.GameState do
  alias __MODULE__

  alias BattleSnake.World

  @max_history 20

  @statuses [:cont, :replay, :halted, :suspend]

  @typedoc """
  Any function that takes a GameState, and returns a new GameState.
  """
  @type state_fun :: (t -> t)
  @type state_predicate :: (t -> boolean)
  @type uuid :: binary
  @type snake_id :: uuid

  @typedoc """
  A function that, when true, indicates that the game is over.
  """
  @type objective_fun :: state_predicate

  @type t :: %GameState{
    world: World.t,
    objective: objective_fun,
    delay: non_neg_integer,
    hist: [World.t],
    game_form: BattleSnake.GameForm.t,
    winners: [snake_id]
  }

  defstruct([
    :world,
    :objective,
    :game_form_id,
    :snakes,
    game_form: {:error, :init},
    delay: 0,
    hist: [],
    status: :suspend,
    winners: [],
  ])

  @spec cont!(t) :: t
  def cont!(state) do
    put_in(state.status, :cont)
  end

  @spec cont?(t) :: t
  def cont?(state) do
    state.status == :cont
  end

  defoverridable("cont!": 1, "cont?": 1)

  @spec suspend!(t) :: t
  def suspend!(state) do
    put_in(state.status, :suspend)
  end

  @spec suspend?(t) :: t
  def suspend?(state) do
    state.status == :suspend
  end

  defoverridable("suspend!": 1, "suspend?": 1)

  @spec halted!(t) :: t
  def halted!(state) do
    put_in(state.status, :halted)
  end

  @spec halted?(t) :: t
  def halted?(state) do
    state.status == :halted
  end

  defoverridable("halted!": 1, "halted?": 1)

  @spec replay!(t) :: t
  def replay!(state) do
    put_in(state.status, :replay)
  end

  @spec replay?(t) :: t
  def replay?(state) do
    state.status == :replay
  end

  defmacrop is_replay(state) do
    quote do
      %__MODULE__{status: :replay} = unquote(state)
    end
  end

  defoverridable("replay!": 1, "replay?": 1)

  @spec done?(t) :: boolean
  def done?(state) do
    state.objective.(state.world)
  end

  def identity(x), do: x

  # TODO change :hist to {forward, backward} so that that
  # history is not lost when watching a replay
  def step(is_replay(state)) do
    case state.hist do
      [] ->
        halted!(state)

      [h|t] ->
        state = put_in(state.world, h)
        state = put_in(state.hist, t)
        state
    end
  end

  def step(state) do
    state
    |> save_history()
    |> BattleSnake.Movement.next()
    |> BattleSnake.Death.reap()
    |> Map.update!(:world, &World.step/1)
  end

  @doc "Loads the game history for a game matching this id"
  @spec load_history(t) :: t
  def load_history(state) do
    # TODO use qlc or something more efficient rather than sorting results here.
    hist =
      World
      |> :mnesia.dirty_index_read(state.game_form_id, :game_form_id)
      |> Enum.map(&Mnesia.Repo.load/1)
      |> Enum.sort_by((& Map.get &1, :turn))
    put_in(state.hist, hist)
  end

  def statuses, do: @statuses

  def step_back(%{hist: []} = s), do: s

  def step_back(state) do
    prev_turn(state)
  end

  def delay(state) do
    state.delay
  end

  def objective(state) do
    state.objective.(state.world)
  end

  defp prev_turn(state) do
    [h|t] = state.hist
    state = put_in state.world, h
    put_in(state.hist, t)
  end

  defp save_history(%{world: h} = state) do
    update_in state.hist, fn t ->
      [h |Enum.take(t, @max_history)]
    end
  end
end
