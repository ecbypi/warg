require "test_helper"

class WargHostCollectionTest < Minitest::Test
  def test_from_creates_host_instances_from_strings
    collection = Warg::HostCollection.from("patni@double-a-batteries.com")

    assert_equal uris_from(collection), ["ssh://patni@double-a-batteries.com"]
  end

  def test_from_creates_host_instances_from_arrays_of_host_data
    hosts_data = [
      "martina@napkin-rollers.io",
      %w( jesus@water-faucets.net stage=production app=hydrate ),
      { user: "matt", address: "localhost" }
    ]

    collection = Warg::HostCollection.from(hosts_data)

    assert_equal uris_from(collection), [
      "ssh://martina@napkin-rollers.io",
      "ssh://jesus@water-faucets.net?stage=production&app=hydrate",
      "ssh://matt@localhost"
    ]
  end

  def test_from_creates_host_instances_from_hashes_of_host_data
    hosts_data = {
      "app:coffee-spout" => {
        "production" => [
          %w( spouty@coffee-spout-production-1 type=app )
        ]
      },
      "app:soup-ladle" => {
        "demo" => "soup-ladle@soup-ladle-demo-1",
        "production" => [
          %w( soup-ladle@soup-ladle-production-1 type=app ),
          %w( soup-ladle@soup-ladle-production-2 type=app ),
          %w( soup-ladle@soup-ladle-production-3 type=app )
        ],
        "testing" => %w( soup-ladle@soup-ladle-testing-1 type=app )
      },
      "staging" => "vaccine@vaccination.io?app=vaccinator"
    }

    collection = Warg::HostCollection.from(hosts_data)

    assert_equal uris_from(collection), [
      "ssh://spouty@coffee-spout-production-1?type=app&stage=production&app=coffee-spout",

      "ssh://soup-ladle@soup-ladle-demo-1?stage=demo&app=soup-ladle",

      "ssh://soup-ladle@soup-ladle-production-1?type=app&stage=production&app=soup-ladle",
      "ssh://soup-ladle@soup-ladle-production-2?type=app&stage=production&app=soup-ladle",
      "ssh://soup-ladle@soup-ladle-production-3?type=app&stage=production&app=soup-ladle",

      "ssh://soup-ladle@soup-ladle-testing-1?type=app&stage=testing&app=soup-ladle",

      "ssh://vaccine@vaccination.io?app=vaccinator&stage=staging"
    ]
  end

  def test_from_passes_through_host_collection_instances
    host_collection = Warg::HostCollection.new

    other_collection = Warg::HostCollection.from(host_collection)

    assert_equal host_collection.object_id, other_collection.object_id
  end

  def test_with_method_removes_items_not_matching_all_filters
    hosts_data = {
      "app:coffee-spout" => {
        "production" => [
          %w( spouty@coffee-spout-production-1 type=app )
        ]
      },
      "app:soup-ladle" => {
        "demo" => "soup-ladle@soup-ladle-demo-1",
        "production" => [
          %w( soup-ladle@soup-ladle-production-1 type=app ),
          %w( soup-ladle@soup-ladle-production-2 type=app ),
          %w( soup-ladle@soup-ladle-production-3 type=app )
        ],
        "testing" => %w( soup-ladle@soup-ladle-testing-1 type=app )
      },
      "staging" => "vaccine@vaccination.io?app=vaccinator"
    }

    collection = Warg::HostCollection.from(hosts_data)

    assert_equal collection.length, 7

    filtered_collection = collection.with(app: "soup-ladle", stage: "production")

    assert_equal filtered_collection.length, 3

    extra_filtered_collection = filtered_collection.with(address: "soup-ladle-production-1")

    assert_equal extra_filtered_collection.length, 1
  end

  def test_add_adds_hosts_from_host_data_compatible_with_from
    collection = Warg::HostCollection.new
    collection.add "localhost"
    collection.add %w( meatloaf@rocky-horror app=midnight-showings stage=butta )
    collection.add(
      user: "alexa",
      address: "10.10.2.20",
      port: 20202,
      properties: { app: "climbing-buddy" }
    )

    assert_equal uris_from(collection), [
      "ssh://localhost",
      "ssh://meatloaf@rocky-horror?app=midnight-showings&stage=butta",
      "ssh://alexa@10.10.2.20:20202?app=climbing-buddy"
    ]
  end

  def uris_from(collection)
    collection.map(&:to_s)
  end
end
