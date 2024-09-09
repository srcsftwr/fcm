require "spec_helper"

describe FCM do
  let(:project_name) { 'test-project' }
  let(:json_key_path) { 'path/to/json/key.json' }
  let(:client) { FCM.new(json_key_path) }

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
      fcm = FCM.new("README.md")
      expect(fcm.__send__(:json_key).class).to eq(File)
    end

    it "can be an IO object" do
      fcm = FCM.new(StringIO.new("hey"))
      expect(fcm.__send__(:json_key).class).to eq(StringIO)
    end
  end

  describe "#send_v1 or #send_notification_v1" do
    let(:client) { FCM.new(json_key_path, project_name) }

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

    describe "send to condition" do
      let(:condition) { "'foo' in topics" }
      let(:send_v1_params) do
        {
          'condition' => condition,
          'notification' => {
            'title' => 'Breaking News',
            'body' => 'New news story available.'
          },
        }
      end

      include_examples "succesfuly send notification"
    end
  end

  describe "#send_to_topic" do
    let(:client) { FCM.new(json_key_path, project_name) }

    let(:uri) { "#{FCM::BASE_URI_V1}#{project_name}/messages:send" }

    let(:topic) { 'news' }
    let(:params) do
      {
        'topic' => topic
      }.merge(options)
    end
    let(:options) do
      {
        'data' => {
          'story_id' => 'story_12345'
        }
      }
    end

    let(:stub_fcm_send_to_topic_request) do
      stub_request(:post, uri).with(
        body: { 'message' => params }.to_json,
        headers: mock_headers
      ).to_return(
        body: "{}",
        headers: {},
        status: 200,
      )
    end

    before do
      stub_fcm_send_to_topic_request
    end

    it 'should send notification to topic using POST to FCM server' do
      client.send_to_topic(topic, options).should eq(
        response: 'success', body: '{}', headers: {}, status_code: 200
      )
      stub_fcm_send_to_topic_request.should have_been_made.times(1)
    end
  end

  describe "#send_to_topic_condition" do
    let(:client) { FCM.new(json_key_path, project_name) }

    let(:uri) { "#{FCM::BASE_URI_V1}#{project_name}/messages:send" }

    let(:topic_condition) { "'foo' in topics" }
    let(:params) do
      {
        'condition' => topic_condition
      }.merge(options)
    end
    let(:options) do
      {
        'data' => {
          'story_id' => 'story_12345'
        }
      }
    end

    let(:stub_fcm_send_to_topic_condition_request) do
      stub_request(:post, uri).with(
        body: { 'message' => params }.to_json,
        headers: mock_headers
      ).to_return(
        body: "{}",
        headers: {},
        status: 200,
      )
    end

    before do
      stub_fcm_send_to_topic_condition_request
    end

    it 'should send notification to topic_condition using POST to FCM server' do
      client.send_to_topic_condition(topic_condition, options).should eq(
        response: 'success', body: '{}', headers: {}, status_code: 200
      )
      stub_fcm_send_to_topic_condition_request.should have_been_made.times(1)
    end
  end

  describe "#get_instance_id_info" do
    subject(:get_info) { client.get_instance_id_info(registration_token, options) }

    let(:options) { nil }
    let(:base_uri) { "#{FCM::INSTANCE_ID_API}/iid/info" }
    let(:uri) { "#{base_uri}/#{registration_token}" }
    let(:registration_token) { "42" }

    context 'without options' do
      it 'calls info endpoint' do
        endpoint = stub_request(:get, uri).with(headers: mock_headers)
        get_info
        expect(endpoint).to have_been_requested
      end
    end

    context 'with detail option' do
      let(:uri) { "#{base_uri}/#{registration_token}?details=true" }
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
    let(:registration_token) { "42" }
    let(:registration_token_2) { "43" }
    let(:registration_tokens) { [registration_token, registration_token_2] }

    describe "#topic_subscription" do
      subject(:subscribe) { client.topic_subscription(topic, registration_token) }

      let(:uri) { "#{FCM::INSTANCE_ID_API}/iid/v1/#{registration_token}/rel/topics/#{topic}" }

      it 'subscribes to a topic' do
        endpoint = stub_request(:post, uri).with(headers: mock_headers)
        subscribe
        expect(endpoint).to have_been_requested
      end
    end

    describe "#topic_unsubscription" do
      subject(:unsubscribe) { client.topic_unsubscription(topic, registration_token) }

      let(:uri) { "#{FCM::INSTANCE_ID_API}/iid/v1:batchRemove" }
      let(:params) { { to: "/topics/#{topic}", registration_tokens: [registration_token] } }

      it 'unsubscribes from a topic' do
        endpoint = stub_request(:post, uri).with(body: params.to_json, headers: mock_headers)
        unsubscribe
        expect(endpoint).to have_been_requested
      end
    end

    describe "#batch_topic_subscription" do
      subject(:batch_subscribe) { client.batch_topic_subscription(topic, registration_tokens) }

      let(:uri) { "#{FCM::INSTANCE_ID_API}/iid/v1:batchAdd" }
      let(:params) { { to: "/topics/#{topic}", registration_tokens: registration_tokens } }

      it 'subscribes to a topic' do
        endpoint = stub_request(:post, uri).with(body: params.to_json, headers: mock_headers)
        batch_subscribe
        expect(endpoint).to have_been_requested
      end
    end

    describe "#batch_topic_unsubscription" do
      subject(:batch_unsubscribe) { client.batch_topic_unsubscription(topic, registration_tokens) }

      let(:uri) { "#{FCM::INSTANCE_ID_API}/iid/v1:batchRemove" }
      let(:params) { { to: "/topics/#{topic}", registration_tokens: registration_tokens } }

      it 'unsubscribes from a topic' do
        endpoint = stub_request(:post, uri).with(body: params.to_json, headers: mock_headers)
        batch_unsubscribe
        expect(endpoint).to have_been_requested
      end
    end
  end
end
