terraform {
  required_version = "~> 1.10"
  required_providers {
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.2"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "msgraph" {}
provider "azuread" {}

data "azuread_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create a regular security group to use as eligible principal
resource "azuread_group" "test_group" {
  display_name     = "PIM-Test-Eligible-Group-${random_string.suffix.result}"
  mail_enabled     = false
  security_enabled = true
}

# Create a role-assignable group (required for PIM)
resource "msgraph_resource" "pim_group" {
  api_version = "v1.0"
  url         = "groups"

  body = {
    displayName         = "PIM-Test-Group-${random_string.suffix.result}"
    mailNickname        = "pimtest${random_string.suffix.result}"
    mailEnabled         = false
    securityEnabled     = true
    isAssignableToRole  = true
    groupTypes          = []
    "owners@odata.bind" = [
      "https://graph.microsoft.com/v1.0/directoryObjects/${data.azuread_client_config.current.object_id}"
    ]
  }

  ignore_missing_property = true
}

# Create eligibility to trigger PIM policy creation
resource "msgraph_resource" "eligibility" {
  api_version = "v1.0"
  url         = "identityGovernance/privilegedAccess/group/eligibilityScheduleRequests"

  body = {
    accessId      = "member"
    action        = "adminAssign"
    groupId       = msgraph_resource.pim_group.id
    principalId   = azuread_group.test_group.object_id
    justification = "Testing PIM policy configuration"
    scheduleInfo = {
      expiration = {
        type     = "afterDuration"
        duration = "P365D"
      }
    }
  }

  ignore_missing_property = true
  depends_on              = [msgraph_resource.pim_group]
}

# Query the PIM policy (created automatically by Microsoft when eligibility is added)
data "msgraph_resource" "pim_policy" {
  api_version = "beta"
  url         = "policies/roleManagementPolicies"

  query_parameters = {
    "$filter" = ["scopeId eq '${msgraph_resource.pim_group.id}' and scopeType eq 'Group'"]
    "$expand" = ["rules"]
  }

  response_export_values = {
    policy_id = "value[0].id"
    rules     = "value[0].rules"
  }

  depends_on = [msgraph_resource.eligibility]
}

# THIS IS THE PROBLEMATIC RESOURCE - PATCH not sent to API
resource "msgraph_update_resource" "enablement_rule" {
  api_version = "beta"
  url         = "policies/roleManagementPolicies/${data.msgraph_resource.pim_policy.output.policy_id}/rules/Enablement_EndUser_Assignment"

  body = {
    "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyEnablementRule"
    id            = "Enablement_EndUser_Assignment"
    enabledRules  = ["Justification", "Ticketing", "MultiFactorAuthentication"]
    target = {
      caller              = "EndUser"
      operations          = ["All"]
      level               = "Assignment"
      inheritableSettings = []
      enforcedSettings    = []
    }
  }
}

# THIS ALSO FAILS - Approval settings not applied
resource "msgraph_update_resource" "approval_rule" {
  api_version = "beta"
  url         = "policies/roleManagementPolicies/${data.msgraph_resource.pim_policy.output.policy_id}/rules/Approval_EndUser_Assignment"

  body = {
    "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyApprovalRule"
    id            = "Approval_EndUser_Assignment"
    target = {
      caller              = "EndUser"
      operations          = ["All"]
      level               = "Assignment"
      inheritableSettings = []
      enforcedSettings    = []
    }
    setting = {
      isApprovalRequired               = true
      isApprovalRequiredForExtension   = false
      isRequestorJustificationRequired = true
      approvalMode                     = "SingleStage"
      approvalStages = [
        {
          approvalStageTimeOutInDays      = 1
          isApproverJustificationRequired = true
          escalationTimeInMinutes         = 0
          primaryApprovers = [
            {
              "@odata.type" = "#microsoft.graph.singleUser"
              userId        = data.azuread_client_config.current.object_id
            }
          ]
          isEscalationEnabled = false
          escalationApprovers = []
        }
      ]
    }
  }
}

output "group_id" {
  value = msgraph_resource.pim_group.id
}

output "policy_id" {
  value = data.msgraph_resource.pim_policy.output.policy_id
}