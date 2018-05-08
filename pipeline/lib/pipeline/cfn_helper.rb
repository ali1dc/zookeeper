# frozen_string_literal: true

require 'aws-sdk'
require 'pipeline/cfn_helper'

# Pipeline
module Pipeline
  # Provides helper methods for provisioning
  class CloudFormationHelper
    def aws_region
      return 'us-east-1' if ENV['AWS_REGION'].nil?
      ENV['AWS_REGION']
    end

    def cfn_parameters(template_name)
      template_path = 'provisioning'
      {
        stack_name: stack_name,
        capabilities: %w[CAPABILITY_IAM CAPABILITY_NAMED_IAM],
        template_body: File.read("#{template_path}/#{template_name}.yml"),
        parameters: stack_parameters
      }
    end

    def parameter(key, value)
      {
        parameter_key: key,
        parameter_value: value
      }
    end

    def waiter(waiter_name)
      started_at = Time.now

      @cloudformation.wait_until(waiter_name, stack_name: stack_name) do |w|
        w.max_attempts = nil
        w.before_wait do
          throw :failure if Time.now - started_at > 3600
        end
      end

      sleep 180 if waiter_name == :stack_create_complete
    end

    # def keypair
    #   retrieve_or_generate_keypair
    # end

    # def retrieve_or_generate_keypair
    #   key_path = "#{stack_name}.pem"
    #   return stack_name if keypair_exists?(key_path)

    #   delete_old_keypair(key_path) # if keypair_exists?(key_path)

    #   key_material = @ec2.create_key_pair(key_name: stack_name).key_material
    #   File.write(key_path, key_material)
    #   File.chmod(0400, key_path)

    #   stack_name
    # end

    # def keypair_exists?(key_path)
    #   aws_check = !@ec2.describe_key_pairs(key_names: [stack_name])
    #                    .key_pairs.empty?
    #   aws_check && File.exist?(key_path)
    # rescue Aws::EC2::Errors::InvalidKeyPairNotFound
    #   false
    # end

    # def delete_old_keypair(key_path)
    #   @ec2.delete_key_pair(key_name: stack_name)
    #   File.delete(key_path) if File.exist?(key_path)
    # rescue Aws::EC2::Errors::InvalidKeyPairNotFound => error
    #   puts error # noop
    # rescue RuntimeError => error
    #   puts error # noop
    # end

    def stack_exists?
      @cloudformation.describe_stacks(stack_name: stack_name)
      true
    rescue Aws::CloudFormation::Errors::ValidationError
      false
    end

    # def connector_sg
    #   @cloudformation.describe_stack_resource(
    #     stack_name: ENV['STACK_NAME'],
    #     logical_resource_id: 'JenkinsConnector'
    #   ).stack_resource_detail.physical_resource_id
    # end
  end
end
