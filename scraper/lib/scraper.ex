defmodule Scraper do
  @moduledoc """
  Documentation for `Scraper`.
  """
  require Logger

  def work(event) do
    Logger.info("Scraper working on #{event}")

    1..5
    |> Enum.random()
    |> :timer.seconds()
    |> Process.sleep()
  end

  def online?(_url) do
    # Pretend to check
    work(nil)

    # Select random return
    Enum.random([false, true, true])
  end
end
