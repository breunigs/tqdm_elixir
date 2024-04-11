defmodule Tqdm.LimitedList do
  def new(limit), do: {:queue.new(), 0, limit}
  def push({q, limit, limit}, item), do: {:queue.in(item, q) |> :queue.drop(), limit, limit}
  def push({q, len, limit}, item), do: {:queue.in(item, q), len + 1, limit}

  def len({_q, len, _limit}), do: len

  def avg({_q, 0, _limit}), do: nil
  def avg({q, len, _limit}), do: (q |> :queue.to_list() |> Enum.sum()) / len
end
