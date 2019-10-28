require 'active_support/core_ext/string'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class EpsilonGateway < EpsilonBaseGateway
      module CreditType
        SINGLE      = 10
        INSTALLMENT = 61
        REVOLVING   = 80
      end

      PATHS = {
        purchase:                'direct_card_payment.cgi',
        registered_recurring:    'direct_card_payment.cgi',
        registered_purchase:     'direct_card_payment.cgi',
        cancel_recurring:        'receive_order3.cgi',
        terminate_recurring:     'receive_order3.cgi',
        void:                    'cancel_payment.cgi',
        find_user:               'get_user_info.cgi',
        change_recurring_amount: 'change_amount_payment.cgi',
        change_amount: 'change_amount_payment.cgi',
        find_order:              'getsales2.cgi',
      }.freeze

      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      def purchase(amount, credit_card, detail = {})
        detail[:mission_code] = EpsilonMissionCode::PURCHASE

        params = billing_params(amount, credit_card, detail)

        commit(PATHS[:purchase], params)
      end

      def registered_purchase(amount, detail = {})
        params = {
          contract_code: self.contract_code,
          user_id:       detail[:user_id],
          user_name:     detail[:user_name],
          user_mail_add: detail[:user_email],
          item_code:     detail[:item_code],
          item_name:     detail[:item_name],
          order_number:  detail[:order_number],
          st_code:       '10000-0000-0000',
          mission_code:  EpsilonMissionCode::PURCHASE,
          item_price:    amount,
          process_code:  2,
          card_st_code:  detail[:credit_type],
          pay_time:      detail[:payment_time],
          xml:           1,
        }

        params[:memo1] = detail[:memo1] if detail.has_key?(:memo1)
        params[:memo2] = detail[:memo2] if detail.has_key?(:memo2)

        commit(PATHS[:registered_purchase], params)
      end

      def recurring(amount, credit_card, detail = {})
        detail[:mission_code] ||= EpsilonMissionCode::RECURRING_2

        requires!(detail, [:mission_code, *EpsilonMissionCode::RECURRINGS])

        params = billing_params(amount, credit_card, detail)

        commit(PATHS[:purchase], params)
      end

      def registered_recurring(amount, detail = {})
        params = {
          contract_code: self.contract_code,
          user_id:       detail[:user_id],
          user_name:     detail[:user_name],
          user_mail_add: detail[:user_email],
          item_code:     detail[:item_code],
          item_name:     detail[:item_name],
          order_number:  detail[:order_number],
          st_code:       '10000-0000-0000',
          mission_code:  detail[:mission_code],
          item_price:    amount,
          process_code:  2,
          xml:           1,
        }

        params[:memo1] = detail[:memo1] if detail.has_key?(:memo1)
        params[:memo2] = detail[:memo2] if detail.has_key?(:memo2)

        commit(PATHS[:registered_recurring], params)
      end

      def cancel_recurring(user_id:, item_code:)
        params = {
          contract_code: self.contract_code,
          user_id:       user_id,
          item_code:     item_code,
          xml:           1,
          process_code:  8,
        }

        commit(PATHS[:cancel_recurring], params)
      end

      def terminate_recurring(user_id:)
        params = {
          contract_code: self.contract_code,
          user_id:       user_id,
          xml:           1,
          process_code:  9,
        }

        commit(PATHS[:terminate_recurring], params)
      end

      def find_user(user_id:)
        params = {
          contract_code: self.contract_code,
          user_id:       user_id,
        }

        commit(PATHS[:find_user], params)
      end

      def change_recurring_amount(new_item_price:, user_id:, item_code:)
        params = {
          contract_code:  self.contract_code,
          mission_code:   2,
          user_id:        user_id,
          item_code:      item_code,
          new_item_price: new_item_price,
        }
        commit(PATHS[:change_recurring_amount], params)
      end

      def change_amount(new_item_price:, order_number:)
        params = {
          contract_code:  self.contract_code,
          mission_code:   1,
          order_number: order_number,
          new_item_price: new_item_price,
        }
        commit(PATHS[:change_amount], params)
      end

      #
      # Second request for 3D secure
      #
      def authenticate(order_number:, three_d_secure_pa_res:)
        params = {
          contract_code:  self.contract_code,
          order_number:   order_number,
          tds_check_code: 2,
          tds_pares:      three_d_secure_pa_res,
        }

        commit(PATHS[:purchase], params)
      end

      def void(order_number)
        params = {
          contract_code: self.contract_code,
          order_number:  order_number,
        }

        commit(PATHS[:void], params)
      end

      def verify(credit_card, options = {})
        o = options.dup
        o[:order_number] ||= "#{Time.now.to_i}#{options[:user_id]}".first(32)
        o[:item_code] = 'verifycreditcard'
        o[:item_name] = 'verify credit card'

        MultiResponse.run(:use_first_response) do |r|
          r.process { purchase(1, credit_card, o) }
          r.process(:ignore_result) { void(o[:order_number]) }
        end
      end

      def find_order(order_number)
        params = {
          contract_code: self.contract_code,
          order_number:  order_number,
        }

        response_keys = [
          :transaction_code,
          :state,
          :payment_code,
          :item_price,
          :amount,
        ]

        commit(PATHS[:find_order], params, response_keys)
      end

      private

      def billing_params(amount, payment_method, detail)
        params = {
          contract_code:  self.contract_code,
          user_id:        detail[:user_id],
          user_name:      detail[:user_name],
          user_mail_add:  detail[:user_email],
          item_code:      detail[:item_code],
          item_name:      detail[:item_name],
          order_number:   detail[:order_number],
          st_code:        '10000-0000-0000',
          mission_code:   detail[:mission_code],
          item_price:     amount,
          process_code:   1,
          card_number:    payment_method.number,
          expire_y:       payment_method.year,
          expire_m:       payment_method.month,
          card_st_code:   detail[:credit_type],
          pay_time:       detail[:payment_time],
          tds_check_code: detail[:three_d_secure_check_code],
          user_agent:     "#{ActiveMerchant::Epsilon}-#{ActiveMerchant::Epsilon::VERSION}",
        }

        params[:memo1] = detail[:memo1] if detail.has_key?(:memo1)
        params[:memo2] = detail[:memo2] if detail.has_key?(:memo2)

        if detail.has_key?(:token)
          params[:token] = detail[:token]
          params.delete(:card_number)
          params.delete(:expire_y)
          params.delete(:expire_m)
        end

        if payment_method.class.requires_verification_value?
          params.merge!(
            security_code:  payment_method.verification_value,
            security_check: 1, # use security code
          )
        end

        params
      end
    end
  end
end
