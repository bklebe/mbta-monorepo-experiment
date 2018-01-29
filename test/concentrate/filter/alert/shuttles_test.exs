defmodule Concentrate.Filter.Alert.ShuttlesTest do
  @moduledoc false
  use ExUnit.Case
  import Concentrate.Filter.Alert.Shuttles
  alias Concentrate.{Alert, Alert.InformedEntity}

  describe "trip_shuttling?/2" do
    setup :supervised

    test "returns a boolean indicating whether the route is being shuttled" do
      alert =
        Alert.new(
          effect: :DETOUR,
          active_period: [
            {5, 10},
            {15, 20}
          ],
          informed_entity: [
            InformedEntity.new(route_type: 1, route_id: "route", stop_id: "stop_id"),
            InformedEntity.new(route_type: 0, route_id: "whole route"),
            InformedEntity.new(route_type: 3, route_id: "bus"),
            InformedEntity.new(
              route_type: 2,
              route_id: "one_direction",
              direction_id: 0,
              stop_id: "stop_id"
            ),
            InformedEntity.new(
              route_type: 2,
              route_id: "ferry",
              direction_id: 1,
              trip_id: "ferry_trip",
              stop_id: "stop_id"
            )
          ]
        )

      handle_events([[alert]], :from, :state)

      assert trip_shuttling?("trip", "route", 0, 5)
      # for now, a whole route shuttle is ignored
      refute trip_shuttling?("trip", "whole route", 0, 20)
      assert trip_shuttling?("trip", "route", 0, {1970, 1, 1})
      # bus/ferry shuttles are handled differently
      refute trip_shuttling?("trip", "bus", 0, 10)
      assert trip_shuttling?("trip", "one_direction", 0, 5)
      refute trip_shuttling?("trip", "one_direction", 1, 5)
      # trip shuttles don't affect other trips on the route
      assert trip_shuttling?("ferry_trip", "ferry", 1, 5)
      refute trip_shuttling?("other_trip", "ferry", 1, 5)
    end
  end

  describe "stop_shuttling_on_route?/1" do
    setup :supervised

    test "returns a boolean indicating whether the route is shuttling a particular stop" do
      alert =
        Alert.new(
          effect: :DETOUR,
          active_period: [
            {5, 10},
            {15, 20}
          ],
          informed_entity: [
            InformedEntity.new(route_type: 2, route_id: "route", stop_id: "stop")
          ]
        )

      handle_events([[alert]], :from, :state)

      assert stop_shuttling_on_route?("route", "stop", 5)
      refute stop_shuttling_on_route?("route", "stop", 21)
      assert stop_shuttling_on_route?("route", "stop", {1970, 1, 1})
    end
  end

  describe "missing ETS table" do
    test "trip_shuttling/3 returns false" do
      refute trip_shuttling?("trip", "route", 0, 0)
    end

    test "stop_shuttling_on_route?/3 returns false" do
      refute stop_shuttling_on_route?("route", "stop", 0)
    end
  end

  defp supervised(_) do
    start_supervised(Concentrate.Filter.Alert.Shuttles)
    :ok
  end
end
