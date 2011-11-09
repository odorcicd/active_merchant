module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class SamuraiGateway < Gateway

      self.homepage_url = 'https://samurai.feefighters.com'
      self.display_name = 'Samurai'
      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :jcb, :diners_club]
      self.default_currency = 'USD'
      self.money_format = :dollars

      def initialize(options = {})
        begin
          require 'samurai'
        rescue LoadError
          raise "Could not load the samurai gem (>= 0.2.24).  Use `gem install samurai` to install it."
        end

        requires!(options, :login, :password, :processor_token)
        @options = options
        Samurai.options = {
          :merchant_key       => options[:login],
          :merchant_password  => options[:password],
          :processor_token    => options[:processor_token]
        }
      end

      def test?
        @options[:test] || super
      end

      def authorize(money, credit_card_or_vault_id, options = {})
        token = payment_method_token(credit_card_or_vault_id, options)
        return token if token.is_a?(Response)

        authorize = Samurai::Processor.authorize(token, amount(money), processor_options(options))
        handle_result(authorize)
      end

      def purchase(money, credit_card_or_vault_id, options = {})
        token = payment_method_token(credit_card_or_vault_id, options)
        return token if token.is_a?(Response)

        purchase = Samurai::Processor.purchase(token, amount(money), processor_options(options))
        handle_result(purchase)
      end

      def capture(money, authorization_id, options = {})
        authorization = Samurai::Transaction.find(authorization_id)
        handle_result(authorization.capture(amount(money)))
      end

      def refund(money, transaction_id, options = {})
        transaction = Samurai::Transaction.find(transaction_id)
        handle_result(transaction.credit(amount(money)))
      end

      def void(money, transaction_id, options = {})
        void = Samurai::Processor.void(transaction_id, amount(money), process_options(options))
        handle_result(void)
      end

      def store(creditcard, options = {})
        options[:billing_address] ||= {}

        result = Samurai::PaymentMethod.create({
          :card_number  => creditcard.number,
          :expiry_month => creditcard.month.to_s.rjust(2, "0"),
          :expiry_year  => creditcard.year.to_s,
          :cvv          => creditcard.verification_value,
          :first_name   => creditcard.first_name,
          :last_name    => creditcard.last_name,
          :address_1    => options[:billing_address][:address1],
          :address_2    => options[:billing_address][:address2],
          :city         => options[:billing_address][:city],
          :zip          => options[:billing_address][:zip],
          :sandbox      => test?
        })

        Response.new(result.is_sensitive_data_valid,
                     message_from_result(result),
                     { :payment_method_token => result.is_sensitive_data_valid && result.payment_method_token })
      end

      private

      def payment_method_token(credit_card_or_vault_id, options)
        return credit_card_or_vault_id if credit_card_or_vault_id.is_a?(String)
        store_result = store(credit_card_or_vault_id, options)
        store_result.success? ? store_result.params["payment_method_token"] : store_result
      end

      def handle_result(result)
        response_params, response_options = {}, {}
        if result.success?
          response_options[:test] = test?
          response_options[:authorization] = result.reference_id
          response_params[:reference_id] = result.reference_id
          response_params[:transaction_token] = result.transaction_token
          response_params[:payment_method_token] = result.payment_method.payment_method_token
        end

        # TODO: handle cvv here
        response_options[:avs_result] = { :code => result.processor_response && result.processor_response.avs_result_code }
        message = message_from_result(result)
        Response.new(result.success?, message, response_params, response_options)
      end

      def message_from_result(result)
        if result.success?
          "OK"
        else
          result.errors.map {|_, messages| messages }.flatten.join(" ")
        end
      end

      def processor_options(options)
        {
          :billing_reference   => options[:billing_reference],
          :customer_reference  => options[:customer_reference],
          :custom              => options[:custom],
          :descriptor          => options[:descriptor],
        }
      end
    end
  end
end
