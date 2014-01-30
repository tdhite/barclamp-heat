# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class HeatService < ServiceObject

  def initialize(thelogger)
    super(thelogger)
    @bc_name = "heat"
  end

# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "rabbitmq", "inst" => role.default_attributes["heat"]["rabbitmq_instance"] }
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["heat"]["keystone_instance"] }
    answer << { "barclamp" => "database", "inst" => role.default_attributes["heat"]["database_instance"] }
    if role.default_attributes["heat"]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes["heat"]["git_instance"] }
    end
    answer
  end

  def create_proposal
    @logger.debug("Heat create_proposal: entering")
    base = super

    base["attributes"][@bc_name]["git_instance"] = find_dep_proposal("git", true)
    base["attributes"][@bc_name]["database_instance"] = find_dep_proposal("database")
    base["attributes"][@bc_name]["rabbitmq_instance"] = find_dep_proposal("rabbitmq")
    base["attributes"][@bc_name]["keystone_instance"] = find_dep_proposal("keystone")

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }

    if nodes.size >= 1
      controller = nodes.find { |n| n.intended_role == "controller" } || nodes.first
      base["deployment"]["heat"]["elements"] = {
        "heat-server" =>  [ controller.name ]
      }
    end

    base["attributes"]["heat"]["keystone_service_password"] = '%012d' % rand(1e12)

    @logger.debug("Heat create_proposal: exiting")
    base
  end

  def validate_proposal_after_save proposal
    validate_one_for_role proposal, "heat-server"

    if proposal["attributes"][@bc_name]["use_gitrepo"]
      validate_dep_proposal_is_active "git", proposal["attributes"][@bc_name]["git_instance"]
    end

    super
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Heat apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    net_svc = NetworkService.new @logger
    tnodes = role.override_attributes["heat"]["elements"]["heat-server"]
    tnodes.each do |n|
      net_svc.allocate_ip "default", "public", "host", n
    end unless tnodes.nil?

    @logger.debug("Heat apply_role_pre_chef_call: leaving")
  end

end