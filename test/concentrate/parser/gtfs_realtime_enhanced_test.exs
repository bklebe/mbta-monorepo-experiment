defmodule Concentrate.Parser.GTFSRealtimeEnhancedTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Concentrate.TestHelpers
  import Concentrate.Parser.GTFSRealtimeEnhanced
  alias Concentrate.{TripUpdate, StopTimeUpdate, VehiclePosition, Alert, Alert.InformedEntity}

  describe "parse/1" do
    test "parsing a TripUpdate enhanced JSON file returns only StopTimeUpdate or TripUpdate structs" do
      binary = File.read!(fixture_path("TripUpdates_enhanced.json"))
      parsed = parse(binary, [])
      assert [_ | _] = parsed

      for update <- parsed do
        assert update.__struct__ in [StopTimeUpdate, TripUpdate]
      end
    end

    test "parsing an alerts_enhanced.json file returns only alerts" do
      binary = File.read!(fixture_path("alerts_enhanced.json"))
      parsed = parse(binary, [])
      assert [_ | _] = parsed

      for alert <- parsed do
        assert alert.__struct__ == Alert
      end
    end

    test "parsing an enhanced VehiclePositions JSON file returns only VehiclePosition or TripUpdate structs" do
      binary = File.read!(fixture_path("VehiclePositions_enhanced.json"))
      parsed = parse(binary, [])
      assert [_ | _] = parsed

      for update <- parsed do
        assert update.__struct__ in [VehiclePosition, TripUpdate]
      end
    end

    test "alerts decode all entity fields" do
      body = ~s(
        {
          "entity": [
            {
              "id": "id",
              "alert": {
                "effect": "STOP_MOVED",
                "informed_entity": [
                  {
                    "route_type": 2,
                    "route_id": "CR-Worcester",
                    "trip": {
                      "route_id": "CR-Worcester",
                      "trip_id": "CR-Weekday-Fall-17-516",
                      "direction_id": 1
                    },
                    "stop_id": "Worcester",
                    "activities": [
                      "EXIT",
                      "RIDE"
                    ]
                  }
                ]
              }
            }
          ]
        })
      [alert] = parse(body, [])
      [entity] = Alert.informed_entity(alert)
      assert InformedEntity.route_type(entity) == 2
      assert InformedEntity.route_id(entity) == "CR-Worcester"
      assert InformedEntity.direction_id(entity) == 1
      assert InformedEntity.trip_id(entity) == "CR-Weekday-Fall-17-516"
      assert InformedEntity.stop_id(entity) == "Worcester"
      assert InformedEntity.activities(entity) == ~w(EXIT RIDE)
    end

    test "alerts can decoded the old-format feed" do
      # top-level "alerts" key
      # id and alert data in same object
      # direction ID in the entity directly
      body = ~s(
        {
          "alerts": [
            {
              "id": "id",
              "effect": "STOP_MOVED",
              "informed_entity": [
                {
                  "route_type": 2,
                  "route_id": "CR-Worcester",
                  "direction_id": 1,
                  "stop_id": "Worcester",
                  "activities": [
                    "BOARD",
                    "EXIT",
                    "RIDE"
                  ]
                }
              ]
            }
          ]
        })
      [alert] = parse(body, [])
      assert Alert.id(alert) == "id"
      [entity] = Alert.informed_entity(alert)
      assert InformedEntity.route_type(entity) == 2
      assert InformedEntity.route_id(entity) == "CR-Worcester"
      assert InformedEntity.direction_id(entity) == 1
      assert InformedEntity.stop_id(entity) == "Worcester"
      assert InformedEntity.activities(entity) == ~w(BOARD EXIT RIDE)
    end
  end

  describe "decode_trip_update/1" do
    test "can handle boarding status information" do
      update = %{
        "trip" => %{},
        "stop_time_update" => [
          %{
            "boarding_status" => "ALL_ABOARD"
          }
        ]
      }

      [_tu, stop_update] = decode_trip_update(update)
      assert StopTimeUpdate.status(stop_update) == "ALL_ABOARD"
    end

    test "can handle platform id information" do
      update = %{
        "trip" => %{},
        "stop_time_update" => [
          %{
            "platform_id" => "platform"
          }
        ]
      }

      [_tu, stop_update] = decode_trip_update(update)
      assert StopTimeUpdate.platform_id(stop_update) == "platform"
    end

    test "treats a missing schedule relationship as SCHEDULED" do
      update = %{
        "trip" => %{},
        "stop_time_update" => [
          %{}
        ]
      }

      [tu, stu] = decode_trip_update(update)
      assert TripUpdate.schedule_relationship(tu) == :SCHEDULED
      assert StopTimeUpdate.schedule_relationship(stu) == :SCHEDULED
    end
  end

  describe "decode_vehicle/1" do
    test "returns nothing if there's an empty map" do
      assert decode_vehicle(%{}) == []
    end

    test "decodes a VehiclePosition JSON map" do
      map = %{
        "congestion_level" => nil,
        "current_status" => "STOPPED_AT",
        "current_stop_sequence" => 670,
        "occupancy_status" => nil,
        "position" => %{
          "bearing" => 135,
          "latitude" => 42.32951,
          "longitude" => -71.11109,
          "odometer" => nil,
          "speed" => nil
        },
        "stop_id" => "70257",
        "timestamp" => 1_534_340_406,
        "trip" => %{
          "direction_id" => 0,
          "route_id" => "Green-E",
          "schedule_relationship" => "SCHEDULED",
          "start_date" => "20180815",
          "start_time" => nil,
          "trip_id" => "37165437-X"
        },
        "vehicle" => %{
          "id" => "G-10098",
          "label" => "3823-3605",
          "license_plate" => nil
        }
      }

      assert [tu, vp] = decode_vehicle(map)

      assert tu ==
               TripUpdate.new(
                 trip_id: "37165437-X",
                 route_id: "Green-E",
                 direction_id: 0,
                 start_date: {2018, 8, 15},
                 schedule_relationship: :SCHEDULED
               )

      assert vp ==
               VehiclePosition.new(
                 id: "G-10098",
                 label: "3823-3605",
                 latitude: 42.32951,
                 longitude: -71.11109,
                 bearing: 135,
                 stop_id: "70257",
                 trip_id: "37165437-X",
                 stop_sequence: 670,
                 status: :STOPPED_AT,
                 last_updated: 1_534_340_406
               )
    end
  end
end
