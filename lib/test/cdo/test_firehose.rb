require_relative '../test_helper'
require 'cdo/firehose'

class FirehoseTest < Minitest::Test
  def setup
    FirehoseClient.log = Logger.new('/dev/null')
    @client = FirehoseClient.client = Aws::Firehose::Client.new(stub_responses: true)
    @stream = :analysis
    @stream_name = FirehoseClient::STREAMS[@stream]
    FirehoseClient.instance.flush!
  end

  def teardown
    # Clear out any state in the client.
    FirehoseClient.instance.flush!
    FirehoseClient.client = nil
  end

  def test_firehose
    FirehoseClient.instance.put_record(@stream, {})
    FirehoseClient.instance.flush!
    api_request = @client.api_requests.first
    assert_equal :put_record_batch, api_request[:operation_name]
    data = JSON.parse(api_request[:params][:records].first[:data])
    assert_equal '"server-side"', data['device']
    assert_equal @stream_name, api_request[:params][:delivery_stream_name]
  end

  def test_firehose_with_multiple_streams
    FirehoseClient::STREAMS.each do |stream, _|
      FirehoseClient.instance.put_record(stream, {})
    end
    FirehoseClient.instance.flush!
    api_requests = @client.api_requests.map do |api_request|
      [api_request[:params][:delivery_stream_name], api_request]
    end.to_h

    FirehoseClient::STREAMS.each do |_, stream_name|
      api_request = api_requests[stream_name]
      assert(api_request, "Firehose put_recode missing for stream_name=#{stream_name}")
      assert_equal :put_record_batch, api_request[:operation_name]
      data = JSON.parse(api_request[:params][:records].first[:data])
      assert_equal '"server-side"', data['device']
      assert_equal stream_name, api_request[:params][:delivery_stream_name]
    end
  end

  # Ensure the calculated #size matches the request length generated by the SDK client.
  def test_firehose_request_size
    records = Array.new(1000) {|n| '*' * n}

    request = Aws::Firehose::Client.new(stub_responses: true).build_request(
      :put_record_batch,
      delivery_stream_name: @stream_name,
      records: records.map {|r| {data: r}}
    )
    request.send_request
    assert_equal request.context.http_request.headers['Content-Length'].to_i,
      FirehoseClient.instance.size(@stream, records)
  end
end
