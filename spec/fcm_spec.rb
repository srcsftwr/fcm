require "spec_helper"

describe FCM do
  let(:group_notification_base_uri) { "#{FCM::GROUP_NOTIFICATION_BASE_URI}/gcm/notification" }
  let(:api_key) { "LEGACY_KEY" }
  let(:registration_id) { "42" }
  let(:registration_ids) { ["42"] }
  let(:key_name) { "appUser-Chris" }
  let(:project_id) { "123456789" } # https://developers.google.com/cloud-messaging/gcm#senderid
  let(:notification_key) { "APA91bGHXQBB...9QgnYOEURwm0I3lmyqzk2TXQ" }
  let(:valid_topic) { "TopicA" }
  let(:invalid_topic) { "TopicA$" }
  let(:valid_condition) { "'TopicA' in topics && ('TopicB' in topics || 'TopicC' in topics)" }
  let(:invalid_condition) { "'TopicA' in topics and some other text ('TopicB' in topics || 'TopicC' in topics)" }
  let(:invalid_condition_topic) { "'TopicA$' in topics" }

  let(:project_name) { 'test-project' }
  let(:json_key_path) { 'path/to/json/key.json' }

  let(:mock_token) { "access_token" }
  let(:mock_headers) do
    {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{mock_token}",
    }
  end

  before do
    # Mock the Google::Auth::ServiceAccountCredentials
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).
      and_return(double(fetch_access_token!: { 'access_token' => mock_token }))
  end

  it "should initialize" do
    expect { FCM.new(api_key, json_key_path) }.not_to raise_error
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
    let(:send_v1_params) do
      {
        'token' => '4sdsx',
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
      allow(client).to receive(:json_key)

      stub_fcm_send_v1_request
    end

    it 'should send notification of HTTP V1 using POST to FCM server' do
      client.send_v1(send_v1_params).should eq(
        response: 'success', body: '{}', headers: {}, status_code: 200
      )
      stub_fcm_send_v1_request.should have_been_made.times(1)
    end
  end

  describe "#get_instance_id_info" do
    subject(:get_info) { client.get_instance_id_info(registration_id, options) }

    let(:client) { FCM.new(api_key, json_key_path) }
    let(:options) { nil }
    let(:base_uri) { "#{FCM::INSTANCE_ID_API}/iid/info" }
    let(:uri) { "#{base_uri}/#{registration_id}" }

    before do
      allow(client).to receive(:json_key)
    end

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
    describe "#subscribe_instance_id_to_topic" do
      subject(:subscribe) { client.subscribe_instance_id_to_topic(registration_id, valid_topic) }

      let(:client) { FCM.new(api_key, json_key_path) }
      let(:uri) { "#{FCM::INSTANCE_ID_API}/iid/v1:batchAdd" }
      let(:params) { { to: "/topics/#{valid_topic}", registration_tokens: [registration_id] } }

      before do
        allow(client).to receive(:json_key)
      end

      it 'subscribes to a topic' do
        endpoint = stub_request(:post, uri).with(body: params.to_json, headers: mock_headers)
        subscribe
        expect(endpoint).to have_been_requested
      end
    end

    describe "#unsubscribe_instance_id_from_topic" do
      subject(:unsubscribe) { client.unsubscribe_instance_id_from_topic(registration_id, valid_topic) }

      let(:client) { FCM.new(api_key, json_key_path) }
      let(:uri) { "#{FCM::INSTANCE_ID_API}/iid/v1:batchRemove" }
      let(:params) { { to: "/topics/#{valid_topic}", registration_tokens: [registration_id] } }

      before do
        allow(client).to receive(:json_key)
      end

      it 'unsubscribes from a topic' do
        endpoint = stub_request(:post, uri).with(body: params.to_json, headers: mock_headers)
        unsubscribe
        expect(endpoint).to have_been_requested
      end
    end
  end
end
