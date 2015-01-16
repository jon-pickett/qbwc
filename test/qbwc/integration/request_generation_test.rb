$:<< File.expand_path(File.dirname(__FILE__) + '/../..')  # (for wash_out_helper.rb)
require 'test_helper.rb'

class RequestGenerationTest < ActionDispatch::IntegrationTest

  def setup
    RequestGenerationTest.app = Rails.application
    Rails.logger = Logger.new('/dev/null')  # or STDOUT
    QBWC.clear_jobs
  end

  def simulate_response(session)
    session.response = <<-EOF
    <?xml version="1.0"?><?qbxml version="7.0"?>
<QBXML>
  <QBXMLMsgsRs onError="stopOnError">
  </QBXMLMsgsRs>
</QBXML>
    EOF
  end

  test "worker with nothing" do
    QBWC.add_job(:integration_test, true, '', QBWC::Worker)
    session = QBWC::Session.new('foo', '')
    assert_nil session.next
  end

  class NilRequestWorker < QBWC::Worker
    def requests
      nil
    end
  end

  test "worker with nil" do
    QBWC.add_job(:integration_test, true, '', NilRequestWorker)
    session = QBWC::Session.new('foo', '')
    assert_nil session.next
    simulate_response(session)
    assert_nil session.next
  end

  class SingleRequestWorker < QBWC::Worker
    def requests
      $SINGLE_REQUESTS_INVOKED_COUNT += 1 if $SINGLE_REQUESTS_INVOKED_COUNT.is_a?(Integer)
      {:foo => 'bar'}
    end
  end

  test "simple request worker" do
    QBWC.add_job(:integration_test, true, '', SingleRequestWorker)
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == false}
    session = QBWC::Session.new('foo', '')
    assert_not_nil session.next
    simulate_response(session)
    assert_nil session.next
  end

  class MultipleRequestWorker < QBWC::Worker
    def requests
      $MULTIPLE_REQUESTS_INVOKED_COUNT += 1 if $MULTIPLE_REQUESTS_INVOKED_COUNT.is_a?(Integer)
      [
        {:foo => 'bar'},
        {:bar => 'foo'}
      ]
    end
  end

  test "multiple request worker" do
    $MULTIPLE_REQUESTS_INVOKED_COUNT = 0

    QBWC.add_job(:integration_test, true, '', MultipleRequestWorker)
    session = QBWC::Session.new('foo', '')
    assert_not_nil session.next
    simulate_response(session)
    assert_not_nil session.next
    simulate_response(session)
    assert_nil session.next

    assert_equal 1, $MULTIPLE_REQUESTS_INVOKED_COUNT
  end

  test 'multiple jobs' do
    $SINGLE_REQUESTS_INVOKED_COUNT   = 0
    $MULTIPLE_REQUESTS_INVOKED_COUNT = 0

    QBWC.add_job(:integration_test_1, true, '', SingleRequestWorker)
    QBWC.add_job(:integration_test_2, true, '', MultipleRequestWorker)
    assert_equal 2, QBWC.jobs.length
    session = QBWC::Session.new('foo', '')

    # one request from SingleRequestWorker
    assert_not_nil session.next
    simulate_response(session)

    # two requests from MultipleRequestWorker
    assert_not_nil session.next
    simulate_response(session)
    assert_not_nil session.next
    simulate_response(session)
    assert_nil session.next

    assert_equal 1, $SINGLE_REQUESTS_INVOKED_COUNT
    assert_equal 1, $MULTIPLE_REQUESTS_INVOKED_COUNT
  end  

  test 'multiple jobs using different request techniques' do
    $MULTIPLE_REQUESTS_INVOKED_COUNT = 0

    QBWC.add_job(:integration_test_1, true, '', SingleRequestWorker)
    QBWC.add_job(:integration_test_2, true, '', MultipleRequestWorker, QBWC_CUSTOMER_ADD_RQ)
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == (job.name == 'integration_test_2')}
    session = QBWC::Session.new('foo', '')

    # one request from SingleRequestWorker
    assert_not_nil session.next
    simulate_response(session)

    # Requests from MultipleRequestWorker are suppressed; instead use one request passed when job added
    assert_not_nil session.next
    simulate_response(session)
    assert_nil session.next

    assert_equal 0, $MULTIPLE_REQUESTS_INVOKED_COUNT
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == (job.name == 'integration_test_2')}
  end

  class ShouldntRunWorker < QBWC::Worker
    def requests
      [
        {:foo => 'bar'},
        {:bar => 'foo'}
      ]
    end

    def should_run?
      false
    end
  end

  test "shouldnt run worker" do
    QBWC.add_job(:integration_test, true, '', ShouldntRunWorker)
    session = QBWC::Session.new('foo', '')
    assert_nil session.next
  end

  $VARIABLE_REQUEST_COUNT = 2
  class VariableRequestWorker < QBWC::Worker
    def requests
      r = []
      $VARIABLE_REQUEST_COUNT.times do
        r << {:foo => 'bar'}
      end
      return r
    end
  end

  test "variable request worker" do
    QBWC.add_job(:integration_test, true, '', VariableRequestWorker)
    session = QBWC::Session.new('foo', '')
    assert_not_nil session.next
    simulate_response(session)
    # The number of requests should be fixed after the job starts.
    $VARIABLE_REQUEST_COUNT = 5
    assert_not_nil session.next
    simulate_response(session)
    assert_nil session.next
  end

  class RequestsArgumentSuppressesRequestWorker < QBWC::Worker
    def requests
      {:foo => 'bar'}
    end
  end

  test "requests argument suppresses request worker" do
    QBWC.add_job(:integration_test, true, '', RequestsArgumentSuppressesRequestWorker, QBWC_CUSTOMER_ADD_RQ)
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == true}
    session = QBWC::Session.new('foo', '')
    request = session.next
    assert_not_nil request
    assert_match /CustomerAddRq.*\/CustomerAddRq/m, request.request
    simulate_response(session)
    assert_nil session.next

    assert_match /CustomerAddRq.*\/CustomerAddRq/m, QBWC::ActiveRecord::Job::QbwcJob.first[:requests][0]
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == true}
  end

  class RequestsArgumentOverridesRequestWorker < QBWC::Worker
    def requests
      nil
    end
  end

  class SimulatedUserModel
    attr_accessor :name
  end

  class RequestsArgumentEstablishesRequestEarlyWorker < QBWC::Worker
    def requests
      nil
    end
  end

  test "requests argument establishes request early" do
    usr = SimulatedUserModel.new
    usr.name = QBWC_USERNAME

    QBWC.add_job(:integration_test, true, '', RequestsArgumentEstablishesRequestEarlyWorker, {:name => usr.name})
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == true}
    usr.name = 'bleech'

    session = QBWC::Session.new('foo', '')
    request = session.next
    assert_match /Name.#{QBWC_USERNAME}.\/Name/, request.request

    assert_equal [{:name => QBWC_USERNAME}], QBWC::ActiveRecord::Job::QbwcJob.first[:requests]
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == true}
  end

  class RequestsArgumentReturnsMultipleRequestsWorker < QBWC::Worker
    def requests
      nil
    end
  end

  test "requests argument returns multiple requests" do
    usr1 = SimulatedUserModel.new
    usr1.name = QBWC_USERNAME

    usr2 = SimulatedUserModel.new
    usr2.name = 'usr2 name'

    multiple_requests = [
      {:name => usr1.name},
      {:name => usr2.name}
    ]
    QBWC.add_job(:integration_test, true, '', RequestsArgumentEstablishesRequestEarlyWorker, multiple_requests)
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == true}
    usr1.name = 'bleech'
    usr2.name = 'bleech'

    session = QBWC::Session.new('foo', '')
    request1 = session.next
    assert_match /Name.#{QBWC_USERNAME}.\/Name/, request1.request
    simulate_response(session)

    request2 = session.next
    assert_match /Name.usr2 name.\/Name/, request2.request
    simulate_response(session)

    assert_nil session.next

    assert_equal [{:name => QBWC_USERNAME}, {:name => 'usr2 name'}], QBWC::ActiveRecord::Job::QbwcJob.first[:requests]
    QBWC.jobs.each {|job| assert job.requests_provided_when_job_added == true}
  end

end
