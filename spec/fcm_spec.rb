require "spec_helper"

describe FCM do
  let(:project_name) { 'test-project' }
  let(:json_key_path) { 'path/to/json/key.json' }
  let(:api_key) { "LEGACY_KEY" }
  let(:client) { FCM.new(api_key, json_key_path) }

  let(:mock_token) { "access_token" }
  let(:mock_headers) do
    {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{mock_token}",
    }
  end

  before do
    allow(client).to receive(:json_key)

    # Mock the Google::Auth::ServiceAccountCredentials
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).
      and_return(double(fetch_access_token!: { 'access_token' => mock_token }))
  end

  it "should initialize" do
    expect { client }.not_to raise_error
  end

  describe "credentials path" do
    it "can be a path to a file" do
      fcm = FCM.new("test", "README.md")
      expect(fcm.__send__(:json_key).class).to eq(File)
    end

    it "can be an IO object" do
      fcm = FCM.new("test", StringIO.new("hey"))
      expect(fcm.__send__(:json_key).class).to eq(StringIO)
    end
  end

  describe "#send_v1 or #send_notification_v1" do
    let(:client) { FCM.new(api_key, json_key_path, project_name) }

    let(:uri) { "#{FCM::BASE_URI_V1}#{project_name}/messages:send" }

    let(:stub_fcm_send_v1_request) do
      stub_request(:post, uri).with(
        body: { 'message' => send_v1_params }.to_json,
        headers: mock_headers
      ).to_return(
        # ref: https://firebase.google.com/docs/cloud-messaging/http-server-ref#interpret-downstream
        body: "{}",
        headers: {},
        status: 200,
      )
    end

    before do
      stub_fcm_send_v1_request
    end

    shared_examples "succesfuly send notification" do
      it 'should send notification of HTTP V1 using POST to FCM server' do
        client.send_v1(send_v1_params).should eq(
          response: 'success', body: '{}', headers: {}, status_code: 200
        )
        stub_fcm_send_v1_request.should have_been_made.times(1)
      end
    end

    describe "send to token" do
      let(:token) { '4sdsx' }
      let(:send_v1_params) do
        {
          'token' => token,
          'notification' => {
            'title' => 'Breaking News',
            'body' => 'New news story available.'
          },
          'data' => {
            'story_id' => 'story_12345'
          },
          'android' => {
            'notification' => {
              'click_action' => 'TOP_STORY_ACTIVITY',
              'body' => 'Check out the Top Story'
            }
          },
          'apns' => {
            'payload' => {
              'aps' => {
                'category' => 'NEW_MESSAGE_CATEGORY'
              }
            }
          }
        }
      end

      include_examples "succesfuly send notification"
    end

    describe "send to topic" do
      let(:topic) { 'news' }
      let(:send_v1_params) do
        {
          'topic' => topic,
          'notification' => {
            'title' => 'Breaking News',
            'body' => 'New news story available.'
          },
        }
      end

      include_examples "succesfuly send notification"

      context "when topic is invalid" do
        let(:topic) { '/topics/news$' }

        it 'should raise error' do
          stub_fcm_send_v1_request.should_not have_been_requested
        end
      end
    end
  end

  describe '#send_with_notification_key' do
    let(:notification_key) { 'notification_key_123' }
    let(:message_options) do
      {
        notification: {
          title: 'Group Notification',
          body: 'This is a test group notification'
        },
        data: {
          key1: 'value1',
          key2: 'value2'
        }
      }
    end

    it 'sends a group notification successfully' do
      expected_body = {
        to: notification_key,
        notification: {
          title: 'Group Notification',
          body: 'This is a test group notification'
        },
        data: {
          key1: 'value1',
          key2: 'value2'
        }
      }

      stub_request(:post, "#{FCM::BASE_URI}/fcm/send")
        .with(
          body: expected_body.to_json,
          headers: mock_headers
        )
        .to_return(status: 200, body: '{"message_id": 987654321, "success": 3, "failure": 0}', headers: {})

      response = client.send_with_notification_key(notification_key, message_options)

      expect(response[:status_code]).to eq(200)
      expect(response[:response]).to eq('success')
      parsed_body = JSON.parse(response[:body])
      expect(parsed_body['message_id']).to eq(987654321)
      expect(parsed_body['success']).to eq(3)
      expect(parsed_body['failure']).to eq(0)
    end

    it 'handles errors when sending a group notification' do
      stub_request(:post, "#{FCM::BASE_URI}/fcm/send")
        .to_return(status: 400, body: '{"error": "InvalidRegistration"}', headers: {})

      response = client.send_with_notification_key(notification_key, message_options)

      expect(response[:status_code]).to eq(400)
      expect(response[:response]).to eq('Only applies for JSON requests. Indicates that the request could not be parsed as JSON, or it contained invalid fields.')
      expect(JSON.parse(response[:body])['error']).to eq('InvalidRegistration')
    end
  end

  describe "#get_instance_id_info" do
    subject(:get_info) { client.get_instance_id_info(registration_id, options) }

    let(:options) { nil }
    let(:base_uri) { "#{FCM::INSTANCE_ID_API}/iid/info" }
    let(:uri) { "#{base_uri}/#{registration_id}" }
    let(:registration_id) { "42" }

    context 'without options' do
      it 'calls info endpoint' do
        endpoint = stub_request(:get, uri).with(headers: mock_headers)
        get_info
        expect(endpoint).to have_been_requested
      end
    end

    context 'with detail option' do
      let(:uri) { "#{base_uri}/#{registration_id}?details=true" }
      let(:options) { { details: true } }

      it 'calls info endpoint' do
        endpoint = stub_request(:get, uri).with(headers: mock_headers)
        get_info
        expect(endpoint).to have_been_requested
      end
    end
  end

  describe "topic subscriptions" do
    let(:topic) { 'news' }
    let(:registration_id) { "42" }

    describe "#subscribe_instance_id_to_topic" do
      subject(:subscribe) { client.subscribe_instance_id_to_topic(registration_id, topic) }

      let(:uri) { "#{FCM::INSTANCE_ID_API}/iid/v1:batchAdd" }
      let(:params) { { to: "/topics/#{topic}", registration_tokens: [registration_id] } }

      it 'subscribes to a topic' do
        endpoint = stub_request(:post, uri).with(body: params.to_json, headers: mock_headers)
        subscribe
        expect(endpoint).to have_been_requested
      end
    end

    describe "#unsubscribe_instance_id_from_topic" do
      subject(:unsubscribe) { client.unsubscribe_instance_id_from_topic(registration_id, topic) }

      let(:uri) { "#{FCM::INSTANCE_ID_API}/iid/v1:batchRemove" }
      let(:params) { { to: "/topics/#{topic}", registration_tokens: [registration_id] } }

      it 'unsubscribes from a topic' do
        endpoint = stub_request(:post, uri).with(body: params.to_json, headers: mock_headers)
        unsubscribe
        expect(endpoint).to have_been_requested
      end
    end
  end
end
