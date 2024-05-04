defmodule Tqdm do
  @moduledoc """
  Tqdm easily adds a CLI progress bar to any enumerable.

  Just wrap Lists, Maps, Streams, or anything else that implements Enumerable
  with `Tqdm.tqdm`:

      for _ <- Tqdm.tqdm(1..1000) do
        :timer.sleep(10)
      end

      # or

      1..1000
      |> Tqdm.tqdm()
      |> Enum.map(fn _ -> :timer.sleep(10) end)

      # or even...

      1..1000
      |> Stream.map(fn _ -> :timer.sleep(10) end)
      |> Tqdm.tqdm(total: 1000)
      |> Stream.run()

      # |###-------| 392/1000 39.0% [elapsed: 00:00:04.627479 \
  left: 00:00:07, 84.71 iters/sec]
  """

  # How many iteration times to keep for calculating the moving average.
  @max_iteration_times 250
  # Exponential smoothing factor. Smaller values increase recency bias.
  @iteration_time_smoothing 0.8

  @type option ::
          {:description, String.t()}
          | {:total, non_neg_integer}
          | {:clear, boolean}
          | {:device, IO.device()}
          | {:min_interval, non_neg_integer}
          | {:min_iterations, non_neg_integer}
          | {:total_segments, non_neg_integer}

  @type options :: [option]

  @doc """
  Wrap the given `enumerable` and print a CLI progress bar.

  `options` may be provided:

    * `:description` - a short string that is displayed on the progress bar.
      For example, if the string `"Processing values"` is provided for this
      option:

          # Processing values: |###-------| 349/1000 35.0% [elapsed: \
  00:00:06.501472 left: 00:00:12, 53.68 iters/sec]

    * `:total` - by default, `Tdqm` will use `Enum.count` to count how many
      elements are in the given `enumerable`. For large amounts of data, or
      streams, this may not be appropriate. You can provide your own total with
      this option. You may provide an estimate, and if the actual count
      exceeds this value, the progress bar will change to an indeterminate mode:

          # 296 [elapsed: 00:00:03.500038, 84.57 iters/sec]

      You can also force the indeterminate mode by passing `0`.

    * `:clear` - by default, `Tqdm` will clear the progress bar after the
      enumeration is complete. If you pass `false` for this option, the progress
      bar will persist, instead.

    * `:device` - by default, `Tqdm` writes to `:stderr`. You can provide any
      `IO.device` to this option to use it instead of the default.

    * `:min_interval` - by default, `Tqdm` will only print progress updates
      every 100ms. You can increase or decrease this value using this option.

    * `:min_iterations` - by default, `Tqdm` will check if the `:min_interval`
      has passed for every iteration. Passing a value for this option will skip
      this check until at least `:min_iterations` iterations have passed.

    * `:total_segments` - by default, `Tqdm` will split its progress bar into 10
      segments. You can customize this by passing a different value for this
      option.
  """
  @spec tqdm(Enumerable.t(), options) :: Enumerable.t()
  def tqdm(enumerable, options \\ []) do
    start_fun = fn ->
      now = System.monotonic_time()

      get_total = fn -> Enum.count(enumerable) end

      %{
        n: 0,
        last_print_n: 0,
        start_time: now,
        last_print_time: now,
        last_printed_length: 0,
        last_iteration_time: now,
        iteration_times: Tqdm.LimitedList.new(@max_iteration_times),
        time_per_iteration: nil,
        prefix: options |> Keyword.get(:description, "") |> prefix(),
        total: Keyword.get_lazy(options, :total, get_total),
        clear: Keyword.get(options, :clear, true),
        device: Keyword.get(options, :device, :stderr),
        min_interval:
          options
          |> Keyword.get(:min_interval, 100)
          |> System.convert_time_unit(:millisecond, :native),
        min_iterations: Keyword.get(options, :min_iterations, 1),
        total_segments: Keyword.get(options, :total_segments, 10)
      }
    end

    Stream.transform(enumerable, start_fun, &do_tqdm/2, &do_tqdm_after/1)
  end

  defp prefix(""), do: ""
  defp prefix(description), do: description <> ": "

  defp update_iteration_times(state, now \\ System.monotonic_time()) do
    delta = now - state.last_iteration_time

    %{
      state
      | iteration_times: Tqdm.LimitedList.push(state.iteration_times, delta),
        last_iteration_time: now
    }
  end

  defp do_tqdm(element, %{n: 0} = state) do
    now = System.monotonic_time()

    state =
      state
      |> estimate_time_per_iteration()
      |> print_status(now)
      |> update_iteration_times(now)

    {[element], %{state | n: 1}}
  end

  defp do_tqdm(
         element,
         %{n: n, last_print_n: last_print_n, min_iterations: min_iterations} = state
       )
       when n - last_print_n < min_iterations,
       do: {[element], update_iteration_times(%{state | n: n + 1})}

  defp do_tqdm(element, state) do
    now = System.monotonic_time()
    time_diff = now - state.last_print_time

    state =
      if time_diff >= state.min_interval do
        state
        |> estimate_time_per_iteration()
        |> print_status(now)
        |> Map.merge(%{
          last_print_n: state.n,
          last_print_time: now
        })
      else
        state
      end

    {[element], update_iteration_times(%{state | n: state.n + 1}, now)}
  end

  defp do_tqdm_after(state) do
    state = print_status(state, System.monotonic_time())

    finish =
      if state.clear do
        prefix_length = String.length(state.prefix)
        total_bar_chars = prefix_length + state.last_printed_length

        "\r" <> String.duplicate(" ", total_bar_chars) <> "\r"
      else
        "\n"
      end

    IO.write(state.device, finish)
  end

  defp print_status(state, now) do
    status = format_status(state, now)
    status_length = String.length(status)

    num_padding_chars = max(state.last_printed_length - status_length, 0)
    padding = String.duplicate(" ", num_padding_chars)

    IO.write(state.device, "\r#{state.prefix}#{status}#{padding}")

    %{state | last_printed_length: status_length}
  end

  defp estimate_time_per_iteration(state) do
    moving_avg = state.iteration_times |> Tqdm.LimitedList.avg() |> native_to_seconds()

    time_per_iteration =
      if state.time_per_iteration && moving_avg do
        moving_avg * (1 - @iteration_time_smoothing) +
          state.time_per_iteration * @iteration_time_smoothing
      else
        moving_avg
      end

    %{state | time_per_iteration: time_per_iteration}
  end

  defp native_to_seconds(nil), do: nil

  defp native_to_seconds(dur),
    do: System.convert_time_unit(round(dur), :native, :microsecond) / 1_000_000

  defp format_status(state, now) do
    elapsed_str = format_interval(native_to_seconds(now - state.start_time))
    rate = format_rate(state)

    n = state.n
    total = state.total
    total_segments = state.total_segments

    if n <= total and total != 0 do
      progress = n / total

      num_segments = trunc(progress * total_segments)
      bar = format_bar(num_segments, total_segments)
      percentage = "#{Float.round(progress * 100)}%"

      left = format_left(state)

      "|#{bar}| #{n}/#{total} #{percentage} " <>
        "[elapsed: #{elapsed_str} left: #{left}, #{rate} iters/sec]"
    else
      "#{n} [elapsed: #{elapsed_str}, #{rate} iters/sec]"
    end
  end

  defp format_rate(%{time_per_iteration: nil}), do: "0"
  defp format_rate(%{time_per_iteration: tpi}), do: Float.round(1 / tpi, 2)

  defp format_bar(num_segments, total_segments) do
    String.duplicate("#", num_segments) <>
      String.duplicate("-", total_segments - num_segments)
  end

  defp format_left(%{time_per_iteration: nil}), do: "?"

  defp format_left(%{time_per_iteration: tpi, n: n, total: total}),
    do: format_interval(tpi * (total - n))

  defp format_interval(elapsed) do
    minutes = trunc(elapsed / 60)
    hours = div(minutes, 60)
    rem_minutes = minutes - hours * 60
    micro_seconds = elapsed - minutes * 60
    seconds = trunc(micro_seconds)

    hours_str = format_time_component(hours)
    minutes_str = format_time_component(rem_minutes)
    seconds_str = format_time_component(seconds)

    "#{hours_str}:#{minutes_str}:#{seconds_str}"
  end

  defp format_time_component(time) when time < 10,
    do: "0#{time}"

  defp format_time_component(time),
    do: to_string(time)
end
